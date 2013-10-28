package Mdkkoji::Search;

use v5.14;
use strict;
use warnings;
use constant EXCERPT_LEN => 150;

sub pick {
	
	my $len  = scalar @_;
	my ($winner, $max) = (0, 0);

	@_ = sort { $a <=> $b } @_; 

	for (my $i = 0; $i < $len; $i++) {
		my ($count, $l, $r) = (0, $i - 1, $i + 1);
		$l--, $count++ while ($l >= 0   && $_[$i] - $_[$l] < EXCERPT_LEN);
		$r++, $count++ while ($r < $len && $_[$r] - $_[$i] < EXCERPT_LEN);
		$max = $count, $winner = $i if $count > $max;
	}
	return $_[$winner];

}

sub unfat {
	${$_[0]} =~ s/\s+/ /g;
}

sub search {
	my $content = shift || '';
	unfat(\$content);
	my @queries = grep {$_} @_;
	my %lengths = (map { $_ => length } @queries);
	my %results = (map { $_ => [] } @queries);
	for my $q (@queries) {
		my $offset = 0;
		while ((my $pos = index($content, $q, $offset)) != -1) {
			push @{$results{$q}}, $pos;
			$offset = $pos + $lengths{$q};
		}
		unless (scalar @{$results{$q}}) {
			%results = (map { $_ => [] } @queries);
			last;
		}
	}
	return \%results;
}

sub score {
	my ($match, $title) = @_;
	my ($sum, $sqr_sum, $in_title_count) = (0, 0, 0);

	for (values $match) {
		next unless ref $_ eq 'ARRAY';
		my $s = scalar @$_;
		$sum     += $s;
		$sqr_sum += $s * $s;
	}

	for (values $title) {
		next unless ref $_ eq 'ARRAY';
		$in_title_count += scalar @$_;
	}

	return $sqr_sum ?
		( $sum * $sum / $sqr_sum - 1 + $sum ) ** ($in_title_count + 1) :
		0 + $in_title_count * $in_title_count;

}

sub excerpt {
	my ($content, $search_result) = @_;

	my $pos = pick(map {@$_} values $search_result);

	return unless defined $pos;

	my ($begin, $excerpt);
	my $length = length($content);
	$begin = $pos - EXCERPT_LEN / 2;
	$begin = 0 unless $begin >= 0;

	$excerpt = '...' unless $begin == 0;
	$excerpt .= substr($content, $begin, EXCERPT_LEN);
	$excerpt =~ s/&/&amp;/g;
	$excerpt =~ s/</&lt;/g;
	$excerpt =~ s/>/&gt;/g;

	$excerpt .= '...' if $begin + EXCERPT_LEN < $length;

	for my $query (keys $search_result) {
		my $quoted = quotemeta $query;
		$excerpt =~ s{$quoted}{<b>$query</b>}g;
	}
	return $excerpt;
}
1;