use v5.14;
use strict;
use warnings;

use Test::More;

use lib 'lib';
use Mdkkoji::Conf;
use Mdkkoji::Template;

my %conf = Mdkkoji::Conf::load;

for (keys $conf{templates}) {
	my $code = eval Mdkkoji::Template::compile($conf{theme}, $conf{templates}->{$_}) or say $@;
	ok($code, "$_ compiles");
}

done_testing();
