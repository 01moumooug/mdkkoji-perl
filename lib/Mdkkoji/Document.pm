package Mdkkoji::Document;

use v5.14;
use strict;
use warnings;

use Text::ParseWords;
use File::Basename;
use Encode qw/ encode decode /;

use Exporter qw/ import /;
our @EXPORT_OK = qw/ parse_values unique build_line /;

sub new {

	my ($class, $path, $self);
    
    ($class, $path, @_) = @_;

    $self = bless {(
        array_fields => [], 
        fields       => {},
        parse_rules  => [], 
        bullet       => '-',
        _ord         => [],
    ), @_}, $class;

    $self->{array_fields} = { map { lc $_ => 1 } @{$self->{array_fields}} };

    $self->read($path) if $path;

    return $self;
}

sub read {
    my ($self, $path) = @_;
    open my $fh, '<:crlf', $path || $self->{path} or warn "cannot open $path: $!" and return;
    $self->{path} = $path;
    undef local $/;
    my ($field_list, $body, $extracts) = parse_head(<$fh>, $self->{parse_rules});
    my ($ord, $fields) = ([], {});
    my ($field, $value);
    while (($field, $value, @$field_list) = @$field_list) {
        $ord = [ grep { $_ ne $field } @$ord ] if (exists $fields->{$field});
        CORE::push @$ord, $field;
        $fields->{$field} = exists $self->{array_fields}->{$field} ? [ unique(parse_values($value)) ] : $value; 
    }
    @{$self}{qw| fields _ord _body _extracts |} = ($fields, $ord, $body, $extracts);
    return $self;
}

sub set_fields {
    my $self = shift;
    my ($field, $value);

    while (($field, $value, @_) = @_) {
        if (defined $value) {
            if ($self->{array_fields}->{$field}) {
                $value = [ parse_values($value) ] unless ref $value eq 'ARRAY';
                $value = [ unique(@$value) ];
            }
            CORE::push (@{$self->{_ord}}, $field) unless exists $self->{fields}->{$field};
            $self->{fields}->{$field} = $value;

        } else {
            delete $self->{fields}->{$field};
            $self->{_ord} = [grep { $_ ne $field } @{$self->{_ord}}];

        }
    }
    return $self
}

sub fields {
    my $self = shift;
    if (scalar @_) {
        return wantarray ? 
            grep { defined $_ } map {
                $self->{array_fields}->{$_} ?
                    ( exists $self->{fields}->{$_} ? @{$self->{fields}->{$_}} : undef ):
                    ( exists $self->{fields}->{$_} ?   $self->{fields}->{$_}  : undef );
            } @_ :
            $self->{fields}->{(shift)};
    } else {
        return $self->{fields}
    }
}

sub push {
    my ($self, $field, @values) = @_;
    @values = grep { defined $_ } @values;
    if (scalar @values && $self->{array_fields}->{$field}) {
        if (ref $self->{fields}->{$field} ne 'ARRAY') {
            $self->{fields}->{$field} = [];
            CORE::push @{$self->{_ord}}, $field;
        }
        $self->{fields}->{$field} = [ unique(@{$self->{fields}->{$field}}, @values) ];
    }
    return $self;
}

sub pull {
    my ($self, $field, @values) = @_;
    my %targets = map { $_ => 1 } grep { defined $_; } @values;
    if ($self->{array_fields}->{$field}) {
        if (ref $self->{fields}->{$field} eq 'ARRAY') {
            $self->{fields}->{$field} = [ grep { !$targets{$_} } @{$self->{fields}->{$field}} ];
            $self->set_fields($field => undef) unless scalar @{$self->{fields}->{$field}};
        }
    }
    return $self;
}

sub fields_ord_ref { return $_[0]->{_ord}; }

sub write {

    my $self = shift;
    my $path = shift || $self->{path};
    my $field_ord = @_ ? [@_] : $self->{_ord};
    
    my $h;
    open  $h, '>', $path or warn "cannot write to: $!" and return;
    print $h $self->_make_head($field_ord).$self->{_body};

    $self->{path} = $path;

    return 1;
}

sub _make_head {

	my $self = shift;
	my @fields = @{$self->{_ord}};
    my $head = '';

    for my $field (@fields) {
        
        my $val;
        $val = $self->{fields}->{$field} or next;
        $val = build_line(@$val) if ref($val) eq 'ARRAY';

        if (exists $self->{_extracts}->{$field}) {
            my $old_val = quotemeta $self->{_extracts}->{$field}->[0];
            $self->{_extracts}->{$field}->[1] =~ s/$old_val/$val/;
            $head .= $self->{_extracts}->{$field}->[1];

        } else {
            $head .= sprintf("%s %s: %s\n",
                substr($self->{bullet}, 0, 1),
                ucfirst($field),
                $val
            );
        }
    }
    $head .= "\n" unless $self->{_body} =~ /^\n/;

    return $head;
}

