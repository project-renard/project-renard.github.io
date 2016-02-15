#!/usr/bin/perl
package IkiWiki::Plugin::ftemplate;
use strict;
=head1 NAME

IkiWiki::Plugin::ftemplate - field-aware structured template plugin

=head1 VERSION

This describes version B<1.20100519> of IkiWiki::Plugin::ftemplate

=head1 DESCRIPTION

This uses the "field" plugin to look for values for the template,
as well as the passed-in values.

See doc/plugins/contrib/ftemplate and ikiwiki/directive/ftemplate for docs.

=cut

our $VERSION = '1.20100519';

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field
    HTML::Template
    Encode

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use HTML::Template;
use Encode;

sub import {
	hook(type => "getsetup", id => "ftemplate", call => \&getsetup);
	hook(type => "preprocess", id => "ftemplate", call => \&preprocess,
	     scan => 1);

	IkiWiki::loadplugin("field");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
    my %params=@_;

    if (! exists $params{id}) {
	error gettext("missing id parameter");
    }

    my $template;
    eval {
	# Do this in an eval because it might fail
	# if the template isn't a page in the wiki
	$template=template_depends($params{id}, $params{page},
				   blind_cache => 1);
    };
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$params{id}.tmpl",
				       blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $params{id}.tmpl:")." $@";
	}
	if (! $template) {

	    error sprintf(gettext("%s not found"),
			  htmllink($params{page}, $params{destpage},
				   "/templates/$params{id}"));
	}
    }
    delete $params{template};

    $params{included}=($params{page} ne $params{destpage});

    IkiWiki::Plugin::field::field_set_template_values($template, $params{page});

    # This needs to run even in scan mode, in order to process
    # links and other metadata includes via the template.
    my $scan=! defined wantarray;

    my $output = $template->output;

    return IkiWiki::preprocess($params{page}, $params{destpage},
			       IkiWiki::filter($params{page}, $params{destpage},
					       $output), $scan);
}

1;
