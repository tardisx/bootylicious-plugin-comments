package Bootylicious::Plugin::Comments;

use strict;
use warnings;
use base 'Mojolicious::Plugin';

our $VERSION = '0.01';
our $CODE_LENGTH = 6;

__PACKAGE__->attr( 'public_uri'        => '/' );
__PACKAGE__->attr( 'string_to_replace' => '%INSERT_COMMENTS_HERE%' );
;    #  build the list of valid image types

sub register {
    my ( $self, $app, $args ) = @_;
    $args ||= {};

    $self->public_uri( $args->{'public_uri'} ) if $args->{'public_uri'};
    $self->string_to_replace( $args->{'string_to_replace'} )
        if $args->{'string_to_replace'};

    # Replace the placeholder with the actual comments.
    $app->plugins->add_hook(
        after_dispatch => sub { shift; $self->show_comments(@_) } );

    # Add a route for adding comments.
    $app->routes->route('/comment/add')->to( cb => \&add_comment );

    # Deleting them.
    $app->routes->route('/comment/delete/:article/:timestamp')
                ->to( cb => \&del_comment );

}

sub add_comment {
    my $self    = shift;
    my $user    = $self->param('author');
    my $comment = $self->param('comment');
    my $ip      = $self->tx->remote_address;
    my $article = $self->param('article');

    my $timestamp = time();

    my $comments_dir = _comments_dir($article);
    die unless ( -d $comments_dir );

    my $filename = "$comments_dir/$timestamp-" . _random_code() .
                   "-unmoderated.md";
    open( my $fh, ">", $filename ) || die;
    print $fh "author: $user\n";
    print $fh "ip: $ip\n";
    print $fh "\n";
    print $fh "$comment\n";
    close $fh;

    $self->res->code(200);
    $self->res->body("THANKS for your comment");

    return 1;
}

sub del_comment {
    my $self = shift;
    my $article = $self->stash('article');
    my $timestamp = $self->stash('timestamp');
    warn "ready to delete";

    $self->res->code(200);
    $self->res->body("deleting $article $timestamp");
    return 1;
}

sub show_comments {
    my $self = shift;
    my $c    = shift;
    my $path = $c->req->url->path;

    # I think this is smelly - can't this be overridden?
    return unless $path =~ /^\/articles/;

    my $article      = $c->stash('article');
    my $comments_dir = _comments_dir(_article_name($article));

    if ( !-d $comments_dir ) {
        $c->app->log->debug("No comments folder at $comments_dir");
        return;
    }

    my $comment_html = "<hr />";
    foreach my $comment_file ( glob "$comments_dir/*.md" ) {
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

    my $body        = $c->res->body;
    my $str_replace = $self->string_to_replace;
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
