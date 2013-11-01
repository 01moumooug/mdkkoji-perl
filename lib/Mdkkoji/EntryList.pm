package Mdkkoji::DocList;

use v5.14;
use warnings;
use strict;
use Text::ParseWords;
use POSIX qw/ ceil /;

sub new {
	my ($class, $dbh, $query, @opts) = @_;
	my %ord_types = (
		'mysql'  => 'INTEGER PRIMARY KEY AUTO_INCREMENT', 
		'SQLite' => 'INTEGER PRIMARY KEY AUTOINCREMENT'
	);
	my $self = bless {(
		dbh        => $dbh, 
		ord_type   => $ord_types{$dbh->{Driver}->{Name}} || die "Not Implemented For $dbh->{Driver}->{Name}. Sorry",
	), @opts}, $class;

	$self->{query} = {(
		dir    => '',
		r  => 0,
	), %$query};

	$self->_init;

	return $self;
}

sub _init {

	my ($self) = @_;
	my $query  = $self->{query};
	my $sth;

	$self->{dbh}->do(<<'QUERY');
	CREATE TEMPORARY TABLE tmp_matches (
		ref     VARCHAR(200) NOT NULL,
		score   INTEGER      DEFAULT NULL,
		excerpt VARCHAR(450) DEFAULT NULL, 
		PRIMARY KEY (ref)
	)
QUERY
	$self->{dbh}->do(<<'QUERY');
	CREATE TEMPORARY TABLE tmp_idxs (
		field VARCHAR(40) NOT NULL, 
		value VARCHAR(50) NOT NULL, 
		PRIMARY KEY (field, value)
	)
QUERY

	$sth = $self->{dbh}->prepare('INSERT INTO tmp_idxs (field, value) VALUES (?, ?)');
	my $count = 0;
	for my $field (grep { ref $query->{$_} eq 'ARRAY' } keys $query) {
		map {
			$sth->execute($field, $_);
			$count++;
		} keys { map {$_ => undef} @{$query->{$field}} }
	}

	my $entries = <<SUBQUERY;
	SELECT ref, date, title
	FROM   entries
	WHERE
		((? IS NULL OR ref NOT LIKE ?) AND ref LIKE ?) AND
		(? IS NULL OR date >= ? ) AND
		(? IS NULL OR date <= ? )
SUBQUERY

	if ($count) {
		$sth = $self->{dbh}->prepare(<<"INSERT");
		INSERT INTO tmp_matches (ref)
		SELECT entry.ref
		FROM   ( $entries ) AS entry
			INNER JOIN idxs ON idxs.ref  = entry.ref
			INNER JOIN tmp_idxs AS query ON 
				(idxs.field = query.field AND
				idxs.value = query.value)
		GROUP BY entry.ref
		HAVING COUNT(entry.ref) = ($count)
INSERT
	} else {
		$sth = $self->{dbh}->prepare(<<"INSERT");
		INSERT INTO tmp_matches (ref)
		SELECT entry.ref
		FROM   ( $entries ) AS entry
INSERT
	}

	$self->{query}->{dir} =~ s{^/+|/+$}{};
	$self->{query}->{dir} .= '/' if $self->{query}->{dir};

	$sth->execute(
		$query->{r} ? undef : 1, "$query->{dir}%/%", "$query->{dir}%",
		$query->{date_from}, $query->{date_from}, 
		$query->{date_to}, $query->{date_to}
	);

	$self->{dbh}->do('DROP TABLE tmp_idxs');

}

sub filter {
	my ($self, $sub) = @_;
	my $select_sth = $self->{dbh}->prepare(<<'QUERY');
		SELECT
			entries.path,
			tmp_matches.ref,
			entries.title, 
			tmp_matches.score, 
			tmp_matches.excerpt
		FROM
			tmp_matches
			INNER JOIN entries ON entries.ref = tmp_matches.ref;
QUERY
	my $update_sth = $self->{dbh}->prepare('UPDATE tmp_matches SET score = ?, excerpt = ? WHERE ref = ?');
	
	$select_sth->execute;
	$select_sth->bind_columns(\(my ($path, $ref, $title, $score, $excerpt)));
	$update_sth->execute(( ($score, $excerpt) = &$sub($path, $ref, $title, $score, $excerpt) ), $ref) while $select_sth->fetch;

	$self->{dbh}->do('DELETE FROM tmp_matches WHERE score = 0');
}

