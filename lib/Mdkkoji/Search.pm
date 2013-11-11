package Mdkkoji::Search;

use v5.14;
use strict;
use warnings;
use List::Util qw/ sum reduce /;
use Encode;

use Mdkkoji::Document;

use constant EXCERPT_LEN => 150;

sub doit {

	my ($body, $title, $queries) = @_;
	my @queries = split /\s+/, decode('utf8', $queries);
	my (%pos, %score);
	my $title_matches = 0;

	$body =~ s/\s+/ /g;
	$body =~ tr/A-Z/a-z/;
	$title =~ tr/A-Z/a-z/;

	# search
	foreach my $q (@queries) {
		my $q_len = length $q;
		{ # in title
			my $offset = 0;
			while ((my $pos = index($title, $q, $offset)) != -1) {
				$title_matches++;
				$score{$q}++;
				$offset = $pos + $q_len;
			}
		}
		{ # in body
			my $offset = 0;
			$pos{$q} = [];
			while ((my $pos = index($body, $q, $offset)) != -1) {
				$score{$q}++;
				push @{$pos{$q}}, $pos;
				$offset = $pos + $q_len;
			}
		}
		return (0, undef) unless $score{$q};
	}

	my $score;
	{ # calculate score
		my $sum = sum values %score;
		my $sqr_sum = reduce { our $a + $b * $b } (0, values %score);
		$score = $sqr_sum ? ( $sum * $sum / $sqr_sum - 1 + $sum ) ** ($title_matches + 1) : 0;
	}

	my $excerpt;
	{ # make excerpt
		my $center = pick(map {@$_} values %pos);
		my $begin;

		$begin = $center - EXCERPT_LEN / 2;
		$begin = 0 unless $begin >= 0;

		$excerpt = '...' unless $begin == 0;
		$excerpt .= substr($body, $begin, EXCERPT_LEN);
		$excerpt =~ s/&/&amp;/g;
		$excerpt =~ s/</&lt;/g;
		$excerpt =~ s/>/&gt;/g;
		$excerpt .= '...' if $begin + EXCERPT_LEN < length($body);

		for my $q (@queries) {
			my $quoted = quotemeta $q;
			$excerpt =~ s{($quoted)}{<b>$1</b>}gi;
		}
		$excerpt = encode('utf8', $excerpt);
	}
	
	return ($score, $excerpt);
}

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

1;