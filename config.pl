use utf8;

# 제목
title => 'Mdkkoji', 

# 서버가 사용할 포트
port => 8080, 

# 색인할 문서의 확장자
suffix => '.md', 

# 문서의 제목 필드 대신 사용할 수 있는 표시
title_marker => '# ', 

# 색인할 필드와 기본값
idx_fields => [
	tags => '(none)', 
	type => ''
],

# 문서 목록에서 하위 디렉토리에 있는 문서까지 보여줄지 여부
recursive => 1,

# 문서 목록에서 한 페이지당 출력할 문서 개수
entries_per_page => 10, 

# 파일 시스템에서 사용하는 인코딩
code_page => 'utf8',

# 색인할 문서가 들어있는 디렉토리
doc_root => 'manual',

# 시간 필드에서 사용할 시간 형식. 첫번째 형식이 자동 생성되는
# 시간 필드에 적용됩니다 
time_fmt => [
	'%Y-%m-%d %H:%M:%S', 
	'%Y-%m-%d',
	'%Y년 %m월 %d일',
],

# 템플릿 파일의 경로
templates => {
	list => 'templates/list.tpl',
	view => 'templates/view.tpl'
},

dbi => {
	# DBI 생성자에 넘길 인자 목록 
	args => ['dbi:SQLite:dbname=mdkkoji.db','','', { RaiseError => 1 }],

	# DBI 인스턴스를 생성한 직후에 실행할 쿼리. 문자열은 쿼리로서 실행하고, 
	# 서브루틴 참조는 생산한 DBI 인스턴스와, 설정 파일의 내용이 담긴 해시 참조를 
	# 인자로 넘겨서 실행한다.
	init => [
		'PRAGMA foreign_keys=ON', 
		'PRAGMA synchronous=OFF', 
		'PRAGMA journal_mode=MEMORY',
		'PRAGMA default_cache_size=10000',
		'PRAGMA locking_mode=EXCLUSIVE'
	],

	# MySQL을 쓸 경우 아래와 같이 설정을 쓸 수도 있습니다.
	# args => [ 'DBI:mysql:database=mdkkoji;host=localhost;', 'user', 'password', {
	# 	RaiseError => 1, 
	# }],
	# init => [
	# 	'SET NAMES utf8 COLLATE utf8_general_ci', 
	# 	'SET CHARACTER SET utf8', 
	# 	'SET storage_engine=MYISAM'
	# ]
}