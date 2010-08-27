package Bootylicious::Plugin::Comments;

use strict;
use warnings;
use base 'Mojolicious::Plugin';

use Mail::Send;

our $VERSION = '0.01';
our $CODE_LENGTH = 6;

__PACKAGE__->attr( 'public_uri'        => '/' );
__PACKAGE__->attr( 'string_to_replace' => '%INSERT_COMMENTS_HERE%' );
__PACKAGE__->attr( 'email'             => undef );

sub register {
    my ( $self, $app, $args ) = @_;
    $args ||= {};

    $self->public_uri( $args->{'public_uri'} ) if $args->{'public_uri'};
    $self->string_to_replace( $args->{'string_to_replace'} )
        if $args->{'string_to_replace'};
    if (defined $args->{'email'}) {
      $self->email( $args->{'email'} );
    }
    else {
      die "you absolutely must define an email address";
    }

    # Replace the placeholder with the actual comments.
    $app->plugins->add_hook(
        after_dispatch => sub { shift; $self->show_comments(@_) } );

    # Add a route for adding comments.
    $app->routes->route('/comment/add')->to( cb => \&add_comment );

    # Deleting them.
    $app->routes->route('/comment/delete/:article/:timestamp/:code')
                ->name('delete')
                ->to( cb => \&del_comment );

    # Approving them.
    $app->routes->route('/comment/approve/:article/:timestamp/:code')
                ->name('approve')
                ->to( cb => \&app_comment );

    $app->log->debug("Registered");
}

sub add_comment {
    my $self    = shift;
    my $user    = $self->param('author');
    my $comment = $self->param('comment');
    my $ip      = $self->tx->remote_address;
    my $article = $self->param('article');

    my $timestamp = time();
    my $code = _random_code();

    my $comments_dir = _comments_dir($article);
    die unless ( -d $comments_dir );

    my $comment_filename = "$timestamp-$code";

    my $filename = "$comments_dir/$comment_filename".
                   "-unmoderated.md";
    open( my $fh, ">", $filename ) || die;
    print $fh "author: $user\n";
    print $fh "ip: $ip\n";
    print $fh "\n";
    print $fh "$comment\n";
    print $fh "-----\n";
    close $fh;

    $self->res->code(200);
    $self->res->body("THANKS for your comment");

    my $msg = Mail::Send->new(Subject => 'New Comment', 
                              To      => 'justin@hawkins.id.au');
    $fh = $msg->open();
    print $fh "Author: $user\n";
    print $fh "IP:     $ip\n";
    print $fh "\n";
    print $fh "$comment\n\n";
    print $fh "APPROVE: " . $self->url_for('approve',
                                           article   => $article,
                                           timestamp => $timestamp,
                                           code      => $code,
                                          )->to_abs() . "\n";
    print $fh "DELETE: "  . $self->url_for('delete',
                                           article   => $article,
                                           timestamp => $timestamp,
                                           code      => $code,
                                          )->to_abs() . "\n";
    close $fh;

    return 1;
}

sub app_comment {
    my $self = shift;
    my $article = $self->stash('article');
    my $timestamp = $self->stash('timestamp');
    my $code = $self->stash('code');

    $timestamp =~ s/[^\d]//g;
    $code      =~ s/[^\w]//g;

    my $comments_dir = _comments_dir($article);
    die unless ( -d $comments_dir );

    my $comment_file     = "$comments_dir/$timestamp-$code-unmoderated.md";
    my $new_comment_file = "$comments_dir/$timestamp-$code.md";

    $self->res->code(200);
    $self->res->body("approving $comment_file");
    rename $comment_file, $new_comment_file;
    return 1;
}

sub del_comment {
    my $self = shift;
    my $article = $self->stash('article');
    my $timestamp = $self->stash('timestamp');
    my $code = $self->stash('code');

    $timestamp =~ s/[^\d]//g;
    $code      =~ s/[^\w]//g;

    my $comments_dir = _comments_dir($article);
    die unless ( -d $comments_dir );

    my $comment_file = "$comments_dir/$timestamp-$code-unmoderated.md";

    $self->res->code(200);
    $self->res->body("deleting $comment_file");
    unlink $comment_file;
    return 1;
}

sub show_comments {
    my $self = shift;
    my $c    = shift;
    my $path = $c->req->url->path;

    $c->app->log->debug("Starting show_comments");

    # I think this is smelly - can't this be overridden?
    return unless $path =~ /^\/articles/;

    my $article      = $c->stash('article');
    my $comments_dir = _comments_dir(_article_name($article));

    my $body        = $c->res->body;
    my $str_replace = $self->string_to_replace;

    if ($body !~ /$str_replace/ms) {
        $c->app->log->debug("No $str_replace tag- doing nothing");
        return;
    }

    if ( !-d $comments_dir ) {
        $c->app->log->debug("No comments folder at $comments_dir - creating");
        mkdir $comments_dir || die $!;
    }

    my $comment_html = "<hr />";
    foreach my $comment_file ( glob "$comments_dir/*.md" ) {
        next if ($comment_file =~ /unmoderated/);
        my ( $timestamp, $ext ) = 
          $comment_file =~ /(\d+)\-\w+\.(\w+)$/;
        open my $comment_fh, "<", $comment_file || die;

        # parse metadata
        my $metadata = {};
        while ( my $line = <$comment_fh> ) {
            last if ( $line =~ /^$/ );
            my ( $key, $val ) = $line =~ /^(\w+):\s*(.*)$/;
            if ( $key && defined $val ) {
                warn "$key $val";
                $metadata->{$key} = $val;
            }
        }

        # get a parser depending on extension
        my $parser = main::_get_parser($ext);
        die if ( !$parser );

        my $to_be_parsed;
        while (<$comment_fh>) {
            $to_be_parsed .= $_;
        }
        $c->stash(
            'author'    => $metadata->{author},
            'timestamp' => scalar localtime($timestamp),
            'content'   => &$parser( undef, $to_be_parsed )
        );
        $comment_html .= $c->render_partial( 'a_comment',
            template_class => __PACKAGE__ );
    }

    $comment_html .= $c->render_partial(
        'comment_form',
        article        => _article_name($article),
        template_class => __PACKAGE__
    );

    $body =~ s/$str_replace/$comment_html/;

    $c->res->body($body);

}

sub _article_name {
    my $article = shift;

    my $name = sprintf( "%d%02d%02d-%s",
        $article->{year}, $article->{month},
        $article->{day},  $article->{name} );
    return $name;
}

sub _comments_dir {
    my $article_name       = shift;

    my $comments_dir = "comments/$article_name";
    return $comments_dir;
}

sub _random_code {
    my @chars = (0..9, 'A'..'Z');
    my $string = '';
    foreach (1..$CODE_LENGTH) {
        $string .= $chars[rand(@chars)];
    }
    return $string;
}

1;

__DATA__

@@ a_comment.html.ep
<h2><%= $author %> wrote on <%= $timestamp %>:</h2>
<%== $content %>
<hr />

@@ comment_form.html.ep
<form method="POST" action="/comment/add">
<input type="hidden" name="article" value="<%= $article %>">
Your Name: <input type="text" name="author" ><br />
Your email: <input type="text" name="email" > (optional)<br />
<textarea rows="4" cols="80" name="comment">
</textarea><br />
<input type="submit">
</form>

__END__

=head1 NAME

Bootylicious::Plugin::Comments

=cut
