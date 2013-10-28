package Mdkkoji::Conf;

use v5.14;
use strict;
use warnings;
use DBI;
use Encode qw/ encode decode /;

sub load {
	my %conf = (do 'config.pl');
	my @idx_fields = @{$conf{idx_fields}};
	my ($field, $default, @names, %defaults);
	while (($field, $default, @idx_fields) = @idx_fields) {
		push @names, $field;
		$defaults{$field} = $default;
	}
	$conf{doc_root} = encode($conf{code_page}, $conf{doc_root});
	$conf{idx_fields} = \@names;
	$conf{idx_field_defaults} = \%defaults;
	return %conf;
}

sub DBI {
	my $conf = shift || { &load };
	my $dbh = DBI->connect(@{$conf->{dbi}->{args}}) or die $DBI::errstr;
	if (ref $conf->{dbi}->{init} eq 'ARRAY') {
		ref $_ eq 'CODE' ? &$_($dbh, $conf) : $dbh->do($_) for @{$conf->{dbi}->{init}};
	}
	return $dbh;
}
1;