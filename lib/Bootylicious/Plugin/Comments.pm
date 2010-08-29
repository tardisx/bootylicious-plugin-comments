package Bootylicious::Plugin::Comments;

use strict;
use warnings;
use base 'Mojolicious::Plugin';

use Mail::Send;
use Mojo::ByteStream 'b';

our $VERSION     = '0.01';
our $CODE_LENGTH = 6;
our $email;

__PACKAGE__->attr( 'public_uri'        => '/' );
__PACKAGE__->attr( 'string_to_replace' => '%INSERT_COMMENTS_HERE%' );
__PACKAGE__->attr( 'email'             => undef );

sub register {
    my ( $self, $app, $args ) = @_;
    $args ||= {};

    $self->public_uri( $args->{'public_uri'} ) if $args->{'public_uri'};
    $self->string_to_replace( $args->{'string_to_replace'} )
        if $args->{'string_to_replace'};
    if ( defined $args->{'email'} ) {
        $self->email( $args->{'email'} );
        $email = $args->{'email'}; # ugly, but don't know how to get this to
                                   # the request otherwise...
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
        ->name('delete')->to( cb => \&del_comment );

    # Approving them.
    $app->routes->route('/comment/approve/:article/:timestamp/:code')
        ->name('approve')->to( cb => \&app_comment );

    $app->log->debug("Registered");
}

sub add_comment {
    my $self    = shift;

    my $author  = $self->param('author');
    my $comment = $self->param('comment');
    my $ip      = $self->tx->remote_address;
    my $article = $self->param('article');

    my $timestamp = time();
    my $code      = _random_code();

    return $self->render_not_found unless ($article);

    my $comments_dir = _comments_dir($article);
    return $self->render_not_found unless ( -d $comments_dir );

    my $comment_filename = "$timestamp-$code";

    # escape the things that will be re-rendered later.
    $author  = b($author)->html_escape;
    $comment = b($comment)->html_escape;
    
    my $filename = "$comments_dir/$comment_filename" . "-unmoderated.md";
    open( my $fh, ">", $filename ) || die;
    print $fh "author: $author\n";
    print $fh "ip: $ip\n";
    print $fh "\n";
    print $fh "$comment\n";
    print $fh "-----\n";
    close $fh;

    my $url_approve = $self->url_for(
        'approve',
        article   => $article,
        timestamp => $timestamp,
        code      => $code,
    )->to_abs();
    my $url_delete = $self->url_for(
        'delete',
        article   => $article,
        timestamp => $timestamp,
        code      => $code,
    )->to_abs();

    $self->app->log->debug("Approve: $url_approve");
    $self->app->log->debug("Delete:  $url_delete");

    my $msg = Mail::Send->new(
        Subject => 'New Comment',
        To      => $email,
    );

    $fh = $msg->open();
    print $fh "Author: $author\n";
    print $fh "IP:     $ip\n";
    print $fh "\n";
    print $fh "$comment\n\n";
    print $fh "Approve: $url_approve\n";
    print $fh "Delete:  $url_delete\n";
    close $fh;

    # setup the confirmation page
    $self->stash( 'layout',      'wrapper' );
    $self->stash( 'title',       'Comment added' );
    $self->stash( 'description', '' );
    return $self->render( text =>
            '<p>Thanks for your comment - it will be moderated soon.</p>' );
}



sub app_comment {
    my $self      = shift;
    my $article   = $self->stash('article');
    my $timestamp = $self->stash('timestamp');
    my $code      = $self->stash('code');

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
    my $self      = shift;
    my $article   = $self->stash('article');
    my $timestamp = $self->stash('timestamp');
    my $code      = $self->stash('code');

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
    my $comments_dir = _comments_dir( _article_name($article) );

    my $body        = $c->res->body;
    my $str_replace = $self->string_to_replace;

    if ( $body !~ /$str_replace/ms ) {
        $c->app->log->debug("No $str_replace tag- doing nothing");
        return;
    }

    if ( !-d $comments_dir ) {
        $c->app->log->debug("No comments folder at $comments_dir - creating");
        mkdir $comments_dir || die $!;
    }

    my $comment_html = "<h2>Comments on this entry:</h2>";
    my $num_comments = 0;
    foreach my $comment_file ( glob "$comments_dir/*.md" ) {
        next if ( $comment_file =~ /unmoderated/ );
        my ( $timestamp, $ext ) = $comment_file =~ /(\d+)\-\w+\.(\w+)$/;
        open my $comment_fh, "<", $comment_file || die;

        # parse metadata
        my $metadata = {};
        while ( my $line = <$comment_fh> ) {
            last if ( $line =~ /^$/ );
            my ( $key, $val ) = $line =~ /^(\w+):\s*(.*)$/;
            if ( $key && defined $val ) {
                $metadata->{$key} = $val;
            }
        }

        # get a parser depending on extension
        my $parser = main::_get_parser($ext);
        die "no parser for $ext" if ( !$parser );

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
        $num_comments++;
    }

    $comment_html .= "<p>[ no comments yet ]</p>"
        if ( !$num_comments );

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
    my $article_name = shift;

    # sanity check the name.... I'm not sure what the allowed values are
    # so we are going to just get brutal... anything but \w and - are
    # fatal.
    die "bad article name $article_name" if ( $article_name =~ /[^\w\-]/ );

    my $comments_dir = "comments/$article_name";
    return $comments_dir;
}

sub _random_code {
    my @chars = ( 0 .. 9, 'A' .. 'Z' );
    my $string = '';
    foreach ( 1 .. $CODE_LENGTH ) {
        $string .= $chars[ rand(@chars) ];
    }
    return $string;
}

1;

__DATA__

@@ a_comment.html.ep
<hr />
<h4><%= $author %> wrote on <%= $timestamp %>:</h4>
<%== $content %>

@@ comment_form.html.ep
<h2>Add your own comment:</h2>
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

=head1 VERSION

version 0.07

=head1 SYNOPSIS

Configuration is done in the bootylicious config file. Parameters are
passed to the plugins constructors.  Register the comments plugin in a
configuration file (bootylicious.conf) by adding a line like this:

    "plugins" : [
        "comments", {
            "email" : "someone@example.com"
        }
    ]

Create article (e.g., 20090903-subversive.pod):

    =head1 NAME

    Subversive exciting article here!

    Add a comment if you dare!

    [ cut ]

    %INSERT_COMMENTS_HERE%

Create a directory 'comments' in the root of your bootylicious install.
Create a subdirectory with the name of the article - so in this example:

    mkdir comments
    mkdir comments/20090903-subversive

Comments will not appear unless both the directory exists and the
%INSERT_COMMENTS_HERE% tag is inserted.

=head1 DESCRIPTION

L<Bootylicious::Plugin::Comments> - Comments plugin for Bootylicious (One-file
blog engine software on Mojo steroids!)

=head1 ATTRIBUTES

=head2 C<public_uri>

Set to public image URL (the same directory as bootylicious.conf publicdir, as
seen by the web browser)

    '/' by default

=head2 C<string_to_replace>

String that is replaced by the comments.

    '%INSERT_GALLERY_HERE%' by default

=head2 C<email>

The email address you want moderation emails to be sent to. It is mandatory.

=head1 AUTHOR

Justin Hawkins, C<< <justin@hawkins.id.au> >>

=head1 SEE ALSO

L<http://getbootylicious.org>, L<bootylicious>, L<Mojo>, L<Mojolicious>, L<Mojolicious::Lite>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Justin Hawkins, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

    
