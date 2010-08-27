#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

use Mojolicious::Lite;
use Test::Mojo;

push @{app->plugins->namespaces}, 'Bootylicious::Plugin';
plugin comments => {email => 'nobody@example.com'};

app->log->level('error');

my $path = '/articles/2010/08/test.html';

# XXX how do I inject this into the test request below?
my $article = { year => 2010,
                month => 8,
                day   => 12,
                name => 'test', 
              };

get $path => 'article';

my $t = Test::Mojo->new;
$t->get_ok($path)->status_is(200)->content_like(qr{form.*POST.*/comment/add}ms);

__DATA__
@@ article.html.ep
<body>
% return "%INSERT_COMMENTS_HERE%\n";
</body>