sub count_entries {
	my ($self, $field) = @_;
	my $sth = $self->{dbh}->prepare(<<'COUNT');
	SELECT idxs.value AS value, COUNT(entry.ref) AS count
	FROM   tmp_matches AS entry
		INNER JOIN idxs ON entry.ref = idxs.ref
	WHERE idxs.field = ?
	GROUP BY idxs.field, idxs.value
	ORDER BY COUNT(entry.ref) DESC, idxs.value ASC
COUNT
	$sth->execute($field);
	return $sth->fetchall_arrayref({});
}

sub _ord {
	my ($self) = @_;
	my $auto_increment = $self->{ord_type};
	$self->{dbh}->do('DROP TABLE IF EXISTS tmp_ordered');
	$self->{dbh}->do(<<"QUERY");
	CREATE TEMPORARY TABLE tmp_ordered (
		ord $auto_increment, 
		ref VARCHAR(200) NOT NULL
	)
QUERY
	$self->{dbh}->do(<<'QUERY');
	INSERT INTO tmp_ordered (ref)
	SELECT tmp_matches.ref
	FROM   tmp_matches
		INNER JOIN entries ON tmp_matches.ref = entries.ref
	ORDER BY tmp_matches.score DESC, entries.date DESC, entries.ref
QUERY
	$self->{_ordered} = 1;
	return $self;
}

sub by_page {
	my ($self, $p, $s) = @_;
	$p = 0 if !defined $p || $p < 0;
	return $self->by_range($p * $s + 1, ($p + 1) * $s);
}

sub by_range {

	my ($self, $to, $from) = @_;
	($to, $from) = ($from, $to) if $from > $to;
	$self->_ord unless $self->{_ordered};

	my $sth;
	$sth = $self->{dbh}->prepare(<<QUERY);
	SELECT
		tmp_ordered.ref,
		entries.path,
		entries.date,
		entries.title, 
		tmp_matches.excerpt
	FROM 
		tmp_ordered
			INNER JOIN entries ON tmp_ordered.ref = entries.ref
			INNER JOIN tmp_matches ON tmp_matches.ref = tmp_ordered.ref
	WHERE
		tmp_ordered.ord >= ? AND tmp_ordered.ord <= ?
	ORDER BY tmp_ordered.ord
QUERY
	$sth->execute($from, $to);
	
	my $list = $sth->fetchall_arrayref({});

	return $list;

}

sub total {
	($_[0]->{dbh}->selectrow_array(q{SELECT COUNT(ref) FROM tmp_matches}))[0];
}

sub paging_params {

	my ($self)    = shift;
	my $now       = shift || 0;
	my $page_size = shift || 10;

	my $last = int(($self->total - 1) / $page_size);
	my ($start, $end) = (
		$now + ceil((1 - $page_size) / 2),
		$now + ceil(($page_size - 1) / 2)
	);
	($start, $end) = (0, $end - $start) if $start < 0;
	($start, $end) = ($start - $end + $last, $last) if $end > $last;
	$start = 0 if $start < 0;

	return $start, $end, $last;
}


1;

__END__

=pod

=head1 NAME

Mdkkoji::DocList - 조건에 맞는 문서를 찾아냅니다.

=head1 SYNOPSIS

  use DBI;
  use Mdkkoji::DocList;

  $dbh = DBI->connect('dbi:SQLite:dbname=mdkkoji.db','','', { RaiseError => 1 });
  $conditions = {
      tags => [qw| tag1 tag2 tag3 |], 
      type => [qw| A B C |], 

      date_from => 1372192594,
      date_to => 1382192594,
      r => 1,
      dir => 'some/dir'
  };

  $list = DocList->new($dbh, $conditions, @options);
  $list->filter(sub{
      my ($path, $ref, $title, $score, $excerpt) = @_;
      # ...
      return $score, $excerpt;
  });

  $count = $list->count_entries('tags');
  $entries = $list->by_page(0, 10);
  $entries = $list->by_range(4, 23);

=head1 DESCRIPTION

지정한 조건을 모두 만족하는 문서의 목록을 나타내는 객체입니다. 
인스턴스를 생성할 때 문서를 검색합니다. 

기본적으로는 등록된 문서들의 색인 필드에 있던 값들로 
문서를 찾습니다.

