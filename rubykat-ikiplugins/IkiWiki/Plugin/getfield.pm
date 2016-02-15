#!/usr/bin/perl
package IkiWiki::Plugin::getfield;
use strict;
=head1 NAME

IkiWiki::Plugin::getfield - query the values of fields

=head1 VERSION

This describes version B<1.20110906> of IkiWiki::Plugin::getfield

=cut

our $VERSION = '1.20110906';

=head1 DESCRIPTION

Ikiwiki getfield plugin.
Substitute field values in the content of the page.

See plugins/contrib/getfield for documentation.

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "getfield",  call => \&getsetup);
	hook(type => "filter", id => "getfield", call => \&do_filter, last=>1);

	IkiWiki::loadplugin("field");
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub do_filter (@) {
    my %params=@_;
    my $page = $params{page};
    my $destpage = ($params{destpage} ? $params{destpage} : $params{page});

    my $page_file = $pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (defined $page_type)
    {
	# substitute {{$var}} variables (source-page)
	$params{content} =~ s/(\\?){{\$([-\w]+)}}/get_field_value($1,$2,$page)/eg;

	# substitute {{$page#var}} variables (source-page)
	$params{content} =~ s/(\\?){{\$([-\w\/]+)#([-\w]+)}}/get_other_page_field_value($1, $3,$page,$2)/eg;
    }

    $page_file=$pagesources{$destpage} || return $params{content};
    $page_type=pagetype($page_file);
    if (defined $page_type)
    {
	# substitute {{+$var+}} variables (dest-page)
	$params{content} =~ s/(\\?){{\+\$([-\w]+)\+}}/get_field_value($1,$2,$destpage)/eg;
	# substitute {{+$page#var+}} variables (source-page)
	$params{content} =~ s/(\\?){{\+\$([-\w\/]+)#([-\w]+)\+}}/get_other_page_field_value($1, $3,$destpage,$2)/eg;
    }

    return $params{content};
} # do_filter

#---------------------------------------------------------------
# Private functions
# --------------------------------
sub get_other_page_field_value ($$$) {
    my $escape = shift;
    my $field = shift;
    my $page = shift;
    my $other_page = shift;

    if (length $escape)
    {
	return "{{\$${other_page}#${field}}}";
    }
    my $use_page = bestlink($page, $other_page);
    # add a dependency for the page from which we get the value
    add_depends($page, $use_page);

    my $val = get_field_value($field, $use_page);
    if ($val eq $field)
    {
	return "${other_page}#$field";
    }
    return $val;

} # get_other_page_field_value

sub get_field_value ($$) {
    my $escape = shift;
    my $field = shift;
    my $page = shift;

    if (length $escape)
    {
	return "{{\$${field}}}";
    }
    my $value = IkiWiki::Plugin::field::field_get_value($field,$page);
    return $value if defined $value;

    # if there is no value, return the field name.
    return $field;
} # get_field_value

1;
