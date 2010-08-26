use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  DISTNAME  => 'Bootylicious-Plugin-Comments',
  NAME      => 'Bootylicious::Plugin::Comments',
  AUTHOR    => "Justin\ Hawkins\ \<justin\@hawkins\.id\.au>",
  ABSTRACT  => "Comments\ plugin\ for\ Bootylicious",
  VERSION   => '0.01',
  EXE_FILES => [ qw() ],
  (eval { ExtUtils::MakeMaker->VERSION(6.31) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM    => {
    "Mojo" => '0.999910',
    "Mail::Send" => 0,
  },
  test => {TESTS => 't/*.t'}
);

