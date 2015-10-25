#!/usr/bin/perl
# Copyright © 2008-2011 Joey Hess
# Copyright © 2009-2012 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation
package IkiWiki::Plugin::trail;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "trail", call => \&getsetup);
	hook(type => "needsbuild", id => "trail", call => \&needsbuild);
	hook(type => "preprocess", id => "trailoptions", call => \&preprocess_trailoptions, scan => 1);
	hook(type => "preprocess", id => "trailitem", call => \&preprocess_trailitem, scan => 1);
	hook(type => "preprocess", id => "trailitems", call => \&preprocess_trailitems, scan => 1);
	hook(type => "preprocess", id => "traillink", call => \&preprocess_traillink, scan => 1);
	hook(type => "pagetemplate", id => "trail", call => \&pagetemplate);
	hook(type => "build_affected", id => "trail", call => \&build_affected);
}

# Page state
# 
# If a page $T is a trail, then it can have
# 
# * $pagestate{$T}{trail}{contents} 
#   Reference to an array of lists each containing either:
#     - [pagenames => "page1", "page2"]
#       Those literal pages
#     - [link => "link"]
#       A link specification, pointing to the same page that [[link]]
#       would select
#     - [pagespec => "posts/*", "age", 0]
#       A match by pagespec; the third array element is the sort order
#       and the fourth is whether to reverse sorting
# 
# * $pagestate{$T}{trail}{sort}
#   A sorting order; if absent or undef, the trail is in the order given
#   by the links that form it
#
# * $pagestate{$T}{trail}{circular}
#   True if this trail is circular (i.e. going "next" from the last item is
#   allowed, and takes you back to the first)
#
# * $pagestate{$T}{trail}{reverse}
#   True if C<sort> is to be reversed.
# 
# If a page $M is a member of a trail $T, then it has
#
# * $pagestate{$M}{trail}{item}{$T}[0]
#   The page before this one in C<$T> at the last rebuild, or undef.
#
# * $pagestate{$M}{trail}{item}{$T}[1]
#   The page after this one in C<$T> at the last refresh, or undef.

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

# Cache of pages' old titles, so we can tell whether they changed
my %old_trail_titles;

sub needsbuild (@) {
	my $needsbuild=shift;

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{trail}) {
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# Remember its title, so we can know whether
				# it changed.
				$old_trail_titles{$page} = title_of($page);

				# Remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild. {item} is the
				# only thing that's added for items, not
				# trails, and it's harmless to delete that -
				# the item is being rebuilt anyway.
				delete $pagestate{$page}{trail};
			}
		}
	}

	return $needsbuild;
}

my $scanned = 0;

sub preprocess_trailoptions (@) {
	my %params = @_;

	if (exists $params{circular}) {
		$pagestate{$params{page}}{trail}{circular} =
			IkiWiki::yesno($params{circular});
	}

	if (exists $params{sort}) {
		$pagestate{$params{page}}{trail}{sort} = $params{sort};
	}

	if (exists $params{reverse}) {
		$pagestate{$params{page}}{trail}{reverse} = $params{reverse};
	}

	return "";
}

sub preprocess_trailitem (@) {
	my $link = shift;
	shift;

	# avoid collecting everything in the preprocess stage if we already
	# did in the scan stage
	if (defined wantarray) {
		return "" if $scanned;
	}
	else {
		$scanned = 1;
	}

	my %params = @_;
	my $trail = $params{page};

	$link = linkpage($link);

	add_link($params{page}, $link, 'trail');
	push @{$pagestate{$params{page}}{trail}{contents}}, [link => $link];

	return "";
}

sub preprocess_trailitems (@) {
	my %params = @_;

	# avoid collecting everything in the preprocess stage if we already
	# did in the scan stage
	if (defined wantarray) {
		return "" if $scanned;
	}
	else {
		$scanned = 1;
	}

	# trail members from a pagespec ought to be in some sort of order,
	# and path is a nice obvious default
	$params{sort} = 'path' unless exists $params{sort};
	$params{reverse} = 'no' unless exists $params{reverse};

	if (exists $params{pages}) {
		push @{$pagestate{$params{page}}{trail}{contents}},
			["pagespec" => $params{pages}, $params{sort},
				IkiWiki::yesno($params{reverse})];
	}

	if (exists $params{pagenames}) {
		push @{$pagestate{$params{page}}{trail}{contents}},
			[pagenames => (split ' ', $params{pagenames})];
	}

	return "";
}

