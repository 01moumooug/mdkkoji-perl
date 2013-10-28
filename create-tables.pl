use v5.14;
use warnings;
use strict;
use lib 'lib';

use Mdkkoji::Conf;

my $dbh = Mdkkoji::Conf::DBI;

$dbh->do('DROP TABLE IF EXISTS idxs');
$dbh->do('DROP TABLE IF EXISTS entries');
$dbh->do('DROP TABLE IF EXISTS etc');
$dbh->do(<<'QUERY');
	CREATE TABLE entries (
		ref    VARCHAR(200) NOT NULL,
		path   BLOB         NOT NULL,
		title  VARCHAR(200) NOT NULL,
		date   INTEGER      NOT NULL, 
		hash   VARCHAR(32)  NOT NULL,
		PRIMARY KEY (ref)
	)
QUERY

$dbh->do(<<'QUERY');
	CREATE TABLE idxs (
		ref  VARCHAR(200) NOT NULL, 
		field VARCHAR(40)  NOT NULL, 
		value VARCHAR(50)  NOT NULL,
		PRIMARY KEY (ref, field, value),
		FOREIGN KEY (ref) REFERENCES entries(ref)
	)
QUERY

$dbh->do(<<'QUERY');
	CREATE TABLE etc (
		field VARCHAR(40)  NOT NULL, 
		value VARCHAR(100) DEFAULT NULL, 
		PRIMARY KEY (field)
	)
QUERY
