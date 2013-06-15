#!/usr/bin/perl 

use FindBin;
use lib "$FindBin::RealBin/../";

use strict;
use warnings;
use feature qw/ say /;

use Cwd qw/ abs_path /;
use File::Find;
use File::Basename;
use File::Spec::Functions qw/ catdir catfile /;
use POSIX qw/ strftime /;
use Time::Local;
use Encode;

use NotesConfig;
use Document;
use Subroutines;
use Database qw/ $_DBH query /;

chdir ("$FindBin::RealBin/../");

sub update_doc ($$$%) {

	my ($path, $title, $date) = map { Encode::decode_utf8($_) } @_[0..2];
	my $fields = $_[3];
	   ($path, $title) = map { esc_squo($_) } ($path, $title);

	for my $field (@{$_CONF{'idx_field_names'}}) {
		$fields->{$field} = $_CONF{'idx_field_defaults'}->{$field} unless $fields->{$field};
		my $doc_table = Database::fabricate_table($fields->{$field},'value');
		query("
			INSERT OR IGNORE INTO mynotes_$field (path,value)
			SELECT '$path' path, doc.value
			FROM   $doc_table doc
			WHERE  doc.value != ''
		");
		query("
			DELETE FROM mynotes_$field
				WHERE
					path = '$path'
					AND value NOT IN $doc_table
		");
	}

	if (-f $path) {

		query("INSERT OR IGNORE INTO mynotes_docs (path) VALUES ('$path')");
		query("
			UPDATE mynotes_docs
			SET   
				title = '$title',
				date  = '". str2epoch($date)."'
			WHERE
				path = '$path'
		");

	} else {
		query("
			DELETE 
				FROM  mynotes_docs
				WHERE path='$path'
		");
	}
}

sub update_link {

	my ($from_doc, $to_doc) = @_;
	$to_doc = Database::fabricate_table(
		-e abs_path($from_doc) ?
			[
				map  {abs_path(
					catfile(dirname(/^\// ? $_CONF{'root'} : $from_doc),$_)
				)}
				grep { !/^[\w]+:\/\// && /\Q$_CONF{suffix}\E$/ }
				@$to_doc
			] :
			[]
		,'path'
	);
	$from_doc = esc_squo(abs_path($from_doc) || '');

	query("
		INSERT OR REPLACE INTO mynotes_links (from_doc, to_doc, is_live)
		SELECT '$from_doc' from_doc, to_doc.path to_doc, '0' is_live
		FROM   $to_doc to_doc
		WHERE  to_doc.path != ''
	");
	query("
		DELETE FROM mynotes_links
		WHERE
			from_doc = '$from_doc'
			AND to_doc NOT IN $to_doc
	");

	my @live_links;
	query("
		SELECT to_doc
		FROM   mynotes_links
		WHERE  from_doc = '$from_doc'
	",sub {
		my $entry  = $_[0]->fetchrow_hashref or return;
		my $target = $entry->{'to_doc'};
		push @live_links, $target if -e $target;
	});
	query("
		UPDATE mynotes_links
		SET    is_live = '1'
		WHERE  
			from_doc = '$from_doc'
			AND to_doc IN ".Database::fabricate_table(\@live_links,'to_doc')
	);

	my $is_live = -e $from_doc ? 1 : 0;
	my $is_dead = $is_live ? 0 : 1;
	query("
		UPDATE mynotes_links
		SET    is_live = '$is_live'
		WHERE
			to_doc = '$from_doc'
			AND is_live = '$is_dead'
	");
}

sub update_db_entry {
	# $_[0] Document object
	if (-f $_[0]->path) {
		my $mtime = strftime('%Y-%m-%d %H:%M:%S', localtime((stat($_[0]->path))[9]) );
		$_[0]->field('date')
			or $_[0]->field('date', $mtime )->write();
	}
	update_doc(
		$_[0]->path,
		$_[0]->field('title'),
		$_[0]->field('date'),
		$_[0]->field
	);
	update_link( $_[0]->path, [ values %{$_[0]->urls} ] );
}


my %entries;
query('SELECT * FROM mynotes_docs', sub{
	my $entry = $_[0]->fetchrow_hashref or return;
	$entries{Encode::encode_utf8($entry->{'path'})} = 1;
});

my $last_update = query("
	SELECT value
	FROM   mynotes_etc
	WHERE  key = 'last_update'
")->[0]->{'value'} || 0;

find ({
 	'wanted' => sub {
 		return unless /\Q$_CONF{suffix}\E$/;
 		$_ = catdir($_, '');
		if (defined $entries{$_} && (stat($_))[9] > $last_update) {
			update_db_entry(Document->new($_));
			say STDOUT 'found modified document: '.$_;
		}
		unless (defined $entries{$_}) {
			update_db_entry(Document->new($_));
			say STDOUT 'found new document: '.$_;
		}
		delete $entries{$_};
 	},
 	'no_chdir' => 1
}, $_CONF{'root'});

for (keys %entries) {
	update_db_entry(Document->new($_));
	say STDOUT 'found removed document: '.$_;
}

$_DBH->do("
	INSERT OR REPLACE INTO mynotes_etc (key, value)
	VALUES ('last_update', '".timelocal(localtime)."')
");

1;