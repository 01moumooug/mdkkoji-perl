use v5.14;
use strict;
use warnings;
use IO::Socket qw/ :crlf /;
use lib 'lib';
use Mdkkoji::Conf;

my %conf = Mdkkoji::Conf::load;

my $conn = IO::Socket::INET->new(
	PeerAddr => 'localhost', 
	PeerPort => $conf{port},
	Proto => 'tcp'
) or exit;

open  MSG, '>', '.msg';
print MSG 'stop';
close MSG;

print {$conn} 'MSG / HTTP/1.1'.$CRLF.$CRLF;