sub preprocess_traillink (@) {
	my $link = shift;
	shift;

	my %params = @_;
	my $trail = $params{page};

	$link =~ qr{
			(?:
				([^\|]+)	# 1: link text
				\|		# followed by |
			)?			# optional

			(.+)			# 2: page to link to
		}x;

	my $linktext = $1;
	$link = linkpage($2);

	add_link($params{page}, $link, 'trail');

	# avoid collecting everything in the preprocess stage if we already
	# did in the scan stage
	my $already;
	if (defined wantarray) {
		$already = $scanned;
	}
	else {
		$scanned = 1;
	}

	push @{$pagestate{$params{page}}{trail}{contents}}, [link => $link] unless $already;

	if (defined $linktext) {
		$linktext = pagetitle($linktext);
	}

	if (exists $params{text}) {
		$linktext = $params{text};
	}

	if (defined $linktext) {
		return htmllink($trail, $params{destpage},
			$link, linktext => $linktext);
	}

	return htmllink($trail, $params{destpage}, $link);
}

# trail => [member1, member2]
my %trail_to_members;
# member => { trail => [prev, next] }
# e.g. if %trail_to_members = (
#	trail1 => ["member1", "member2"],
#	trail2 => ["member0", "member1"],
# )
#
# then $member_to_trails{member1} = {
#	trail1 => [undef, "member2"],
#	trail2 => ["member0", undef],
# }
my %member_to_trails;

# member => 1
my %rebuild_trail_members;

sub trails_differ {
	my ($old, $new) = @_;

	foreach my $trail (keys %$old) {
		if (! exists $new->{$trail}) {
			return 1;
		}

		if (exists $old_trail_titles{$trail} &&
			title_of($trail) ne $old_trail_titles{$trail}) {
			return 1;
		}

		my ($old_p, $old_n) = @{$old->{$trail}};
		my ($new_p, $new_n) = @{$new->{$trail}};
		$old_p = "" unless defined $old_p;
		$old_n = "" unless defined $old_n;
		$new_p = "" unless defined $new_p;
		$new_n = "" unless defined $new_n;
		if ($old_p ne $new_p) {
			return 1;
		}

		if (exists $old_trail_titles{$old_p} &&
			title_of($old_p) ne $old_trail_titles{$old_p}) {
			return 1;
		}

		if ($old_n ne $new_n) {
			return 1;
		}

		if (exists $old_trail_titles{$old_n} &&
			title_of($old_n) ne $old_trail_titles{$old_n}) {
			return 1;
		}
	}

	foreach my $trail (keys %$new) {
		if (! exists $old->{$trail}) {
			return 1;
		}
	}

	return 0;
}

my $done_prerender = 0;

