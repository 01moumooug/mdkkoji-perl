#!/usr/bin/perl

use FindBin;
use lib "$FindBin::RealBin/../";

use strict;
use warnings;
use feature qw/ say /;

use NotesConfig;
use Database qw/ $_DBH query /;

chdir ("$FindBin::RealBin/../");

sub has_table {
	query("
		SELECT COUNT(*) found
		FROM   sqlite_master
		WHERE  tbl_name = '$_[0]'
	")->[0]->{'found'};
}

my %tables;
my $need_update = 0;
$tables{$_} = undef for grep { /^w2notes_/ } @{query('
	SELECT name
	FROM   sqlite_master
	WHERE  type="table"
',sub{ return $_[0]->fetchrow_array; })};

unless (has_table('w2notes_docs')) {
	$_DBH->do(q|
		CREATE TABLE w2notes_docs (
			path  TEXT PRIMARY KEY,	
			title TEXT,
			date  INTEGER
		)
	|);
	$need_update++;
}
unless (has_table('w2notes_links')) {
	$_DBH->do(q|
		CREATE TABLE w2notes_links (
			from_doc TEXT,
			to_doc   TEXT,
			is_live  INTEGER,
			FOREIGN KEY(from_doc) REFERENCES w2notes_docs(path),
			PRIMARY KEY(from_doc, to_doc)
		)
	|);
	$need_update++;
}
unless (has_table('w2notes_etc')) {
	$_DBH->do('
		CREATE TABLE w2notes_etc (
			key   TEXT PRIMARY KEY,	
			value TEXT
		)
	');
	$need_update++;
}

delete $tables{'w2notes_docs'};
delete $tables{'w2notes_links'};
delete $tables{'w2notes_etc'};

for my $field (@{$_CONF{'idx_field_names'}}) {
	unless(has_table("w2notes_$field")) {
		$_DBH->do("
			CREATE TABLE w2notes_$field (
				path   TEXT,
				value  TEXT,
				FOREIGN KEY(path) REFERENCES w2notes_docs(path),
				PRIMARY KEY(path, value)
			)
		");
		$need_update++;
	}
	delete $tables{"w2notes_$field"};
}

$_DBH->do("DROP TABLE $_") for keys %tables;

$_DBH->do("
	INSERT OR REPLACE INTO w2notes_etc (key, value)
	VALUES ('last_update', '0')
") if $need_update;
