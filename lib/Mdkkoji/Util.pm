use v5.14;
use strict;
use warnings;

use CGI::Util qw/ escape unescape /;

use Exporter qw/ import /;
our @EXPORT_OK = qw/ parse_query build_query build_query_pairs /;

sub parse_query {
	my $arg = shift;
	my $query = ref $arg ? $arg->query : $arg;

	my $delim = shift || '&';
	my $ref = {};

	for (split $delim, $query || return {}) {
		my ($key, $val) = split '=', $_;
		if ($key) {
			$key = unescape($key);
			my $recv = \$ref;
			while (
				$key && (
					$key =~ s/^\[(.*?)\](?!\])// ||
					$key =~ s/^(.*?)(?=(\[|$))//)
			) {
				if ($1) {
					$$recv = {} unless ref $$recv eq 'HASH';
					$recv = \$$recv->{$1};

				} else {
					$$recv = [] unless ref $$recv eq 'ARRAY';
					$recv = \$$recv->[$#$$recv + 1];
				}
			}
			$$recv = defined $val ? unescape($val) : undef;
		}
	}
	return $ref;
}

sub build_query {
	my $data = build_query_pairs(shift);
	my ($key, $val, @pairs);
	push @pairs, (escape($key).'='.escape($val)) while (($key, $val, @$data) = @$data);
	return join '&', @pairs;
};

sub build_query_pairs {
	my $node  = shift;
	my $query = shift || [];
	my $name  = shift;
	my $ref   = ref $node;
	if (defined $name) {
		if ($ref eq 'HASH') {
			build_query_pairs($node->{$_}, $query, $name.'['.$_.']') for keys $node;
		} elsif ($ref eq 'ARRAY') {
			build_query_pairs($_, $query, $name.'[]') for @$node;
		} elsif (!$ref) {
			push @$query, ($name, $node) if defined $node;
		}
	} else {
		if ($ref eq 'HASH') {
			build_query_pairs($node->{$_}, $query, $_) for keys $node;
		}
	}
	return $query;
}
