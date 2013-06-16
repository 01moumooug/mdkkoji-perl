package RequestHandler;

use strict;
use warnings;
use feature qw/ say switch /;

use IO::Socket;
use Socket qw/ :crlf /;
use Cwd    qw/ abs_path /;
use File::Spec::Functions qw/ catpath /;
use Encode;

use NotesConfig;
use Subroutines;
use Document;
use Data::Dumper;

sub receptionist {
	
	my ($request, $socket) = @_;
	select $socket;

	$request->{'CONTENT'} = parse_query($request->{'CONTENT'});

	my ($file, $length, $response);
	given($request->{'URL'}) {
		when ('/hello')   { say "hello" }
		when ('/pid')     { say "$$" }
		when ('/dump')    { say Dumper($request) }
		when (m|^/html/|) {
			($file, $length) = template($_CONF{'template_folder'}.'/html.template',$request);
			print 'HTTP/1.0 200 OK'.$CRLF;
			print 'Content-Length: '.$length.$CRLF.$CRLF;
			open $response, '<',$file;	
		}
		when ('/list' ) { 
			($file, $length) = template($_CONF{'template_folder'}.'/list.template',$request);
			print 'HTTP/1.0 200 OK'.$CRLF;
			print 'Content-Length: '.$length.$CRLF.$CRLF;
			open $response, '<',$file;
		}
		default {
			
			$file = url_decode($request->{'URL'});
			if ($_CONF{'file_name_encoding'}) {
				$file = Encode::decode('utf8',$file);
				$file = Encode::encode($_CONF{'file_name_encoding'},$file);
			}
			$file = $_CONF{'root'}.$file;
			$file = '' unless $file =~ /^\Q$_CONF{'root'}\E/;

			if (-e $file) {

				if (-d $file) {
					$request->{'CONTENT'}->{'dir'} = $file;
					($file, $length) = template($_CONF{'template_folder'}.'/list.template',$request);
				} elsif ( $file =~ /\Q$_CONF{suffix}\E$/ ) {
					($file, $length) = template($_CONF{'template_folder'}.'/view.template',$request);
				} else {
					$length = (stat($file))[7];
				}

				print 'HTTP/1.0 200 OK'.$CRLF;
				print 'Content-Length: '.$length.$CRLF.$CRLF;
				open $response, '<',$file;

			} else {

				($file, $length) = template($_CONF{'template_folder'}.'/404.template',$request);
				print 'HTTP/1.0 404 Not Found'.$CRLF.$CRLF;
				open $response, '<', $file;
				
			}
		}
	}
	return  $response;
}

sub template {

	my $_SOCKET = select;
	my ($_TEMPLATE, $_DATA) = @_;
	my $_BUFF = '';
	
	open    _BUFFER, '>', \$_BUFF;
	select  _BUFFER;
	
	my   $_SRC  = file2scalar($_TEMPLATE);
	     $_SRC =~ s/\"/\\\"/g;
	     $_SRC  = 'print "'.$_SRC;
	     $_SRC =~ s/<%/";/g;
	     $_SRC =~ s/%>/print "/g;
	     $_SRC .= '";';
	eval $_SRC or print $@;
	
	select $_SOCKET;
	return (\$_BUFF, length($_BUFF));

}
1;