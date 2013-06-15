package Search;

use strict;
use warnings;
use feature qw/ say /;
use Subroutines;
use NotesConfig;
use Exporter qw/ import /;
use Encode;
our @EXPORT = qw/ search /;

sub search {

	my ($content, $title, $quries) = @_;

	my (
		@match_pos,
		@match_count,
		$intitle_count,

		$sqr_sum,
		$sum,
		$match_score,

		$range,
		@in_range,
		%range_score,
		$max_range_score,
		$range_winner,
		$excerpt,
		$length,
		$excerpt_start,
		$excerpt_length
	);

	($content, $title) = map { Encode::decode('utf8',$_) } ($content, $title);

	$content =~ s/</&lt;/g;
	$content =~ s/>/&gt;/g;
	$range = 200;
	$max_range_score = 0;
	$range_winner = 0;
	$intitle_count = 0;

	$excerpt_length = $_CONF{'excerpt_length'};
	$excerpt = '';


	for my $query (@$quries) {
		
		$query = Encode::decode('utf8',$query);
		$intitle_count++ while $title =~ /(\Q$query\E)/g;

		while ( $content =~ /(\Q$query\E)/g ) {
			substr($content, $-[0], $+[0] - $-[0], "<b>$1</b>");
			push @match_pos, $+[0];
			pos($content) = $+[0] + 7;
		}
		push @match_count, scalar(@match_pos);
		for my $pos (@match_pos) {
			push @in_range, $pos;
			for ( grep { $_ > $pos - $range && $_ < $pos + $range } @in_range ) {
				$range_score{$_}++;
				if ($range_score{$_} > $max_range_score) {
					$max_range_score  = $range_score{$_};
					$range_winner = $_;
				}
			}
		}
	}

	$sqr_sum += $_ ** 2 for @match_count;
	$sum += $_ for @match_count;
	
	$match_score = $sqr_sum ?
		( $sum**2/$sqr_sum - 1 + $sum )	** ($intitle_count + 1) :
		0 + $intitle_count ** 2;

	if ($match_score) {
		$excerpt_start = max($range_winner - ($excerpt_length / 2), 0);
		$excerpt  = substr($content, $excerpt_start, $excerpt_length);
		$excerpt  = '...'.$excerpt if $excerpt_start != 0;
		$excerpt .= '...' if ($excerpt_start + 200) < length($content);

		my $rev = scalar reverse $excerpt;
		my $last_close = index($rev,'>b/<');
		   $last_close != -1 or $last_close = $excerpt_length;
		if (index($rev,'>b<') < $last_close) {
			$excerpt .= '</b>';
		}
		$excerpt = Encode::encode('utf8',$excerpt);

	}

	return $match_score, $excerpt;
}