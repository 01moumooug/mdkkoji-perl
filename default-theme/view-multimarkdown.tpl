[%
	my ($request, $local_path) = @_;
	use Text::MultiMarkdown 'markdown';

	my $doc = Mdkkoji::Document->new($local_path,
		array_fields => $conf{idx_fields}
	);
%]
<!doctype html>
<html>
<head>
	<meta charset="UTF-8">
	<link rel='stylesheet' href='/theme/style.css'>
	<title>[% print $conf{title}; %]: [% print $doc->title; %]</title>
</head>
<body>
	<div class='l-wrapper'>
		<div class='l-inline'>
			[% {
				my @segments = split '/', $request->{PATH}, -1;
				pop @segments;
			%]
				<ul class='no-list-style l-inline tree no-print'>
					<li>
						<a href='/'>$conf{title}</a>
					</li>
					[% if ($#segments) { %]
						[% for (1..$#segments) { %]
						<li>
							<a href='[% print join "/", @segments[0..$_]; %]'>
								[% print unescape($segments[$_]); %]
							</a>
						</li>
						[% } %]
					[% } %]
				</ul>
			[% } %]
		</div>
		<h1 class='title title--view'>[% print $doc->title; %]</h1>
		<ul class='fields fields--view no-list-style'>
			<li class='l-inline'>
				[% print $doc->fields('date') || ''; %]
			</li>
			[% for my $field (@{$conf{idx_fields}}) { %]
				[% if ($doc->fields($field)) { %]
					<li class='l-inline no-print'>
						<h3>[% print ucfirst($field); %]</h3>
						<ul class='l-inline comma-list'><!--
							[% for my $value ($doc->fields($field)) { %]
								--><li><a href='/?[% print build_query({$field => $value}); %]'>$value</a></li><!--
							[% } %]
						--></ul>
					</li>
				[% } %]
			[% } %]
		</ul>
		<div class='content'>
			[% print markdown($doc->body); %]
		</div>
	</div>
</body>
</html>
