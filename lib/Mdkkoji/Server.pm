package Mdkkoji::Server;

use v5.14;
use strict;
use warnings;

use constant {
	MTIME => 9, 
	SIZE  => 7,
	INODE => 1,
};
use constant {
	SEC  => 0, 
	MIN  => 1, 
	HOUR => 2, 
	MDAY => 3, 
	MON  => 4, 
	YEAR => 5, 
	WDAY => 6
};
use constant WEEKDAYS => qw/ Sun Mon Tue Wed Thu Fri Sat /;
use constant MONTHS   => qw/ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec /;

use AnyDBM_File;
use CGI::Util qw/ escape unescape /;
use Encode qw/ encode decode /;
use Fcntl;
use File::Basename;
use File::Spec::Functions qw/ catfile /;
use IO::Select;
use IO::Socket;
use POSIX qw/ :errno_h /;
use Socket qw/ :crlf /;

use Exporter qw/ import /;
our @EXPORT_OK = qw/ header /;

our %status_msg = (
	200 => 'OK', 
	404 => 'NOT FOUND', 
	304 => 'NOT MODIFIED',
);

sub format_time {
	my @t = gmtime(shift);
	return sprintf('%s, %02d %s %d %02d:%02d:%02d GMT',
		(WEEKDAYS)[$t[WDAY]], $t[MDAY], (MONTHS)[$t[MON]], 1900 + $t[YEAR],
		@t[HOUR, MIN, SEC]
	);
}

sub header {
	my $status = shift or return;
	return unless $status_msg{$status};
	my ($field, $value);
	print "HTTP/1.1 $status $status_msg{$status}".$CRLF;
	while (($field, $value, @_) = @_) {
		next unless defined $value;
		print $field.': '.$value.$CRLF;
	}
	print $CRLF;
}

sub serve_file {

	my ($opts, $local_path, $request) = @_;

	open my $fh, '<:raw', $local_path or header(404) and return;

	my @stat  = stat($fh);
	my $mtime = format_time($stat[MTIME]);
	my $etag  = $stat[INODE].'-'.$stat[MTIME];

	# say "use the cache" if not modified
	header(304) and return if
		(defined $request->{'if-modified-since'} &&
		$request->{'if-modified-since'} eq $mtime ) ||
		(defined $request->{'if-none-match'} &&
		$request->{'if-none-match'} eq $etag);

	my $suffix = (fileparse($local_path, @{$opts->{valid_suffixes}}))[2] || '.';

	header(200,
		'Content-Type'   => $opts->{mime_types}->{substr($suffix, 1)} || 'application/octet-stream',
		'Content-Length' => $stat[SIZE], 
		'Etag'           => $etag, 
		'Date'           => format_time(time), 
		'Expires'        => format_time(time + 24 * 60 *60), 
		'Last-Modified'  => $mtime, 
		'Cache-Control'  => 'public', 
	);
	return $fh;

}

