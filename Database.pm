package Database;

use strict;
use warnings;
use feature qw/ say switch /;

use DBI;
use POSIX qw/ strftime /;
use File::Spec::Functions qw/ catdir catfile /;

use NotesConfig;
use Subroutines;

use Exporter 'import';
our @EXPORT = qw($_DBH query);

our $_DBH = DBI->connect(
 	'dbi:SQLite:dbname='.$_CONF{'db_path'},'','',
 	{ RaiseError => 1 }
) or die $DBI::errstr;

sub query {
	my ($q,$method, $debug) = @_;
	my @result;
	my $row;
	my $sth = $_DBH->prepare($q);
	$method = sub { return $_[0]->fetchrow_hashref; } unless defined $method;
	$sth->execute() or die $DBI::errstr;
	push @result, $row while $row = &$method($sth);
    $sth->finish();
    return \@result;
}

sub fabricate_table {
	# $_[0] value(array ref)
	# $_[1] label 
	return "( ".( join(' UNION ', map { "SELECT '".esc_squo($_)."' $_[1]" } @{$_[0]} ) || "SELECT '' $_[1]" )." )";
}

sub query_docs {
	my ($request) = @_;
	my @queries;
	my $idx_fields = $_CONF{'idx_field_names'};
	for (keys %$request) {
		my $value = $request->{$_};
		next unless $value;
		given($_) {
			when ('daterange')  { push @queries, _make_daterange_query($value) }
			when (@$idx_fields) { push @queries, _make_idx_field_query($_,$value) }
			when ('dir')        { push @queries, _make_dir_query($value) }
		}
	}
	my $query = join (' INTERSECT ', @queries ) || '
		SELECT *
		FROM   mynotes_docs
	';
	return query($query.' ORDER BY date DESC');
}

sub _make_daterange_query {

	my ($from,$to) = split '-', $_[0], 2;
	$from or $from = '1970/01/01';
	$from = str2epoch($from);
	$to   or $to   = strftime('%Y/%m/%d',localtime);
	$to   = str2epoch($to,1);

	return "
		SELECT path, title, date
		FROM   mynotes_docs
		WHERE  date BETWEEN '$from' AND '$to'
	";
}

sub _make_idx_field_query {
	my ($field,$value) = @_;
	my @value = split ',', $value;
	   $value = join  ',', (map { "'".esc_squo($_)."'" } @value);
	return "
		SELECT
			field.path AS path,
			docs.title AS title,
			docs.date AS date
		FROM   mynotes_$field field 
			INNER JOIN mynotes_docs docs
				ON field.path = docs.path
		WHERE  field.value IN ( $value )
		GROUP  BY field.path
		HAVING COUNT(*) > $#value
	";
}

sub _make_dir_query {
	opendir(my $dh, $_[0]);
	return "
		SELECT *
		FROM   mynotes_docs
		WHERE
			path LIKE '".esc_squo(catfile($_[0],''))."%'
	".join ' ',
	 	map  { q|AND path NOT LIKE '|.esc_squo(catfile($_[0],$_,'')).q|%' | }
	 	grep { !($_ eq '.' || $_ eq '..' || /^\./) }
	 	grep { -d catdir($_[0],$_) }
	 	readdir($dh);
}

sub count_records {
	# $_[0] paths(array ref)
	# $_[1] field
	return query("
		SELECT $_[1].value value, COUNT(*) count
		FROM   mynotes_$_[1] $_[1]
			INNER JOIN ( ".fabricate_table($_[0],'path')." ) paths
				ON $_[1].path = paths.path
		GROUP BY value
		ORDER BY count DESC
	");
}

sub back_link {
	return query("
		SELECT *
		FROM   mynotes_docs docs
		WHERE
			docs.path IN (
				SELECT from_doc
				FROM   mynotes_links
				WHERE  to_doc = '".esc_squo($_[0])."'
			)
	")
}
1;