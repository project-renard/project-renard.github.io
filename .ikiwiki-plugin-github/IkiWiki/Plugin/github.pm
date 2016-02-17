#!/usr/bin/perl
package IkiWiki::Plugin::github;

use warnings;
use strict;
use IkiWiki 3.00;

# github:
#   repo: orgname/reponame
#   branch: branchname
# <branchname> is the branch that has the ikiwiki source
#
# TODO extract this information from the git plugin

sub import {
	hook(type => "pagetemplate", id => "skeleton", call => \&pagetemplate);
}

sub pagetemplate (@) {
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};

	my $page_source = $pagesources{ $page };
	return unless $page_source;

	my $github_config = $config{github};

	my $editurl = "https://github.com/@{[ $github_config->{repo} ]}/edit/@{[ $github_config->{branch} ]}/$page_source";

	$template->param( have_actions => 1 );
	$template->param( editurl => $editurl );
}

1