sub path  { $_[0]->{path} }

sub body  { $_[0]->{_body} }

sub parse_head {

    my $src = shift;
    my (@fields, $body, %extracts);

    # remove BOM!
    $src =~ s/^(?:\357\273\277|\377\376\0\0|\0\0\376\377|\376\377|\377\376)//g;

    my $failed = 0;
    my $rules = shift || [];
    until ($failed) {
        my $try_field_match = 1;
        for my $rule (@$rules) {
            if ($src =~ /$rule->[0]/gcp) {
                my $value = $1 || '';
                $extracts{$rule->[1]} = [ $value, ${^MATCH} ];
                CORE::push @fields, ($rule->[1] => $value);
                $try_field_match = 0;
                last;
            }
        }
        if ($try_field_match) {
            if ($src =~ /\G(?:[-+*][\t ]+)?(\w+)[\t ]*?:\s+(.+?)\n/gcp) {
                my $field = lc $1;
                CORE::push @fields, ($field => $2);
                delete $extracts{$field};
                $failed = 0;
            } else {
                $failed = 1;
            }
        }
    }
    $body = substr($src, pos($src) || 0);
    return (\@fields, $body, \%extracts);
}

# returns title of the document
# title is either defined by title field in header or filename
sub title {
    my $self = shift;
    my $code_page = shift || 'utf8';
    return $self->{fields}->{title} if (defined $self->{fields}->{title});
    
    if (defined $self->{path}) {
        my ($suffix, $title);
        ($suffix) = $self->{path} =~ /(\.[^.]+)$/;
        $title = basename(decode($code_page, $self->{path}), $suffix);
        $title =~ tr/_/ /;
        $title = encode('utf8', $title);
        return $title;
    
    } else {
        return undef;

    }
}

sub clone {
    my $self = shift;
    my $copy = bless {}, ref $self;
    my @shallow_things = qw/ path bullet _body /;

    @{$copy}{@shallow_things} = @{$self}{@shallow_things};
    $copy->{array_fields} = { map { $_ => 1 } keys %{$self->{array_fields}} };
    $copy->{_ord} = [ @{$self->{_ord}} ];
    $copy->{_extracts} = { map { $_ => [@{$self->{_extracts}->{$_}}] } keys %{$self->{_extracts}} }
        if defined $self->{_extracts};
    $copy->{parse_rules} = [ @{$self->{parse_rules}} ];

    while (my ($key, $val) = each %{$self->fields}) {
        $copy->{fields}->{$key} = ref $val eq 'ARRAY' ? [ @$val ] : $val;
    }
    return $copy;
}

# opposite of parse_line()
sub build_line {
	join ', ', map { s/,/\\,/gr } @_;
}

sub unique {
    my $seen = {};
    return grep { !$seen->{$_}++ } @_;
}

