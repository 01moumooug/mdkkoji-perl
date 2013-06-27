#!/usr/bin/perl 

use FindBin;
use lib "$FindBin::RealBin/../";

use strict;
use warnings;
use feature qw/ say /;

use Cwd qw/ abs_path /;
use File::Find;
use File::Basename;
use File::Spec::Functions qw/ catdir catfile abs2rel /;
use POSIX qw/ strftime /;
use Time::Local;

use NotesConfig;
use Document;
use Subroutines;
use Database qw/ $_DBH query /;

chdir ("$FindBin::RealBin/../");

sub update_doc ($$$%) {

	my ($path, $title, $date, $fields) = @_;
	   ($path, $title) = map { esc_squo($_) } ($path, $title);

	$path = abs2rel($path, $_CONF{'root'});

	for my $field (@{$_CONF{'idx_field_names'}}) {
		$fields->{$field} = $_CONF{'idx_field_defaults'}->{$field} unless $fields->{$field};
		my $doc_table = Database::fabricate_table($fields->{$field},'value');
		query("
			INSERT OR IGNORE INTO w2notes_$field (path,value)
			SELECT '$path' path, doc.value
			FROM   $doc_table doc
			WHERE  doc.value != ''
		");
		query("
			DELETE FROM w2notes_$field
				WHERE
					path = '$path'
					AND value NOT IN $doc_table
		");
	}

	if (-f catfile($_CONF{'root'}, $path)) {

		query("INSERT OR IGNORE INTO w2notes_docs (path) VALUES ('$path')");
		query("
			UPDATE w2notes_docs
			SET   
				title = '$title',
				date  = '". str2epoch($date)."'
			WHERE
				path = '$path'
		");

	} else {
		query("
			DELETE 
				FROM  w2notes_docs
				WHERE path='$path'
		");
	}
}

sub update_link {

	my ($abs_from, $to) = @_;

	$to = [ map {
		Encode::from_to($_, 'utf8', $_CONF{'code_page'});
		$_;
	} @$to ] if $_CONF{'code_page'};


	$to = Database::fabricate_table(
		-e $abs_from ?
			[
				map  {
					my $path =
						$_ =~ /^\// ?
							catfile($_CONF{'root'}, $_) :
							catfile(dirname($abs_from), $_);
					abs2rel($path, $_CONF{'root'});
				}
				grep { !/^[\w]+:\/\// && /\Q$_CONF{suffix}\E$/ }
				@$to
			] :
			[]
		,'path'
	);

	my $rel_from = abs2rel($abs_from, $_CONF{'root'});
	$rel_from = esc_squo($rel_from);
	query("
		INSERT OR REPLACE INTO w2notes_links (from_doc, to_doc, is_live)
		SELECT '$rel_from' from_doc, to_doc.path to_doc, '0' is_live
		FROM   $to to_doc
		WHERE  to_doc.path != ''
	");
	query("
		DELETE FROM w2notes_links
		WHERE
			from_doc = '$rel_from'
			AND to_doc NOT IN $to
	");

	my @live_links;
	query("
		SELECT to_doc
		FROM   w2notes_links
		WHERE  from_doc = '$rel_from'
	",sub {
		my $entry  = $_[0]->fetchrow_hashref or return;
		my $target = $entry->{'to_doc'};
		push @live_links, $target if -e catfile($_CONF{'root'}, $target);
	});

	query("
		UPDATE w2notes_links
		SET    is_live = '1'
		WHERE  
			from_doc = '$rel_from'
			AND to_doc IN ".Database::fabricate_table(\@live_links,'to_doc')
	);

	my $is_live = -e $abs_from ? 1 : 0;
	my $is_dead = $is_live ? 0 : 1;
	query("
		UPDATE w2notes_links
		SET    is_live = '$is_live'
		WHERE
			to_doc = '$rel_from'
			AND is_live = '$is_dead'
	");
}

sub update_db_entry {
	# $_[0] Document object
	if (-f $_[0]->path) {
		my $mtime = strftime($_CONF{'time_format'}, localtime((stat($_[0]->path))[9]) );
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
query('SELECT * FROM w2notes_docs', sub{
	my $entry = $_[0]->fetchrow_hashref or return;
	$entries{$entry->{'path'}} = 1;
});

my $last_update = query("
	SELECT value
	FROM   w2notes_etc
	WHERE  key = 'last_update'
")->[0]->{'value'} || 0;

find ({
 	'wanted' => sub {
 		return unless /\Q$_CONF{suffix}\E$/;
 		my $path = abs2rel($_, $_CONF{'root'});
		if (
			defined $entries{$path}
			&& (stat($File::Find::name))[9] > $last_update
		) {
			update_db_entry(Document->new($File::Find::name));
			say STDOUT 'found modified document: '.$path;
		}
		unless (defined $entries{$path}) {
			update_db_entry(Document->new($File::Find::name));
			say STDOUT 'found new document: '.$path;
		}
		delete $entries{$path};
 	},
 	'no_chdir' => 1
}, $_CONF{'root'});

for (keys %entries) {
	update_db_entry(Document->new($_));
	say STDOUT 'found removed document: '.$_;
}

$_DBH->do("
	INSERT OR REPLACE INTO w2notes_etc (key, value)
	VALUES ('last_update', '".timelocal(localtime)."')
");

1;