#!/usr/bin/perl
# POD as a wiki page type.
# See plugins/contrib/pod for documentation.
package IkiWiki::Plugin::pod;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::pod - process pages written in POD format.

=head1 VERSION

This describes version B<1.20100519> of IkiWiki::Plugin::pod

=cut

our $VERSION = '1.20100519';

=head1 PREREQUISITES

    IkiWiki
    Pod::Xhtml
    IO::String

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use Pod::Xhtml;
use IO::String;

sub import {
	hook(type => "getsetup", id => "pod", call => \&getsetup);
	hook(type => "checkconfig", id => "pod", call => \&checkconfig);
	hook(type => "htmlize", id => "pod", call => \&htmlize);
	hook(type => "htmlize", id => "pm", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			description => "process pages written in POD format",
			safe => 1,
			rebuild => undef,
		},
		pod_index => {
			type => "boolean",
			example => "0",
			description => "if true, make an index for the page",
			safe => 0,
			rebuild => 0,
		},
		pod_toplink => {
			type => "string",
			example => "Top",
			description => "label for link to top of page",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig () {
    if (!defined $config{pod_index})
    {
	$config{pod_index} = 1;
    }
    if (!defined $config{pod_toplink})
    {
	$config{pod_toplink} = '';
    }
    return 1;
}

sub htmlize (@) {
    my %params=@_;
    my $page = $params{page};

    my $toplink = $config{pod_toplink} ?
	sprintf '<p><a href="#TOP" class="toplink">%s</a></p>',
	$config{pod_toplink} : '';

    my $parser = new Pod::Xhtml(
				StringMode => 1,
				FragmentOnly => 1,
				MakeIndex  => $config{pod_index},
				TopLinks   => $toplink,
			       );
    my $io = IO::String->new($params{content});
    $parser->parse_from_filehandle($io);

    return $parser->asString;
}

1;