sub prerender {
	return if $done_prerender;

	%trail_to_members = ();
	%member_to_trails = ();

	foreach my $trail (keys %pagestate) {
		next unless exists $pagestate{$trail}{trail}{contents};

		my $members = [];
		my @contents = @{$pagestate{$trail}{trail}{contents}};

		foreach my $c (@contents) {
			if ($c->[0] eq 'pagespec') {
				push @$members, pagespec_match_list($trail,
					$c->[1], sort => $c->[2],
					reverse => $c->[3]);
			}
			elsif ($c->[0] eq 'pagenames') {
				my @pagenames = @$c;
				shift @pagenames;
				foreach my $page (@pagenames) {
					if (exists $pagesources{$page}) {
						push @$members, $page;
					}
					else {
						# rebuild trail if it turns up
						add_depends($trail, $page, deptype("presence"));
					}
				}
			}
			elsif ($c->[0] eq 'link') {
				my $best = bestlink($trail, $c->[1]);
				push @$members, $best if length $best;
			}
		}

		if (defined $pagestate{$trail}{trail}{sort}) {
			@$members = IkiWiki::sort_pages(
				$pagestate{$trail}{trail}{sort},
				$members);
		}

		if (IkiWiki::yesno $pagestate{$trail}{trail}{reverse}) {
			@$members = reverse @$members;
		}

		# uniquify
		my %seen;
		my @tmp;
		foreach my $member (@$members) {
			push @tmp, $member unless $seen{$member};
			$seen{$member} = 1;
		}
		$members = [@tmp];

		for (my $i = 0; $i <= $#$members; $i++) {
			my $member = $members->[$i];
			my $prev;
			$prev = $members->[$i - 1] if $i > 0;
			my $next = $members->[$i + 1];

			$member_to_trails{$member}{$trail} = [$prev, $next];
		}

		if ((scalar @$members) > 1 && $pagestate{$trail}{trail}{circular}) {
			$member_to_trails{$members->[0]}{$trail}[0] = $members->[$#$members];
			$member_to_trails{$members->[$#$members]}{$trail}[1] = $members->[0];
		}

		$trail_to_members{$trail} = $members;
	}

	foreach my $member (keys %pagestate) {
		if (exists $pagestate{$member}{trail}{item} &&
			! exists $member_to_trails{$member}) {
			$rebuild_trail_members{$member} = 1;
			delete $pagestate{$member}{trail}{item};
		}
	}

	foreach my $member (keys %member_to_trails) {
		if (! exists $pagestate{$member}{trail}{item}) {
			$rebuild_trail_members{$member} = 1;
		}
		else {
			if (trails_differ($pagestate{$member}{trail}{item},
					$member_to_trails{$member})) {
				$rebuild_trail_members{$member} = 1;
			}
		}

		$pagestate{$member}{trail}{item} = $member_to_trails{$member};
	}

	$done_prerender = 1;
}

sub build_affected {
	my %affected;

	# In principle we might not have done this yet, although in practice
	# at least the trail itself has probably changed, and its template
	# almost certainly contains TRAILS or TRAILLOOP, triggering our
	# prerender as a side-effect.
	prerender();

	foreach my $member (keys %rebuild_trail_members) {
		$affected{$member} = sprintf(gettext("building %s, its previous or next page has changed"), $member);
	}

	return %affected;
}

sub title_of ($) {
	my $page = shift;
	if (defined ($pagestate{$page}{meta}{title})) {
		return $pagestate{$page}{meta}{title};
	}
	return pagetitle(IkiWiki::basename($page));
}

my $recursive = 0;

sub pagetemplate (@) {
	my %params = @_;
	my $page = $params{page};
	my $template = $params{template};

	return unless length $page;

	if ($template->query(name => 'trails') && ! $recursive) {
		prerender();

		$recursive = 1;
		my $inner = template("trails.tmpl", blind_cache => 1);
		IkiWiki::run_hooks(pagetemplate => sub {
				shift->(%params, template => $inner)
			});
		$template->param(trails => $inner->output);
		$recursive = 0;
	}

	if ($template->query(name => 'trailloop')) {
		prerender();

		my @trails;

		# sort backlinks by page name to have a consistent order
		foreach my $trail (sort keys %{$member_to_trails{$page}}) {

			my $members = $trail_to_members{$trail};
			my ($prev, $next) = @{$member_to_trails{$page}{$trail}};
			my ($prevurl, $nexturl, $prevtitle, $nexttitle);

			if (defined $prev) {
				$prevurl = urlto($prev, $page);
				$prevtitle = title_of($prev);
			}

			if (defined $next) {
				$nexturl = urlto($next, $page);
				$nexttitle = title_of($next);
			}

			push @trails, {
				prevpage => $prev,
				prevtitle => $prevtitle,
				prevurl => $prevurl,
				nextpage => $next,
				nexttitle => $nexttitle,
				nexturl => $nexturl,
				trailpage => $trail,
				trailtitle => title_of($trail),
				trailurl => urlto($trail, $page),
			};
		}

		$template->param(trailloop => \@trails);
	}
}

1;
