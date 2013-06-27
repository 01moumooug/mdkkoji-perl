package Content;

use strict;
use warnings;
use feature qw/ say /;

use File::Spec::Functions qw/ catdir catfile abs2rel /;

use NotesConfig;
use Database;
use Document;
use Search;
use Subroutines;

sub view {

	my ($file, $request) = @_;
	my $data = {};

	$data->{'doc'}      = Document->new($file);
	$data->{'edit_url'} = $_CONF{'edit_url'};
	$data->{'edit_url'} =~ s/%u/$request->{'URL'}/;
	$data->{'query'}    = build_query({
		map { ( $_, join ',', @{$data->{'doc'}->field($_)} ) }
		@{$_CONF{'idx_field_names'}}
	});
	$data->{'back_links'} = Database::back_link($file);
	$data->{'request'} = $request;

	return $data;
}

sub list {

	my ($path, $request) = @_;
	my $data = {};
	my $root = $_CONF{'root'};

	# 조건에 맞는 문서 목록
	$data->{'docs'} = [ @{Database::query_docs($request->{'CONTENT'})} ];

	# 검색을 할 경우
	$data->{'search_term'} = $request->{'CONTENT'}->{'search'} || '';
	if ($data->{'search_term'}) {
		$data->{'docs'} = [
			sort { $b->{'score'} <=> $a->{'score'} }
			grep {

				my $doc = Document->new(catfile($root, $_->{'path'}));
				(
					$_->{'score'},
					$_->{'excerpt'}
				) = search(
					$doc->body,
					$doc->title,
					[ csv2arr($data->{'search_term'}) ]
				);
			 	$_->{'score'};
			 	
			} @{$data->{'docs'}}
		];
	}

	# 디렉토리 목록

	unless ($request->{'URL'} eq '/list') {
		opendir(my $DIR, $path);
		$data->{'dirs'} = [
			grep { !($_ eq '.' || $_ eq '..' || /^\./) }
			grep { -d catdir($path,$_); }
			readdir($DIR)
		];
		$data->{'dirs'} = [map{
			Encode::from_to($_, $_CONF{'code_page'}, 'utf8');
			$_;
		} @{$data->{'dirs'}}] if $_CONF{'code_page'};
	}

	# 색인된 값 개수 세기
	$data->{'record_counts'}->{$_} =
		Database::count_records([
			map { $_->{'path'} }
			@{$data->{'docs'}}
		],$_) for @{$_CONF{'idx_field_names'}};


	$data->{'docs'} = [
		map {
			$_->{'path'} = Encode::decode($_CONF{'code_page'}, $_->{'path'});
			$_->{'path'} = Encode::encode('utf8', $_->{'path'});
			$_;
		} @{$data->{'docs'}}
	] if $_CONF{'code_page'};

	# 디렉토리 링크를 위해 제일 앞의 '/' 제거
	$request->{'URL'} =~ s/\///;

	# 요청 헤더
	$data->{'request'} = $request;

	return $data;
}

1;