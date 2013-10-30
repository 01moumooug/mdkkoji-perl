#!/usr/bin/env perl

use strict;
use warnings;
use v5.14;

use CGI::Util qw/ unescape /;
use Encode qw/ decode encode /;
use File::Find;
use File::Spec;
use FindBin;
use POSIX qw/ strftime /;
use Text::ParseWords;

use lib File::Spec->catdir($FindBin::RealBin, 'lib');
use Mdkkoji::Conf;
use Mdkkoji::Document;
use Mdkkoji::EntryList;
use Mdkkoji::Search;
use Mdkkoji::Server qw/ header /;
use Mdkkoji::Template;
use Mdkkoji::Util qw/ build_query build_query_pair /;

chdir $FindBin::RealBin;

my %conf = Mdkkoji::Conf::load;
$conf{templates}->{$_} = eval Mdkkoji::Template::compile($conf{templates}->{$_})
or die "load failed to load $_: $@"
	for keys $conf{templates};

Mdkkoji::Server::start(
	port      => $conf{port}, 
	doc_root  => $conf{doc_root},
	code_page => $conf{code_page}, 
	root_overrides => $conf{root_overrides},
	response  => sub {

		my ($local_path, $request, $sock) = @_;
		say STDOUT $local_path;
		##### requests to directory #####
		if (-d $local_path) {

			my $query = Mdkkoji::Document->new(undef, array_fields => $conf{idx_fields});

			### default conditions ###
			$query->set_fields(%{parse_query($request->{QUERY})});
			defined $query->fields('r') or $query->set_fields(r => $conf{recursive});
			defined $query->fields('pg') && $query->fields('pg') >= 0 or $query->set_fields(pg => 0);
			$query->set_fields(dir => unescape($request->{PATH}));

			### filter by indexes, directory, date ###
			my $list = Mdkkoji::EntryList->new(
				Mdkkoji::Conf::DBI(\%conf),
				$query->fields,
				idx_fields => $conf{idx_fields}
			);

			### filter by text search if search terms are provided ###
			my @search = grep {$_}
				map  { s/^\s+|\s+$//r }
				map  { decode('utf8', $_) }
				parse_line(',', 0, $query->fields('search'));

			if (scalar @search) {
				$list->filter(sub {
					
					my ($path, $url, $title) = @_;
					
					open my $fh, '<:encoding(utf8)', $path;
					Mdkkoji::Document::parse_head($fh, $conf{title_marker});

					local $/ = undef;
					my $body = <$fh>;

					my $title_match = Mdkkoji::Search::search($title, @search);
					my $body_match  = Mdkkoji::Search::search($body, @search);

					my $score   = Mdkkoji::Search::score($body_match, $title_match);
					my $excerpt = Mdkkoji::Search::excerpt($body, $body_match);

					$excerpt = encode('utf8', $excerpt) if defined $excerpt;

					return $score, $excerpt;

				});
			}

			### get directory list ###
			my @dirs;
			find(sub {
				if ($_ ne '.' && -d $_) {
					push @dirs, encode($conf{code_page}, decode('utf8', $_)) if substr($_, 0, 1) ne '.';
					$File::Find::prune = 1;
				}
			}, $local_path);
			@dirs = sort @dirs;
			$query->set_fields(dir => undef);

			### template result ###
			header(200, 'Content-Type' => 'text/html');
			$conf{templates}->{list}->($request, $query, $list, \@dirs);
			return 1;

		##### requests to markdown documents ####
		} elsif ($local_path =~ m/\Q$conf{suffix}\E$/) {
			if (-e $local_path) {
				header(200, 'Content-Type' => 'text/html');
				$conf{templates}->{view}->($request, $local_path);
				return 1;

			} else {
				header(404);
				return 1;

			}

		} 
	}
);

exec($^X, $0);
