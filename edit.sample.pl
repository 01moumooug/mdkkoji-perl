#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib	"$FindBin::RealBin/.";
chdir $FindBin::RealBin;

use Subroutines;
use NotesConfig;
use File::Spec::Functions qw/ catfile /;

{
	my $file = $ARGV[0];
	exit unless $file =~ m|^edit://|;

	$file =~ s|edit://||;
	$file = url_decode($file);

	system('/usr/bin/leafpad', catfile($_CONF{'root'},$file));
	exec('perl scripts/update.pl');
}
