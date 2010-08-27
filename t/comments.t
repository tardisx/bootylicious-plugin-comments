#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 13;

use Mojolicious::Lite;
use Test::Mojo;

push @{ app->plugins->namespaces }, 'Bootylicious::Plugin';
plugin comments => { email => 'nobody@icanteverberesolved.com' };

app->log->level('error');

my $path         = '/articles/2010/08/test.html';
my $article_name = '20100812-test';

get $path => 'article';

# basic GET tests
my $t = Test::Mojo->new;
$t->get_ok($path)->status_is(200)

    # has the form, type post
    ->content_like(qr{form.*POST.*/comment/add})

    # has the hidden article field
    ->content_like(qr{input.*hidden.*name.*article.*value="$article_name"});

# make a comment dir
ok( do { mkdir "comments", 0777 }, 'mkdir' );
ok( do { mkdir "comments/$article_name", 0777 }, 'mkdir' );

# some good submissions
$t->post_form_ok(
    '/comment/add',
    {   author  => 'foo',
        email   => 'bar',
        article => $article_name,
        comment => 'cowabunga'
    }
);
$t->content_like(qr/Thanks for your comment/);

# now we should have something like comments/20100812-test/1282915480-ZHA8JB-unmoderated.md
my @files = glob "comments/$article_name/*-unmoderated.md";
ok(scalar @files == 1, 'one comment added');

my $file = $files[0];
ok (-s $file, 'some data in it');

ok( do { unlink $file }, 'unlink comment file' );

ok( do { rmdir "comments/$article_name"} , 'unlink article dir' );
ok( do { rmdir 'comments'              },  'removed empty comments dir' );

__DATA__
@@ article.html.ep
<body>
% # is there a better way to wedge this in here?
% $self->stash('article' => { year => 2010, month => 8, day   => 12, name => 'test' });

% return "%INSERT_COMMENTS_HERE%\n";
</body>
