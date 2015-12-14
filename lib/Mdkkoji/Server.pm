package Mdkkoji::Server;

use v5.14;
use strict;
use feature "switch";
use warnings;

use constant {
	HEADER_LINE_MAX_LEN => 2048,
	POST_MAX => 8192
};
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

	my ($opts, $local_path, $type, $request) = @_;

	open my $fh, '<:raw', $local_path or header(404) and return;

	my @stat  = stat($fh);
	my $mtime = format_time($stat[MTIME]);
	my $etag  = $stat[INODE].'-'.$stat[MTIME];

	header(304) and return if
		(defined $request->{'if-modified-since'} &&
		$request->{'if-modified-since'} eq $mtime ) ||
		(defined $request->{'if-none-match'} &&
		$request->{'if-none-match'} eq $etag);

	header(200,
		'Content-Type'   => $type || 'application/octet-stream',
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
	my ($unmapped, $mapped) = @{$opts}{qw| unmapped_responses mapped_responses |};
	select $sock;

	$request->{URL} =~ m|^(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$|;
	my ($path, $query) = ($3, $4);
	$path =~ s{(?<=.)/$}{}; # remove trailing slash

	@{$request}{qw| PATH QUERY |} = ($path, $query);

	my $response;
	if (ref $unmapped->{$path} eq 'CODE') {
		$response = $unmapped->{$path}->($request, $sock);

	} else {
		my $local_path = $opts->to_local_path($request->{PATH});
		if (-d $local_path) {
			$response = $mapped->{DIR}->($local_path, $request, $sock) if -d $local_path;
			
		} elsif (-f $local_path) {
			
			$local_path =~ /\.([\w]+)$/;
			my $suffix = lc ($1 || '');
			$response = ref $mapped->{$suffix} eq 'CODE' ?
				$mapped->{$suffix}->($local_path, $request, $sock) : 
				$opts->serve_file($local_path, $opts->{mime_types}->{$suffix}, $request);

		} else {
			header(404);

		}
	}
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
	shift @segments unless $segments[0];

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
		unmapped_responses => {},
		mapped_responses => {}, 
		mime_type_db   => 'mime-types/mime.dbm',
		@_
	}, __PACKAGE__;

	$opts->{mapped_responses}->{DIR} = sub {} unless exists $opts->{mapped_responses}->{DIR};

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
									if (
										defined $req->{'content-length'} 
										&& $req->{'content-length'} <= POST_MAX
									) {
										$read{$key} = $sock;
										$req->{CONTENT} = $$read;
									} else {
										push @reception, $sock;
									}
								}
								default {
									say $sock 'unknown method';
									push @trash, $sock;
								}
							}

						} else {
							say $sock 'bad header';
							push @trash, $sock;

						}

					}
					if (length $$read > HEADER_LINE_MAX_LEN) {
						say $sock 'too long header';
						push @trash, $sock;
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