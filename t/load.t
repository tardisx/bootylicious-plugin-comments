#!perl -T

use Test::More tests => 2;


BEGIN {
	use_ok( 'Bootylicious::Plugin::Comments' );
}

diag( "Testing Bootylicious::Plugin::Comments $Bootylicious::Plugin::Comments::VERSION, Perl $], $^X" );

my $gallery = Bootylicious::Plugin::Comments->new();
ok($gallery && ref($gallery) eq 'Bootylicious::Plugin::Comments', 'ok use new')
