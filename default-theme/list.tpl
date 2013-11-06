[%
	my ($request, $query, $list, $dirs) = @_;
	my %pg;
	$pg{now} = $query->fields('pg');
	@pg{qw|start end last|} = $list->paging_params($pg{now}, $conf{entries_per_page});

	my $entries = $list->by_page($pg{now}, $conf{entries_per_page});
	my $total   = $list->total;

%]
<!doctype html>
<html>
<head>
	<meta charset="UTF-8">
	<title>$conf{title}</title>
	<link rel='stylesheet' type='text/css' href='/theme/style.css'>
</head>
<body>
	<div class='l-wrapper'>
		<div class='l-head'>
			<h1 class='title'><a href='/'>$conf{title}</a></h1>
		</div>
		<div class='l-main'>
			<div class='main-inner'>
				<ul class='fields fields--list no-list-style'>
					<li class='l-inline'>
						<h3>Location</h3>
						[% { my @segments; %]
							<ul class='no-list-style l-inline tree'>
								[% for (split '/', $request->{PATH}, -1) { %]
									<li>
										<a href='[%
											push @segments, $_ and print join "/", (@segments, "..");
										%]?[%
											print build_query($query->clone->set_fields(pg => 0)->fields);
										%]' class='unset-link'>
											[% print unescape($_); %]
										</a>
									</li>
								[% } %]
							</ul>
						[% } %]
					</li>
				</ul>

				<!-- Matched Entries -->
				<ul class='no-list-style entries'>
					[% for my $entry (@$entries) { %]
						<li>
							<a href="/$entry->{ref}">
								<span class='entries__date'>[% print strftime('%Y-%m-%d', gmtime($entry->{date})); %]</span>
								$entry->{title}
							</a>
							[% if (defined $entry->{excerpt}) { %]
								<div class='entries__excerpt'>$entry->{excerpt}</div>
							[% } %]
						</li>
					[% } %]
					[% for (1..($conf{entries_per_page} - @$entries)) { %]
						<li>&nbsp;</li>
					[% } %]
				</ul>

				<!-- paging -->
				[% if ($total > $conf{entries_per_page}) { %]
					<ul class='no-list-style l-inline paging'><!--
						[% if ($pg{now} != 0) { %]
							--><li><!--
								--><a href="?[% print build_query($query->clone->set_fields(pg => 0)->fields); %]">처음</a><!--
							--></li><!--
						[% } %]
						[% for ($pg{start}..$pg{end}) { %]
							--><li><!--
								[% if ($_ != $pg{now}) { %]
										--><a href="?[% print build_query($query->clone->set_fields(pg => $_)->fields); %]">[% print $_ + 1; %]</a><!--
								[% } else { %]
									--><span>[% print $_ + 1; %]</span><!--
								[% } %]
							--></li><!--
						[% } %]
						[% if ($pg{now} != $pg{last}) { %]
							--><li><!--
								--><a href="?[% print build_query($query->clone->set_fields(pg => $pg{last})->fields); %]">끝</a><!--
							--></li><!--
						[% } %]
					--></ul>
				[% } %]
			</div>
		</div>

		<div class='l-side'>
			<div class='side-section'>
				[% if ($query->fields('r')) { %]
					<a href="?[% print build_query($query->clone->set_fields(r => 0, pg => 0)->fields); %]">
						Directory
					</a>
				[% } else { %]
					<a href="?[% print build_query($query->clone->set_fields(r => 1, pg => 0)->fields); %]">
						Recursive
					</a>
				[% } %]
			</div>
			<div class='side-section'>
				<h3>Directories</h3>
				<ul class='no-list-style'>
					[% for (@$dirs) { %]
						<li>
							<a href='[%
								print join "/", (split ("/", $request->{PATH}), $_);
							%]?[%
								print build_query($query->clone->set_fields(pg => 0)->fields);
							%]'>$_</a>
						</li>
					[% } %]
				</ul>
			</div>
			<div class='side-section'>
				<h3>Search</h3>
				[% {
					my ($key, $val);
					my $query_pairs = build_query_pairs($query->clone->set_fields(pg => 0)->fields);
				%]
					<form action='[% print $request->{PATH}; %]' method='get'>
						[% while (($key, $val, @$query_pairs) = @$query_pairs) { %]
							[% next if $key eq 'search'; %]
							<input
								type='hidden'
								name='[% print CGI::Util::simple_escape($key); %]'
								value='[% print CGI::Util::simple_escape($val); %]'
							>
						[% } %]
						<input type='text' name='search' value='[% print CGI::Util::simple_escape($query->fields("search")); %]'>
					</form>
				[% } %]
			</div>
			<!-- statistics -->
			<div class='side-section'>
				[% for my $field (@{$conf{idx_fields}}) { %]
					<h3>[% print ucfirst($field); %]</h3>
					<ul class='no-list-style'>
						[% for my $stat (@{$list->count_entries($field)}) { %]
							<li>
								[% if ($total != $stat->{count}) { %]
									<a href="?[% print build_query($query->clone->push($field => $stat->{value})->set_fields(pg => 0)->fields); %]" class='set-link'>
										$stat->{value}($stat->{count})
									</a>
								[% } else { %]
									[% if ($stat->{value} ~~ ($query->fields($field))) { %]
										<a href="?[% print build_query($query->clone->pull($field, $stat->{value})->set_fields(pg => 0)->fields); %]" class='unset-link'>
											$stat->{value}($stat->{count})
										</a>
									[% } else { %]
										$stat->{value}($stat->{count})
									[% } %]
								[% } %]
							</li>
						[% } %]
					</ul>
				[% } %]
			</div>
		</div>
	</div>
</body>
</html>
