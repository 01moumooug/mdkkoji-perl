package NotesConfig;

our %_CONF = (

	# 사용할 포트 번호
	'port'     => 8888, 
	
	# 노트 제목
	'title'    => 'W2 Notes', 
	
	# 문서 파일들의 루트 경로.
	'root'     => "/notes", 
	
	# 마크다운 파일 확장자
	'suffix'   => '.md', 
	
	# db 파일 이름
	'db_path'  => 'w2notes.db', 
		
	# 문서 편집 url. %u는 문서의 url로 치환됩니다. w2notes 자체에는 문서 편집 
	# 기능이 없습니다. 임의 프로토콜과 편집용 프로그램을 연동시키거나(아래의 설정
	# 값과 edit.sample.pl을 참고), 그냥 수동으로 파일을 편집하거나 알아서 하시길.
	'edit_url' => 'edit://%u',
	
	# 색인할 헤더의 필드 이름과 기본값
	'idx_fields' => [
		['tags'  ,'(none)'],
		['type'  ,'(none)'],
		['author',''],
		['status',''],
	],
	
	# 내용을 검색할 경우 발췌문의 길이
	'excerpt_length' => 150, 
	
	# 헤더에 넣을 시간의 형식
	'time_format' => '%Y-%m-%d %H:%M:%S',

	# 코드 페이지
	'code_page' => undef,

	# title 필드가 없을 경우, 파일 이름을 제목으로 변환하는 방법
	'basename2title' => sub {
		tr/\_/ /;
		s/\.[\d\w]+?$//g;
		return $_;
	}

);

use strict;
use warnings; 

use Exporter 'import';
our @EXPORT = qw/ %_CONF /;

use Subroutines;

$_CONF{'idx_field_names'} = [];
$_CONF{'idx_field_defaults'} = {};
for (@{$_CONF{'idx_fields'}}) {
	push @{$_CONF{'idx_field_names'}}, $_->[0];
	$_CONF{'idx_field_defaults'}->{$_->[0]} = [ csv2arr($_->[1] || '') ];
}

1;