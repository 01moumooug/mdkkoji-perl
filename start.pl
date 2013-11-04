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
use Mdkkoji::DocList;
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
	code_page => $conf{code_page}, 
	doc_root  => $conf{doc_root},
	root_overrides => { %{$conf{root_overrides}}, theme => $conf{theme} }, 
	unmapped_responses => {
		
	}, 
	mapped_responses => {
		DIR => sub {
			my ($local_path, $request) = @_;
			my $query = Mdkkoji::Document->new(undef,
				array_fields => $conf{idx_fields}
			)->set_fields(
				r => $conf{recursive}, 
				pg => 0,
				%{parse_query($request->{QUERY})}
			);
			my $list = Mdkkoji::DocList->new(
				Mdkkoji::Conf::DBI(\%conf),
				$query->fields,
			);
			if ($query->fields('search')) {
				$list->filter(sub {
					my ($path, $title) = @{$_[0]}{qw| path title |};
					open my $fh, '<:encoding(utf8)', $path;
					Mdkkoji::Document::parse_head($fh, $conf{title_marker});
					local $/ = undef;
					my $body = <$fh>;
					return Mdkkoji::Search::doit($body, $title, $query->fields('search'));
				});
			}
			
			my @dirs;
			header(200, 'Content-Type' => 'text/html');
			$conf{templates}->{list}->($request, $query, $list, \@dirs);
		}, 
		md => sub {
			my ($local_path, $request) = @_;
			header(200, 'Content-Type' => 'text/html');
			$conf{templates}->{view}->($request, $local_path);
		}, 
		pl => sub {

		}
	}, 
);

exec($^X, $0);
