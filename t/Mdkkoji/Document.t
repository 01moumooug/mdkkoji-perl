use v5.14;
use strict;
use warnings;

use File::Spec::Functions;
use POSIX qw/ strftime /;
use Test::More;

BEGIN {
	use_ok('lib', 'lib');
	use_ok('Mdkkoji::Document', qw/ parse_values unique build_line /);
	use_ok('Mdkkoji::Conf');
}

is_deeply(
	[unique('1', '2', '3', '1')],
	['1', '2', '3'],
	'unique() filters duplicate values without losing element order'
);
is_deeply(
	[parse_values('foo , baz   ')],
	['foo', 'baz'],
	'parse_values() trims each values'
);
is_deeply(
	[parse_values('foo, ,baz')],
	['foo','baz'],
	'parse_values() filters empty values'
);
is_deeply(
	build_line('foo', 'bar', 'baz,qux'),
	'foo, bar, baz\\,qux',
	'build_line() builds comma separated values'
);

my $parse_rules = [[ qr/\G\#[ \t]*(.+?)[ \t]*\#*\n+/, 'title' ]];
my %conf = (Mdkkoji::Conf::load);
my $doc;
$doc = Mdkkoji::Document->new(catfile(qw/ t Mdkkoji sample-docs generic-document.md /), 
	array_fields => [qw| tags category |], 
	parse_rules => $parse_rules
);
is_deeply(
	[$doc->fields('tags')],
	['tag1', 'tag2', 'tag3'], 
	'array field in document is parsed as array'
);
is_deeply(
	[$doc->push(tags => 'tag4', 'tag5')->fields('tags')],
	['tag1', 'tag2', 'tag3', 'tag4', 'tag5'],
	'push() works'
);
is_deeply(
	[$doc->push(category => 'A' ,'B')->fields('category')],
	['A', 'B'], 
	'push() can add new field with correct type'
);
is_deeply(
	[$doc->push(tags => 'tag4')->fields('tags')], 
	['tag1', 'tag2', 'tag3', 'tag4', 'tag5'], 
	'push() keeps uniqueness of values'
);
is_deeply(
	[$doc->pull(tags => 'tag2','tag3')->fields('tags')],
	['tag1', 'tag4', 'tag5'],
	'pull() works'
);
is_deeply(
	[$doc->set_fields(tags => 'foo, bar, baz')->fields('tags')], 
	['foo', 'bar', 'baz'],
	'set_fields() works'
);
is_deeply(
	$doc->fields_ord_ref,
	['title', 'field', 'tags', 'category'],
	'field order is correctly recorded'
);

my $out = catfile(qw/ t Mdkkoji sample-docs write.md /);

unlink $out;
$doc->write($out);

open FH, '<', $out or die 'cannot open written input: '.$!;
read(FH, my $char, 1);

is($char, '#', 'title marker is retained in output file');
$doc = Mdkkoji::Document->new($out,
	array_fields => [qw| tags category |], 
	parse_rules => $parse_rules
);
is_deeply(
	$doc->fields,
	{
		'title' => 'This is title', 
		'field' => 'this is field',
		'tags' => ['foo', 'bar', 'baz'],
		'category' => ['A', 'B']
	},
	'write() all fields are correctly built'
);
$doc->set_fields('tags' => undef, 'category' => undef);
is_deeply(
	$doc->fields,
	{
		'title' => 'This is title', 
		'field' => 'this is field',
	},
	'set_fields() can unset fields'
);

$doc->set_fields('tags' => 'tag1, tag2');
my $clone = $doc->clone;
is_deeply($clone, $doc, 'clone() results identical copy');
isnt(
	$clone->fields('tags'),
	$doc->fields('tags'), 
	'clone() but their referent is not same'
);

$doc = Mdkkoji::Document->new(catfile(qw/ t Mdkkoji sample-docs no-head.md/));
is(
	$doc->body,
	<<RESULT,
Document without head. 

body text
RESULT
	'fieldless head is regarded as part of body'
);

$doc = Mdkkoji::Document->new(catfile(qw/ t Mdkkoji sample-docs without-title.md/));
is($doc->title($conf{code_page}), 'without-title',
	'title() if no title field, properly decoded basename of file is regarded as title'
);

$doc = Mdkkoji::Document->new(catfile(qw/ t Mdkkoji sample-docs document-with-bom.md/), 
	parse_rules => $parse_rules
);
is(
	$doc->fields('field'), 'this is field',
	'it seems that BOM does not interfere with head parsing'
);

done_testing();
