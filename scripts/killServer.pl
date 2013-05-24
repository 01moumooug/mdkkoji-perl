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

my $socket = new IO::Socket::INET(
	Proto    => 'tcp',
	PeerAddr => 'localhost',
	PeerPort =>  $ARGV[0] || $_CONF{'port'} || 8888
) or die $!;

say $socket 'GET /pid HTTP/1.0'.$CRLF.$CRLF;
   my $pid = <$socket>;
chomp($pid);
say `kill $pid`;