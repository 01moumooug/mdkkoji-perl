#!/usr/bin/env perl

use v5.14;
use warnings;
use strict;

use File::Find;
use File::Spec::Functions;
use Test::Harness;

my @tests;
find(sub { push @tests, $File::Find::name if /\.t$/ }, 't');
runtests(@tests);

do 'create-tables.pl';
unshift @ARGV, 'init';
do 'mime.pl';
do 'update.pl';
