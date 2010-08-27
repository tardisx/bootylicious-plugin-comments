#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;

use Mojolicious::Lite;
use Test::Mojo;

push @{app->plugins->namespaces}, 'Bootylicious::Plugin';
plugin comments => {email => 'nobody@example.com'};

app->log->level('error');

my $path = '/articles/2010/08/test.html';

get $path => 'article';

my $t = Test::Mojo->new;
$t->get_ok($path)->status_is(200)->content_like(qr{form.*POST.*/comment/add}ms);
$t->get_ok($path)->status_is(200)->content_like(qr{input.*hidden.*name.*article.*value="20100812-test}ms);

__DATA__
@@ article.html.ep
<body>
% # is there a better way to wedge this in here?
% $self->stash('article' => { year => 2010, month => 8, day   => 12, name => 'test' });

% return "%INSERT_COMMENTS_HERE%\n";
</body>