색인 필드 외에도 날짜나 디렉토리로도 검색할 수 
있습니다. 그 밖의 검색 조건은 C<filter> 메서드를 사용합니다.

이 클래스는 데이터베이스를 이용해 문서를 찾기 때문에 DBI에 의존합니다. 

=head2 CONSTRUCTOR

=head3 new( $dbh, $conditions )

첫번째 데이터베이스에 접속한 DBI의 인스턴스입니다. 
두번째 인자는 조건을 나타내는 해시 참조입니다. 

=head4 CONDITIONS

필드 이름은 키에 쓰고, 필드의 값은 배열 참조로 씁니다.

  tags => [qw| tag1 tag2 tag3 |]

그러면 DocList는 해당 필드에 지정한 값이 모두 있는 문서를 찾습니다.

색인용 필드 외에도 다른 조건을 걸 수 있습니다. 이 때 조건 값은 배열 참조가 
아니라 스칼라로 지정합니다. 

=over 10

=item date_from, date_to

날짜 조건입니다. epoch로 적습니다. 날짜에 상관없이 문서를 찾으려면 C<undef>를 씁니다.
기본값은 C<undef>입니다. 

=item dir

해당 디렉토리의 문서만 찾는 조건입니다. 아래의 C<r> 조건에 따라 하위 디렉토리까지 포함시킬 수도 있습니다.

파일 시스템에 상관 없이 utf8을 사용하고, 디렉토리는 "C</>"으로 구분합니다.

제일 앞의 '/'는 언제나 무시됩니다. 끝의 '/'는 있어도 되고 없어도 됩니다. 다음 조건들은 
모두 동일한 효과를 냅니다.

  dir => '/dir',
  dir => 'dir', 
  dir => '/dir/'

기본값은 빈 문자열입니다.

=item r

하위 디렉토리의 문서까지 포함시킬지 정합니다. 참 값을 쓰면 하위 디렉토리도 
포함합니다. 기본값은 0.

=back

=head2 METHODS

=head3 filter( $sub ) 

문서 목록을 임의의 방법으로 걸러냅니다. 서브루틴 참조를 인자로 넘깁니다. 

  $list->filter(sub{
      my ($path, $ref, $title, $score, $excerpt) = @_;
      # ...
      return $score, $excerpt;
  });

이 메서드를 호출하면 인자로 넘긴 서브루틴으로 문서 목록의 모든 항목을 검토합니다. 
이 서브루틴은 파일 시스템 상의 문서 경로, 상대 URL 참조로 나타낸 문서의 경로, 
문서의 제목, 점수, 발췌문을 인자로 넘겨받고, 점수와 발췌문을 돌려줍니다. 

모든 문서를 검토한 뒤에는 점수가 0인 문서를 목록에서 제외합니다. 생성자에게 인자로
넘겨주는 검색 조건은 점수를 따로 매기지 않습니다. 따라서 이 메서드를 처음 호출할
때에는 C<$score>의 값이 C<undef>일 것입니다. 

점수의 값을 C<undef>로 돌려주면 목록에서 제외되지 않습니다.

=head3 count_entries( $field ) 

문서 목록 중에서 인자로 지정한 필드의 색인값을 가진 문서가 몇개인지 다음과 같은 
형태로 알려줍니다.

  [
      {
	     value => tag1,
	     count => 10
      },
      {
	     value => tag2,
	     count => 8
      }, 
      # ...
  ]

개수가 가장 많은 값부터 나열됩니다.

=head3 by_range( $to, $from )

문서 목록의 일부를 다음과 같은 형태로 가져옵니다.

  [
      {
	     ref => 'url/ref.md'
	     path => '/local/path/of/url/ref.md'
	     date => 1372192594
	     title => 'title of document'
	     excerpt => 'extracted by filter() method'
      }, 
      # ...
  ]

문서의 순서는 C<filter()> 메서드로 매긴 점수, 날짜, 경로
를 기준으로 합니다.

=head3 by_page( $page, $entries_per_page )

인자값으로 지정한 페이징에 맞게 C<by_range()> 메서드를 호출합니다.
C<$page>의 값은 0부터 시작합니다.

=head3 paging_params( $current_page, $entries_per_page )

사용자에게 보여줄 페이징 커서의 범위를 구합니다. 
C<시작 커서>, C<끝 커서>, C<마지막 커서>의 값을 목록으로
돌려줍니다.
