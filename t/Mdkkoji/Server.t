use v5.14;
use strict;
use warnings;

use File::Spec::Functions;
use IO::Select;
use IO::Socket qw/ :crlf /;
use Digest::MD5 qw/ md5_hex /;
use Test::More;

BEGIN {
	use_ok('lib', 'lib');
	use_ok('Mdkkoji::Conf');
	use_ok('Mdkkoji::Server');
}

my %conf = (Mdkkoji::Conf::load);
my $opts = {
	doc_root => $conf{doc_root},
	code_page => $conf{code_page}
};
is(
	Mdkkoji::Server::to_local_path($opts,'dir/file'),
	catfile($conf{doc_root}, qw/ dir file /),
	'to_local_path() works'
);
is(
	Mdkkoji::Server::to_local_path($opts,'../.././file'),
	catfile($conf{doc_root}, qw/ file /), 
	'to_local_path() collapses path segments'
);

my $hello = md5_hex('hello'.rand.'hello');
my $pid = fork();

if ($pid == 0) {
	diag('starting test server...');
	Mdkkoji::Server::start(
		port      => $conf{port}, 
		doc_root  => catfile(qw/ t Mdkkoji sample-docs /), 
		code_page => $conf{code_page}, 
		unmapped_responses => {
			'/hello' => sub { print {$_[1]} $hello }, 
			'/exit'  => sub { &exit }
		}
	);
	exit;
}

sub get_connection {
	my ($socket, $attempt);
	while (1) {
		diag("attempt to connect test server");
		$socket = IO::Socket::INET->new(
			PeerAddr => 'localhost', 
			PeerPort => $conf{port}, 
			Proto => 'tcp'
		);
		last if (defined $socket);
		die 'failed to connect test server' if $attempt++ > 10;
		select(undef, undef, undef, 1);
	}
	return $socket;
}


my $conn;

{
	$conn = get_connection();
	print {$conn} "GET /hello HTTP/1.1".$CRLF.$CRLF;
	my $set;
	$set = IO::Select->new();
	$set->add($conn);
	my @ready = $set->can_read(1);
	die "test server not respond properly" unless scalar @ready;
	my $response = <$conn>;
	is($response, $hello, 'connected to test server');
}

{
	$conn = get_connection();
	print {$conn} "GET /%EB%B9%84%EB%9D%BC%ED%8B%B4/%EC%95%88%EB%85%95%ED%95%98%EC%84%B8%EC%9A%94 HTTP/1.1".$CRLF.$CRLF;
	local $/ = undef;
	my $response = <$conn>;
	like($response, '/hello/', 'can serve non latin file names');
}

$conn = get_connection();
print {$conn} "GET /exit HTTP/1.1".$CRLF.$CRLF;
diag('stop test server');
done_testing();