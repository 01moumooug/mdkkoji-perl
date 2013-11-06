package Mdkkoji::Template;

use v5.14;
use strict;
use warnings;
use File::Spec;

sub _add_slashes {
	my $s = $_[0];
	$s =~ s/\\/\\\\/g;
	$s =~ s/"/\\"/g;
	$s;
}

sub compile {
	my ($dir, $src) = @_;
	$src = File::Spec->catfile($dir, $src);
	undef local $/;
	open my $fh, '<', $src or die "failed to open template source: $src, $!";

	$src = <$fh>;
	$src = '%]'.$src;
	$src .= '[%' unless $src =~ m/\[%(\s+)?\Z/m;
	$src =~ s/(?<=%\])((\s|\S)+?)(?=\[%)/_add_slashes($1)/mega;

	$src =~ s/\[%/";/g;
	$src =~ s/%\]/print "/g;

	return 'sub { '.$src.' }';

}

1;