# parse_line() with trim
sub parse_values {
    grep { $_ ne '' } map { s/^\s+|\s+$//gra; } parse_line(',', 0, $_[0]);
}

1;

__END__

=pod 

=head1 NAME

Mdkkoji::Document

=head1 SYNOPSIS

  use Mdkkoji::Document;

  $doc1 = Mdkkoji::Document->new('some-file.txt');
  $doc2 = $doc1->clone;
  $doc3 = Mdkkoji::Document->new(undef);
  $doc3->read('some-file.txt');

  $doc4 = Mdkkoji::Document->new('some-file.txt', 
      array_fields => [qw| tags |]
  );

  $doc4->set_fields(
      title => 'This is title'
      tags => 'tag1, tag2, tag3',
  );
  $doc4->push('tags' => qw| tag2 tag3 tag4 |);
  $doc4->pull('tags' => qw| tag1 tag2 |);
  $doc4->fields('tags');
  $doc4->fields;

  $doc4->write;
  $doc4->write('another-file.txt');
  $doc4->write('yet-another-file.txt', qw| tags title date |);

=head1 DESCRIPTION

Mdkkoji 문서를 표상하는 클래스입니다. 문서의 헤더를 읽고 수정하는 것이 주된 
용도입니다. 

=head2 CONSTRUCTOR

=head3 new( $path, @options )

인스턴스를 생성합니다. C<$path>가 빈 값이 아니면, C<read> 메서드로 그 값이 가리키는 파일을 
읽어들입니다. 

=head4 옵션

=over 12

=item array_fields => []

배열 유형 필드를 지정합니다. 배열 유형 필드는 Text::ParseWords의 
C<parse_line>으로 "C<,>"를 구분자로 하여 값을 구분합니다. 중복된 값은 
제거되고, 각 값의 양쪽 공백도 잘려나갑니다.

=item bullet => "-"

내용을 파일에 쓸 때 헤더에서 사용할 불릿 기호입니다.

=item title_marker => "# "

제목 필드를 나타내는 문자열입니다. 헤더의 첫번째 줄이 이 문자열로 시작하면
title 필드로 간주됩니다.

=back

=head2 METHODS

=head3 read( $path )

파일을 읽습니다. 파일을 찾을 수 없는 경우 경고 메시지를 출력합니다.

=head3 clone 

인스턴스를 복제해서 돌려줍니다.

=head3 set_fields( @field_value_pairs )

필드의 값을 지정합니다. 필드가 없는 경우 필드를 새로 만듭니다. C<array_fields>
옵션으로 지정한 필드는 각각의 값을 C<,>로 구분합니다. 

=head3 fields( @fields )

필드의 값을 돌려줍니다. 스칼라 맥락에서는 첫번째 값을 돌려주고, 목록 맥락에서는 
해당 필드의 모든 값을 돌려줍니다. 이 때 C<undef>는 자동으로 제외됩니다. 예시: 

  $doc->set_field(title => 'TITLE', date => '2013-10-18')
      
  # 스칼락 맥락에서는 C<'TITLE'>을 반환
  # 목록 맥락에서는 C<('TITLE', '2013-10-18')>을 반환
  $doc->field(qw| title date |);

C<array_fields> 옵션으로 지정한 필드도 각 값을 목록으로 돌려줍니다. 

  $doc->set_field(tags => qw| tag1, tag2, tag3 |);
  $doc->set_field(type => qw| A, B, C |);
  
  $doc->fields(qw| tags type |); # ( tag1, tag2, tag3, A, B, C )

아무 필드도 지정하지 않는 경우 필드 전체를 해시 참조를 반환합니다.

  {
      title => 'TITLE', 
      date  => '2013-10-18', 
      tags  => [ 'tag1', 'tag2', 'tag3' ],  # 배열 필드
      type  => [ 'A', 'B', 'C' ] # 배열 필드
  }

=head3 push( $field, @values )

필드에 값을 추가합니다. 배열 필드에만 적용되며 중복되는 값은 제외됩니다.
한 문자열에서 각각의 값을 "C<,>"로 구분한 C<set_fields>와 달리,
각각의 값을 분리해서 넘깁니다.

  $doc->set_fields(tag => 'tag1, tag2, tag3');
  $doc->push(tag => qw/ tag1 tag2 tag3 /);

=head3 pull( $field, @values )

필드에서 해당 값을 뺍니다. C<push>와 마찬가지로 배열 필드에만 적용됩니다.

=head3 write ( $path, @fields )

필드와 본문을 빈 줄로 구분해서 파일에 씁니다.
경로를 따로 지정하지 않으면 C<read>로 읽은 
파일에 씁니다. 파일을 읽은 적도 없는 경우 아무 일도 하지 않습니다.

나머지 인자는 어떤 필드를 어떤 순서로 쓸지 정합니다.

이것을 생략할 경우 필드를 쓰는 순서는 기본적으로 기존에
읽어들인 문서를 따릅니다. 새로 추가된 필드는 입력된 순서대로 씁니다. 

첫번째 필드가 title인 경우에는 생성자 옵션에서 정한 C<title_marker>로 
제목줄을 씁니다.

=head3 title( $code_page )

현재 읽어들인 문서의 제목을 돌려줍니다. 제목은 title 필드에서 찾습니다. 
title 필드가 없으면 파일 경로에서 basename을 가져다가 확장자를 
떼고, "C<_>"를 공백으로 바꿔서 돌려줍니다. 읽어들인 파일이 없는 경우 
C<undef>를 돌려줍니다.

C<$code_page>의 기본값은 'C<utf8>'입니다. 파일 시스템이 다른 인코딩을 
사용할 경우 이 매개변수에 다른 값을 넘겨줘야, 파일 이름에서 문서 제목을 
제대로 가져올 수 있습니다.
