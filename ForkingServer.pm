use strict;
use warnings;
use feature qw/ say switch /;

use RequestHandler;

use IO::Socket;
use Socket qw/ :crlf /;

$SIG{CHLD} = 'IGNORE';
$SIG{PIPE} = sub {};
$| = 1;
$/ = $CRLF;

my $main_sock = new IO::Socket::INET(
	Proto     => 'tcp',
	LocalAddr => 'localhost',
	LocalPort => $ARGV[0] || 8888,
	Listen    => SOMAXCONN,
	Reuse     => 1
) or die "Cannot create main socket!: $!";

while (my $client = $main_sock->accept()) {

	my $pid = fork();
	
	if ($pid == 0) {

		my $request = {};
		my $response;

		while (<$client>) {
			
			chomp;
			if (/\s*(\w+)\s*([^\s]+)\s*HTTP\/(\d.\d)/) { 
				(
					$request->{'METHOD'},
					$request->{'URL'},
					$request->{'HTTP_VERSION'}
				) = (uc($1), $2, $3);

			} elsif (index($_,':') != -1) {

				%$request = (
					%$request,
					map { s/^\s+|\s+$//; lc($_); } ( split ':', $_, 2 )
				);

			} elsif ($_ eq '') {

				if ($request->{'METHOD'} eq 'POST') {
					read($client, $request->{'CONTENT'}, $request->{'content-length'})
						if defined $request->{'content-length'};
				} elsif ($request->{'METHOD'} eq 'GET') {
					($request->{'URL'},$request->{'CONTENT'}) = split '\?', $request->{'URL'}, 2;
				} else {
					say $client 'undefined method';
					close $client;
				}
				$response = RequestHandler::receptionist($request, $client);
				last;

			} else {

				say $client 'Sorry, cannot understand your request';
				close $client;
				last;

			}
		}

		if ($response) {
		      my $buffer;
		      while (read($response, $buffer, 4096)) {
		          print $client $buffer;
		      }
		}
		exit();

	} else {

	}
}

close $main_sock;
