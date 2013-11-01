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
	code_page => $conf{code_page}, 
	doc_root  => $conf{doc_root},
	root_overrides => { %{$conf{root_overrides}}, theme => $conf{theme} }, 
	unmapped_responses => {
		
	}, 
	mapped_responses => {
		DIR => sub {
			my ($local_path, $request) = @_;
			my $query = Mdkkoji::Document->new(undef, array_fields => [ @{$conf{idx_fields}}, 'search' ]);
			$query->set_fields(
				r => $conf{recursive}, 
				pg => 0,
				%{parse_query($request->{QUERY})}
			);

			my $list = Mdkkoji::DocList->new(Mdkkoji::Conf::DBI(\%conf), $query->fields, idx_fields => $conf{idx_fields});
			$list->filter(sub {
				
				my ($path, $url, $title) = @_;
				
				open my $fh, '<:encoding(utf8)', $path;
				Mdkkoji::Document::parse_head($fh, $conf{title_marker});

				local $/ = undef;
				my $body = <$fh>;
				my @search = $query->fields('search');
				my $title_match = Mdkkoji::Search::search($title, @search);
				my $body_match  = Mdkkoji::Search::search($body, @search);

				my $score   = Mdkkoji::Search::score($body_match, $title_match);
				my $excerpt = Mdkkoji::Search::excerpt($body, $body_match);

				$excerpt = encode('utf8', $excerpt) if defined $excerpt;

				return $score, $excerpt;
				
			}) if $query->fields('search');
			my @dirs;
			header(200, 'Content-Type' => 'text/html');
			$conf{templates}->{list}->($request, $query, $list, \@dirs);
		}, 
		md => sub {
			my ($local_path, $request) = @_;
			header(200, 'Content-Type' => 'text/html');
			$conf{templates}->{view}->($request, $local_path);
		}, 
		pl => sub {}
	}, 
);

exec($^X, $0);
