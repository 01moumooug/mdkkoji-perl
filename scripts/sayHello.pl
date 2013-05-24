#!/usr/bin/perl

use FindBin;
use lib "$FindBin::RealBin/../";

use strict;
use warnings; 

use feature qw/ say /;

use NotesConfig;
use IO::Socket;

use Socket qw/ :crlf /;

chdir ("$FindBin::RealBin/../");

my $port = $_CONF{'port'} || 8888;
my $socket = new IO::Socket::INET(
	Proto    => 'tcp',
	PeerAddr => 'localhost',
	PeerPort =>  $port
) or say "Cannot open port: $!" and exit;

say $socket 'GET /hello HTTP/1.0'.$CRLF.$CRLF;

   my $answer = <$socket>;
chomp($answer);

$answer eq 'hello' ?
	say STDOUT "The server seems running at $port." :
	say STDOUT "The server seeams not running?";
