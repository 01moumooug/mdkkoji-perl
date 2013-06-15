package Document;

use strict;
use warnings;
use feature qw/ say /;

use Text::Markdown;
use File::Basename;

use NotesConfig;
use Subroutines;
use Database;

our  @LIST_FIELD = (@{$_CONF{'idx_field_names'}},'css','js');

sub new {
	my ($class, $path) = @_;
	my $self = bless {}, $class;
	$path or $path = '';
	$self->read($path) if $path;
	return $self;
}

sub read {

	my ($self, $path) = @_;

	delete $self->{'_cache_html'};
	$self->{'_path'} = $path;
	open my $fh, '<:crlf:utf8', $path or return $self;
	local $/ = "\n\n";
	$self->{'_src'}->{'head'} = <$fh> || '';
	local $/ = undef;
	$self->{'_src'}->{'body'} = <$fh> || '';
	$self->_parse_header();
	return $self;

}

sub _parse_header {
	my $i = 0;
	my ($self) = @_;

	unless ( $self->{'_src'}->{'head'} =~ /^([-*+] )?\w+:\s+/ ) {
		$self->{'_field'} = {};
		$self->{'_src'}->{'body'} =
			$self->{'_src'}->{'head'}.
			$self->{'_src'}->{'body'};
		$self->{'_src'}->{'head'} = '';
		return;
	}

	$self->{'_field'}     = {};
	$self->{'_field_ord'} = {};

	for ( split "\n", $self->{'_src'}->{'head'} ) {
		/^([-*+] )?(\w+):\s+?(.+)$/;
		my ($name, $val) = ($2, $3);
		next unless ($name && $val);

		$name = lc($name);
		$val = [ csv2arr($val) ] if ($name ~~ @LIST_FIELD);
		$self->{'_field_ord_n'}        = $i;
		$self->{'_field_ord'}->{$name} = $i++;
		$self->{'_field'}->{$name}     = $val;
	}
	return 1;
}

sub _make_header {
	my ($self) = @_;
	$self->{'_src'}->{'head'} = '';
	for my $name (
		sort {
			$self->{'_field_ord'}->{$a} <=> $self->{'_field_ord'}->{$b}
		} keys %{$self->{'_field_ord'}}
	) {
		my $val = $self->{'_field'}->{$name};
		   $val = ref($val) eq 'ARRAY' ? join ', ', @$val : $val;
		$name = ucfirst($name);
		$self->{'_src'}->{'head'} .= "- $name: $val\n";
	}
	$self->{'_src'}->{'head'} .= "\n";
}

sub field {
	my ($self, $name, $val) = @_;
	if ( defined $val ) {
		$name = lc($name);
		$val  = [ csv2arr($val) ] if ( ($name ~~ @LIST_FIELD) && (ref($val) ne "ARRAY") );
		unless ($self->{'_field'}->{$name}) {
			$self->{'_field_ord_n'}++;
			$self->{'_field_ord'}->{$name} = $self->{'_field_ord_n'};
		}
		$self->{'_field'}->{$name} = $val;
		$self->_make_header;
		return $self;
	}
	if ( defined $name ) {
		$name = lc($name);
		return $self->{'_field'}->{$name} if defined $self->{'_field'}->{$name};
		return $name ~~ @LIST_FIELD ? [] : '';
	}
	return defined $self->{'_field'} ? $self->{'_field'} : {};
}

sub to_html {
	my $formatter = Text::Markdown->new;
	return $_[0]->{'_cache_html'} if defined $_[0]->{'_cache_html'};
	return '' unless defined $_[0]->{'_src'}->{'body'};
	$_[0]->{'_cache_html'} = $formatter->markdown($_[0]->{'_src'}->{'body'});
	$_[0]->{'_urls'} = $formatter->urls;
	return $_[0]->{'_cache_html'};
}

sub urls {
	return {} unless -f $_[0]->path;
	return $_[0]->{'_urls'} if defined $_[0]->{'_cache_html'};
	$_[0]->to_html;
	return $_[0]->{'_urls'};
}

sub write {
	my ($self,$path) = @_;
	$path or $path = $self->path;
	return unless $path;
	$self->{'_path'} = $path;
	open my $wr, '>', $path;
	print $wr $self->{'_src'}->{'head'}.$self->{'_src'}->{'body'};
	return $self;
}

sub title { return select_title(basename($_[0]->{'_path'}),$_[0]->field('title')); }
sub path  { return $_[0]->{'_path'}; }
sub body  { return $_[0]->{'_src'}->{'body'}; }
sub select_title {
	my ($basename, $title, $sub) = @_;
	return $title if $title;
	local  $_ = $basename;
	$sub or $sub = $_CONF{'basename2title'};
	return &$sub;
}

1;
