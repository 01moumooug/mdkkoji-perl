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
	
	# 편집용 프로그램
	'editor'   => 'subl',
	
	# 편집용 프로토콜. 이 프로토콜과 편집용 프로그램을 연동시킵니다.
	'edit_proto' => 'edit',
	
	# 색인할 헤더의 필드 이름과 기본값
	'idx_fields' => [
		['tags'  ,'(none)'],
		['type'  ,'(none)'],
		['author',''],
		['status',''],
	],
	
	# 내용을 검색할 경우 발췌문의 길이
	'excerpt_length' => 150, 
	
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