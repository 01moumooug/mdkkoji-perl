use v5.14;
use strict;
use warnings;
use IO::Socket qw/ :crlf /;
use lib 'lib';
use Mdkkoji::Conf;

my %conf = Mdkkoji::Conf::load;

my $fail = 0;
my $conn = IO::Socket::INET->new(
	PeerAddr => 'localhost', 
	PeerPort => $conf{port},
	Proto => 'tcp'
) or die "The server seems not running. Cannot connect to localhost:$conf{port}: $!";

print {$conn} 'GET /hello HTTP/1.1'.$CRLF.$CRLF;
my $answer = <$conn>;
chomp $answer;
$answer eq 'hello' ?
	say "The server seems running at $conf{port}" : 
	die "Something is on port $conf{port}, but it seems not the one";
