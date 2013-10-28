use v5.14;
use strict;
use warnings;

use Fcntl;
use AnyDBM_File;
use Pod::Usage;

tie my %mime, 'AnyDBM_File', 'mime-types/mime.dbm', O_RDWR | O_CREAT, 0666;

given (shift) {
	when ('set')    { %mime = (%mime, (shift || pod2usage(2)) => shift) }
	when ('get')    { say ($mime{(shift || pod2usage(2))} || 'not set'); }
	when ('dump')   { map { say "'$_' => '$mime{$_}', " } keys %mime; }
	when ('init')   { %mime = do 'mime-types/init.pl'; }
	default { pod2usage(-verbose => 99) }
}

%mime = (map { $_ => $mime{$_} } grep { $mime{$_} } keys %mime);

untie %mime;

__END__

=pod

=head1 NAME

mime.pl

=head1 SYNOPSIS

  perl mime.pl init
  perl mime.pl dump
  perl mime.pl set [suffix] [type]
  perl mime.pl get [suffix]

=head1 DESCRIPTION

This script manages simple MIME type database used by Mdkkoji::Server. 
Each suffix is associated with one type. e.g.

	css => 'text/css', 
	jpeg => 'image/jpeg'

=head2 COMMANDS

=over 10

=item init

Initialize database with F<init.pl>, which contains key/value pairs of
suffix and MIME type. 

=item dump

Dump contents of the database to STDOUT. Output of this command is 
formatted as key/value list in perl.

=item set

Set MIME type of given suffix. If seconds argument is omitted, 
MIME type of given suffix will be removed from the database

=item get

Get MIME type of given suffix.

=back