sub respond {
	my ($opts, $request, $sock) = @_;

	select $sock;

	$request->{URL} =~ m|^(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$|;
	@{$request}{qw| PATH QUERY |} = ($3, $4);

	$request->{PATH} =~ s{(?<=.)/$}{};
	
	my $local_path = $opts->to_local_path($request->{PATH});
	my $response = $opts->{response}->($local_path, $request, $sock);

	return $opts->serve_file($local_path, $request) unless $response;
	return $response if ref $response eq 'GLOB';

}

sub to_local_path {
	my ($opts, $path) = @_;
	my @segments;
	my $root;
	# collapse segments
	for my $segment (split '/', $path, -1) {
		next if $segment eq '.';
		pop  @segments, next if $segment eq '..';
		push @segments, $segment;
	}
	@segments = map { unescape($_) } @segments;
	@segments = map { encode($opts->{code_page}, decode('utf8', $_)) } @segments;
	shift @segments;

	$root = $opts->{root_overrides}->{$segments[0]};
	defined $root ? shift @segments : ($root = $opts->{doc_root});

	return catfile($root, @segments);
}

sub start {

	local $SIG{PIPE} = sub {};
	local $| = 1;
	local $/ = $CRLF;

	my $opts = bless {
		port           => 8888, 
		doc_root       => 'docs',
		root_overrides => {}, 
		code_page      => 'utf8',
		response       => sub { return undef }, 
		mime_type_db   => 'mime-types/mime.dbm',
		valid_suffixes => [ qw/ .tar.gz .tar.bz /, qr/\.\w+$/ ],
		secret_orders  => {
			stop => sub { exit(); }
		},
		@_
	}, __PACKAGE__;

	tie my %mime, 'AnyDBM_File', $opts->{mime_type_db}, O_RDONLY, 0666 or
		warn "cannot open mime type db: $opts->{mime_type_db}".$!;
	$opts->{mime_types} = \%mime;

	my $main_sock = IO::Socket::INET->new(
		Proto     => 'tcp',
		LocalAddr => 'localhost',
		LocalPort => $opts->{port},
		Listen    => SOMAXCONN,
		Reuse     => 1,
		Blocking  => 0
	) or die $!;

	my ($read_set, $write_set) = (new IO::Select(), new IO::Select());
	my (%read, %data, @reception, @trash);

	$read_set->add($main_sock);

	while (1) {

		# listen
		my ($readable, $writable) = IO::Select->select($read_set, $write_set, undef, 1800);
		last unless ($readable or $writable);

		# read header
		foreach my $sock (@$readable) {
			if ($sock == $main_sock) {
				my $client = $sock->accept();
				@{$data{scalar $client}}{qw| req read_buff |} = ({}, '');
				$read_set->add($client);

			} else {

				my $key = scalar $sock;
				next if defined $read{$key};
				my $read = \$data{$key}->{read_buff};
				my $req  = $data{$key}->{req};

				if (sysread($sock, my $buff, 2048)) {
					
					$$read .= $buff;
					
					my $crlf_pos;

					while (($crlf_pos = index($$read, $CRLF)) != -1) {

						local $_ = substr($$read, 0, $crlf_pos + 2, '');
						chomp;

						if (/\s*(\w+)\s*([^\s]+)\s*HTTP\/(\d.\d)/) { 
							@{$req}{qw|METHOD URL HTTP_VERSION|} = (uc($1), $2, $3);

						} elsif (/:/) {
							my ($key, $val) = map { s/^\s+|\s+$//r; } split ':', $_, 2;
							$req->{lc($key)} = $val;

						} elsif ($_ eq '') {
							given ($req->{METHOD}) {
								when ('GET')  { push @reception, $sock; }
								when ('POST') {
									if (defined $req->{'content-length'}) {
										$read{$key} = $sock;
										$req->{CONTENT} = $$read;
									}
								}
								when ('MSG') {
									my ($fh, $msg);
									open  $fh, '<', '.msg';
									$msg = <$fh>;
									close $fh;
									open  $fh, '>', '.msg';
									close $fh;
									$opts->{secret_orders}->{$msg}->() if ref $opts->{secret_orders}->{$msg} eq 'CODE';
								}
								default {
									say $sock 'unknown method';
									push @trash, $sock;
								}
							}

						} else {
							say $sock 'cannot understand your request';
							push @trash, $sock;

						}

					}

				} else {
					push @trash, $sock unless ( $! == EAGAIN );

				}
			}
		}

		# read POST content
		while (my($key, $sock) = each %read) {

			my $request = $data{$key}->{req};
			if (defined sysread($sock, my $buff, 2048)) {
				$request->{CONTENT} .= $buff;
				if ($request->{'content-length'} == length($request->{CONTENT})) {
					delete $read{$key};
					push @reception, $sock;
				}
			} else {
				push @trash, $sock unless ( $! == EAGAIN );

			}

		}

		# generate response
		while (my $sock = pop @reception) {
			my $key = scalar $sock;
			$read_set->remove($sock);

			if ($data{$key}->{RESPONSE} = $opts->respond($data{$key}->{req}, $sock)) {
				$write_set->add($sock);

			} else {
				push @trash, $sock;

			}
		}

		# write response 
		for (@$writable) {
			my $buff;
			sysread($data{scalar $_}->{RESPONSE}, $buff, 1024) ?
				print $_ $buff :
				push  @trash, $_ ;
		}

		# close socket
		while (my $sock = pop @trash) {
			delete $data{scalar $sock};
			$write_set->remove($sock);
			$read_set->remove($sock);
			close($sock);
		}

	}
}

1;