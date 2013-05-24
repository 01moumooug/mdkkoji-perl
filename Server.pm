use strict;
use warnings;
use feature qw/ say switch /;

use IO::Select;
use IO::Socket;
use Fcntl;
use Socket qw/ :crlf /;

use RequestHandler;

$SIG{PIPE} = sub {};
$| = 1;
$/ = $CRLF;

my $main_socket = new IO::Socket::INET(
	Proto     => 'tcp',
	LocalAddr => 'localhost',
	LocalPort => $ARGV[0] || 8888,
	Listen    => SOMAXCONN,
	Reuse     => 1,
) or die $!;

my $read_set = new IO::Select();
   $read_set->add($main_socket);
my $write_set = new IO::Select();

my %read;
my %data;
my @reception;
my @trash;

while (1) {

	my ($readable, $writable) = IO::Select->select($read_set, $write_set, undef, 1800);
	exec('perl', $0, $ARGV[0]) unless ($readable or $writable);

	foreach my $socket (@$readable) {
		if ($socket == $main_socket) {
			
			$read_set->add($socket->accept());

		} else {

			my $key = scalar $socket;
			next if defined $read{$key};
			fcntl($socket, F_SETFL(), O_NONBLOCK());

			defined $data{$key}->{'request'}   or $data{$key}->{'request'}   = {};
			defined $data{$key}->{'read_buff'} or $data{$key}->{'read_buff'} = '';

			my $read    = \$data{$key}->{'read_buff'};
			my $request =  $data{$key}->{'request'};
			if (sysread($socket, my $buff, 2048)) {
				
				$$read .= $buff;
				
				my $crlf_pos = index($$read, $/);
				while ($crlf_pos != -1) {

					local $_ = substr($$read,0,$crlf_pos + 2,'');
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

						given ($request->{'METHOD'}) {
							when ('GET')  {($request->{'URL'},$request->{'CONTENT'}) = split '\?', $request->{'URL'}, 2 }
							when ('POST') { $request->{'CONTENT'} = $$read; }
						}
						defined $request->{'CONTENT'} or $request->{'CONTENT'} = '';
						defined $request->{'content-length'} ?
							$read{$key} = $socket :
							push @reception, $socket;

					} else {

						say $socket 'Sorry, cannot understand your request';
						push @trash, $socket;

					}

					$crlf_pos = index($$read, $CRLF);

				}

			} else {
				push @trash, $socket unless ( $! == EAGAIN() );
			}
		}
	}

	while (my($key, $socket) = each %read) {

		my $request = $data{$key}->{'request'};
		if (defined sysread($socket,my $buff, 2048)) {
			$request->{'CONTENT'} .= $buff;
			if ($request->{'content-length'} == length($request->{'CONTENT'})) {
				delete $read{$key};
				push @reception, $socket;
			}
		} else {
			push @trash, $socket unless ( $! == EAGAIN() );
		}
	}

	for (@$writable) {
		my $buff;
		read($data{scalar $_}->{'RESPONSE'}, $buff, 1024) ?
			print $_   $buff :
			push  @trash, $_ ;
	}

	while (my $socket = pop @reception) {
		my $key = scalar $socket;
		$read_set->remove($socket);
		if ($data{$key}->{'RESPONSE'} = RequestHandler::receptionist($data{$key}->{'request'}, $socket)) {
			$write_set->add($socket);
		} else {
			push @trash, $socket;
		}
	}

	while (my $socket = pop @trash) {
		delete $data{scalar $socket};
		$write_set->remove($socket);
		$read_set->remove($socket);
		close($socket);
	}

}