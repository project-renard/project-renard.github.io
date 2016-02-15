#!/usr/bin/perl
# Form for creating a new page.
package IkiWiki::Plugin::newpage;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::newpage - add a "create new page" form to actions

=head1 VERSION

This describes version B<1.20120205> of IkiWiki::Plugin::newpage

=cut

our $VERSION = '1.20120205';

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2012 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "newpage",  call => \&getsetup);
	hook(type => "checkconfig", id => "newpage", call => \&checkconfig);
	hook(type => "pageactions", id => "newpage", call => \&pageactions);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "misc",
		},
}

sub checkconfig () {
}

sub pageactions (@) {
    my %params=@_;
    my $page=$params{page};

    my $cgiurl = $config{cgiurl};
    my $form;
    if ($cgiurl and IkiWiki->can("cgi editpage"))
    {
	$form =<<EOT;
    <form method="get" action="$cgiurl" id="newpageform">
<input type="submit" name="do" value="create" class="button"/>
<input type="hidden" name="from" value="$page"/>
<input type="text" name="page" value="" class="input"/>
</form>
EOT
    }
    return ($form);
}


1
