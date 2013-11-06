#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use utf8;

use FindBin;
use File::Find;
use File::Spec::Functions qw/ abs2rel catdir splitdir catfile /;
use Encode qw/ encode decode /;
use Digest::MD5 qw/ md5_hex /;
use POSIX qw/ strftime /;
use Time::Piece;

use lib catdir($FindBin::RealBin, 'lib');
use Mdkkoji::Document;
use Mdkkoji::Conf;

# chdir $FindBin::RealBin;

my %conf = Mdkkoji::Conf::load;
my $dbh = Mdkkoji::Conf::DBI(\%conf);
my $sth;

my $last_update = ($dbh->selectrow_array(q{SELECT value FROM etc WHERE field = 'last_update'}))[0] || 0;


{
	#
	# attempts to parse date string with formats specified in $conf{time_fmt}
	# returns epoch if success, undef if fails
	#
	sub try_strptime {
		my $str = shift or return;
		my ($t);
		for my $fmt (@{$conf{time_fmt}}) {
			$t = eval { Time::Piece->strptime($str, $fmt) };
			if ($t) {
				$t = $t->epoch;
				last;
			}
		}
		return $t;
	}

	sub update {

		my ($ref, $path, $hash) = @_;

		my $doc = Mdkkoji::Document->new($path, array_fields => $conf{idx_fields});
		my $date;
		my $sth;

		unless (($date = try_strptime($doc->fields('date')))) {
			$date = time;
			unless ($doc->set_fields(date => strftime($conf{time_fmt}->[0], localtime))->write) {
				warn "cannot add date field to $path: $!"
			}
		}

		{ # delete all idxs
			$sth = $dbh->prepare('DELETE FROM idxs WHERE ref = ?');
			$sth->execute($ref);
		}

		{ # insert entry
			$sth = $dbh->prepare('REPLACE INTO entries (ref, path, title, date, hash) VALUES (?, ?, ?, ?, ?)');
			$sth->execute($ref, $path, $doc->title, $date, $hash);
		}

		{ # insert all idx values
			$sth = $dbh->prepare('INSERT INTO idxs (ref, field, value) VALUES (?, ?, ?)');
			for my $field (@{$conf{idx_fields}}) {
			for my $value ($doc->fields($field)) {
				$sth->execute($ref, $field, $value);
			}}
		}
		say $path;
	}

	sub md5_file {
		undef local $/;
		open my $fh, '<:raw', $_[0] or return;
		md5_hex(<$fh>);
	}


	{ # Create temporary table
		$dbh->do(<<'QUERY');
			CREATE TEMPORARY TABLE tmp_entries (
				ref   VARCHAR(200) NOT NULL,
				path  BLOB         NOT NULL,
				mtime INTEGER      NOT NULL, 
				hash  VARCHAR(32)  DEFAULT NULL, 
				PRIMARY KEY (ref)
			)
QUERY
	}

	{ # Insert actual entries into the temporary table
		$sth = $dbh->prepare('INSERT INTO tmp_entries (ref, path, mtime) VALUES (?, ?, ?)');
		my $dir_walker = sub {
			my ($root, $override) = @_;
			my $suffix = quotemeta($conf{suffix});
			return unless -d $root;
			find ({
				wanted => sub {

					$File::Find::prune = 1 if /^\.(.)/;
			 		return if -d;
			 		return unless /\.$suffix$/;

			 		my $path = $File::Find::name;
			 		my @segments = splitdir(abs2rel($path, $root));
			 		unshift @segments, $override if defined $override;

			 		my $ref  = join '/', map { decode($conf{code_page}, $_) } @segments; 
			 		eval {
			 			$sth->execute($ref, $path, (stat($_))[9]);
			 		} or do {
			 			warn "$path is ignored. It may be because of root override settings";
			 		}

				}
			}, $root);
		};
		$dir_walker->($conf{root_overrides}->{$_}, $_) for keys $conf{root_overrides};
		$dir_walker->($conf{doc_root});

	}

	{ # Delete non existent entry
		$dbh->do('DELETE FROM idxs    WHERE ref NOT IN (SELECT ref FROM tmp_entries)');
		$dbh->do('DELETE FROM entries WHERE ref NOT IN (SELECT ref FROM tmp_entries)');
	}

	{ # Rule out unmodified entries(by mtime)
		$sth = $dbh->prepare('DELETE FROM tmp_entries WHERE mtime < ?');
		$sth->execute($last_update);
	}

	{ # Get hashes of modified entries
		my $sth1 = $dbh->prepare('SELECT ref, path FROM tmp_entries');
		my $sth2 = $dbh->prepare('UPDATE tmp_entries SET hash = ? WHERE ref = ?');
		
		my ($ref, $path);
		$sth1->execute;
		$sth1->bind_columns(\$ref, \$path);
		$sth2->execute(md5_file($path), $ref) while ($sth1->fetch);

	}

	{ # Rule out unmodified entries(by hash)
		$sth = $dbh->prepare(<<'QUERY');
		DELETE FROM tmp_entries WHERE ref IN (
			SELECT tmp.ref
			FROM   tmp_entries AS tmp
				INNER JOIN entries ON entries.ref = tmp.ref
			WHERE
				tmp.hash = entries.hash
		)
QUERY
	}

	{ # Update modified entries;
		$sth = $dbh->prepare('SELECT ref, path, hash FROM tmp_entries');
		$sth->execute;
		$sth->bind_columns(\(my ($ref, $path, $hash)));
		update($ref, $path, $hash) while ($sth->fetch);
	}


	{ # Update last update time
		$sth = $dbh->prepare(q{REPLACE INTO etc (field, value) VALUES ('last_update', ?)});
		$sth->execute(time);
	}

}
