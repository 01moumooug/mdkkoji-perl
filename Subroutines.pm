package Subroutines;

use strict;
use warnings;
use feature qw/ say /;
use Time::Piece;

use Exporter 'import';
our @EXPORT = qw/
	str2epoch
	max
	csv2arr
	esc_squo
	url_encode
	url_decode
	parse_query
	build_query
	file2scalar
/;

sub str2epoch {

	my ($date,$is_last) = @_;
	my ($year, $month, $day, $hour, $min, $sec) = $date =~ /[\d]+/g;

	$month or $month = $is_last ? 12 : 1;
	$month += $is_last ? 1 : 0;
	$day   or $day   = $is_last ? 0 : 1;
	$hour  or $hour  = $is_last ? 23 : 0;
	($min, $sec) = map { $_ or $is_last ? 59 : 0 } ($min, $sec);

	my $time = Time::Piece->strptime(( $year || 1970 ),'%Y')->add_months($month - 1);
	   $time += 86400 * ($day - 1) + 3600 * ( $hour || 0 ) + 60 * ( $min || 0 ) + ( $sec || 0 );
	   $time->epoch;
}

sub max ($$) { $_[$_[0] < $_[1]] }
# sub min ($$) { $_[$_[0] > $_[1]] }

sub csv2arr  { grep { s/^\s+|\s+$//g; $_ ne ''; } split /(?<!\\),/, $_[0]; }
sub esc_squo { my $s = $_[0]; $s =~ s/'/''/g; $s }


use Encode;
sub url_encode { my $s = Encode::encode_utf8($_[0]); $s =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg; $s }
sub url_decode { my $s = $_[0]; $s =~ tr/+/ /; $s =~ s/\%(..)/chr(hex($1))/seg; Encode::decode_utf8($s) }

sub parse_query {
	my %data;
	return {} unless $_[0];
	for (split '&', $_[0]) {
		my ($key, $val) = map { url_decode($_) } split '=', $_, 2;
		$data{$key} = $val;
	}
	return \%data;
}
sub build_query { join '&', map { "$_=".url_encode($_[0]->{$_}) } keys %{$_[0]}; }
sub file2scalar {
	open my $f, '<:utf8', $_[0] or return '';
	local $/ = undef;
	return <$f>;
}

1;