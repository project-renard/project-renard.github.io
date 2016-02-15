#!/usr/bin/perl
# Ikiwiki field plugin.
package IkiWiki::Plugin::field;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::field - middle-end for per-page record fields.

=head1 VERSION

This describes version B<1.20120105> of IkiWiki::Plugin::field

=cut

our $VERSION = '1.20120105';

=head1 DESCRIPTION

Used by other plugins as an interface; treats each page as
a record which can have multiple fields.

See doc/plugin/contrib/field.mdwn for documentation.

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

my %Fields = (
    _first => {
	id => '_first',
	seq => 'BB',
    },
    _last => {
	id => '_last',
	seq => 'YY',
    },
    _middle => {
	id => '_middle',
	seq => 'MM',
    },
);
my @FieldsLookupOrder = ();

my %Cache = ();

sub field_get_value ($$;@);

sub import {
	hook(type => "getsetup", id => "field",  call => \&getsetup);
	hook(type => "checkconfig", id => "field", call => \&checkconfig);
	hook(type => "preprocess", id => "field", call => \&preprocess, scan=>1);
	hook(type => "scan", id => "field", call => \&scan, last=>1);
	hook(type => "pagetemplate", id => "field", call => \&pagetemplate);
}

# ===============================================
# Hooks
# ---------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		field_register => {
			type => "hash",
			example => "field_register => {meta => 'last'}",
			description => "simple registration of fields by plugin",
			safe => 0,
			rebuild => undef,
		},
		field_allow_config => {
			type => "boolean",
			example => "field_allow_config => 1",
			description => "allow config settings to be queried",
			safe => 0,
			rebuild => undef,
		},
		field_tags => {
			type => "hash",
			example => "field_tags => {BookAuthor => '/books/authors'}",
			description => "fields flagged as tag-fields",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {

    # use the simple by-plugin pagestatus method for
    # those plugins registered with the field_register config option.
    if (defined $config{field_register})
    {
	if (ref $config{field_register} eq 'ARRAY')
	{
	    foreach my $id (@{$config{field_register}})
	    {
		field_register(id=>$id);
	    }
	}
	elsif (ref $config{field_register} eq 'HASH')
	{
	    foreach my $id (keys %{$config{field_register}})
	    {
		field_register(id=>$id, order=>$config{field_register}->{$id});
	    }
	}
	else
	{
	    field_register(id=>$config{field_register});
	}
    }
    # also register the "field" directive
    field_register(id=>'field_directive');

    if (!defined $config{field_allow_config})
    {
	$config{field_allow_config} = 0;
    }
} # checkconfig

sub preprocess (@) {
    my %params= @_;

    # add the content of the field directive to the fields
    if (!defined wantarray) # scanning
    {
	my $page_type = pagetype($pagesources{$params{page}});
	# perform htmlizing on content on HTML pages
	$page_type = $config{default_pageext} if $page_type eq 'html';

	foreach my $key (keys %params)
	{
	    if ($key =~ /^(page|destpage|preview|_raw)$/) # skip non-fieldname things
	    {
		next;
	    }
	    my $value = $params{$key};
	    if ($value and !$params{_raw})
	    {
		# HTMLize the text
		$value = IkiWiki::htmlize($params{page},
					  $params{destpage},
					  $page_type,
					  $value) unless (!$page_type);

		# Preprocess the text to expand any preprocessor directives
		# embedded inside it.
		# First in scan mode, then in real mode
		my $fake_value = IkiWiki::preprocess
		    ($params{page},
		     $params{destpage}, 
		     IkiWiki::filter($params{page},
				     $params{destpage},
				     $value)
		    );
		($value) = IkiWiki::preprocess
		    ($params{page},
		     $params{destpage}, 
		     IkiWiki::filter($params{page},
				     $params{destpage},
				     $value)
		    );
	    }
	    $pagestate{$params{page}}{field_directive}{$key} = $value;
	}
    }
    return '';
} # preprocess

sub scan (@) {
    my %params=@_;

    scan_for_tags(%params);
} # scan


sub pagetemplate (@) {
    my %params=@_;

    field_set_template_values($params{template}, $params{page});
} # pagetemplate

# ===============================================
# Field interface
# ---------------------------

sub field_register (%) {
    my %param=@_;
    if (!exists $param{id})
    {
	error 'field_register requires id parameter';
	return 0;
    }
    if (exists $param{get_value} and !ref $param{get_value})
    {
	error 'field_register get_value parameter must be function';
	return 0;
    }
    if (exists $param{call} and !exists $param{get_value})
    {
	error 'field_register "call" is obsolete, use "get_value"';
	return 0;
    }
    if (exists $param{all_values} and !exists $param{get_value})
    {
	error 'field_register "all_values" is obsolete, use "get_value"';
	return 0;
    }

    my $id = $param{id};
    $Fields{$id} = \%param;

    # add this to the ordering hash
    # first, last, order; by default, middle
    my $when = ($param{first}
		? '_first'
		: ($param{last}
		   ? '_last'
		   : ($param{order}
		      ? ($param{order} eq 'first'
			 ? '_first'
			 : ($param{order} eq 'last'
			    ? '_last'
			    : ($param{order} eq 'middle'
			       ? '_middle'
			       : $param{order}
			      )
			   )
			)
		      : '_middle'
		     )
		  ));
    add_lookup_order($id, $when);
    return 1;
} # field_register

sub field_get_value ($$;@) {
    my $field_name = shift;
    my $page = shift;
    my %params = @_;

    my $lc_field_name = $field_name;
    $lc_field_name =~ tr/A-Z/a-z/;

    #
    # passed-in values override all other values
    #
    if (exists $params{$lc_field_name})
    {
	return $params{$lc_field_name};
    }

    # This uses lazy evaluation; that is, rather than pre-calculating
    # all field values as soon as possible, put it off until the last
    # minute, and don't derive a field value until it's needed.
    # This not only has the advantage of not doing needless calculations,
    # but it also enables field values to depend on other field values
    # without having to worry about the order in which the fields are defined.

    # check the cache in case we've already got this value
    if (defined $Cache{$page}{$lc_field_name})
    {
	return $Cache{$page}{$lc_field_name};
    }

    # The reason why it checks every registered plugin rather than have
    # plugins declare which fields they know about, is that it is quite
    # possible that a plugin doesn't know, ahead of time, what fields
    # will be available; for example, a YAML format plugin would return
    # any field that happens to be defined in a YAML page file, which
    # could be anything!

    my $value = undef;
    my $basevalue = undef;
    my $basename = $lc_field_name;
    my $suffix = '';
    if ($basename =~ /(.*)[-_](loop|html|raw|tagpage|tagpage_loop)$/o)
    {
	$basename = $1;
	$suffix = $2;
    }

    if (!@FieldsLookupOrder)
    {
	build_fields_lookup_order();
    }
    for (my $i = 0; (!defined $basevalue && $i < @FieldsLookupOrder); $i++)
    {
	my $id = $FieldsLookupOrder[$i];
	if (exists $pagestate{$page}{$id}{$basename})
	{
	    $basevalue = $pagestate{$page}{$id}{$basename};
	}
	elsif (exists $Fields{$id}{get_value})
	{
	    $basevalue = $Fields{$id}{get_value}->($basename, $page);
	}
    }

    # Okay, so we didn't find a value, but
    # this could be a basic derived value
    if (!defined $basevalue)
    {
	$basevalue = calculated_values($lc_field_name, $page);
    }
    if (defined $basevalue)
    {
	$Cache{$page}{$basename} = $basevalue;
    }
    if ($basename ne $lc_field_name)
    {
	if ($suffix eq 'raw')
	{
	    return $basevalue;
	}
	elsif ($suffix eq 'html')
	{
	    $value = htmlize_value(field=>$basename,
		value=>$basevalue,
		page=>$page);
	}
	elsif ($suffix eq 'loop' || $suffix eq 'tagpage_loop')
	{
	    $value = make_loop_value(field=>$basename,
		value=>$basevalue,
		type=>$suffix,
		page=>$page);
	}
	elsif ($suffix eq 'tagpage')
	{
	    $value = make_tagpage_value(field=>$basename,
		value=>$basevalue,
		page=>$page);
	}
	else # unknown
	{
	    $value = $basevalue;
	}
    }
    else
    {
	$value = $basevalue;
    }
    if (defined $value)
    {
	$Cache{$page}{$lc_field_name} = $value;
    }

    return $value;
} # field_get_value

sub field_set_template_values ($$;@) {
    my $template = shift;
    my $page = shift;
    my %params = @_;

    # Find the parameter names in this template
    # and see if you can find their values.

    # The reason we check the template for field names is because we
    # don't know what fields the registered plugins provide; and this is
    # reasonable because for some plugins (e.g. a YAML data plugin) they
    # have no way of knowing, ahead of time, what fields they might be
    # able to provide.

    my @parameter_names = $template->param();
    foreach my $field (@parameter_names)
    {
	# Don't redefine if the field already has a value set.
	next if ($template->param($field));

	# for speed, try to avoid calling field_get_value if we don't need to
	my $value = (exists $params{$field}
	    ? $params{$field}
	    : (exists $Cache{$page}{$field}
		? $Cache{$page}{$field}
		: field_get_value($field, $page, %params)));
	if (defined $value)
	{
	    my $type = $template->query(name => $field);
	    if ($type eq 'LOOP' and ref $value eq 'ARRAY')
	    {
		$template->param($field => $value);
	    }
	    elsif (ref $value eq 'ARRAY' and $type ne 'LOOP')
	    {
		$template->param($field => join(' ', @{$value}));
	    }
	    elsif (!ref $value)
	    {
		$template->param($field => $value);
	    }
	    else
	    {
		debug("field_set_template_values ${page}/${field} not scalar or array");
	    }
	}
    }

} # field_set_template_values

# ===============================================
# Private Functions
# ---------------------------

sub scan_for_tags (@) {
    my %params=@_;
    my $page=$params{page};
    my $content=$params{content};

    # scan for tag fields
    if ($config{field_tags})
    {
	foreach my $field (keys %{$config{field_tags}})
	{
	    my $lc_field = $field;
	    $lc_field =~ tr/A-Z/a-z/;
	    my $value = field_get_value($lc_field, $page);
	    if ($value)
	    {
		if (ref $value eq 'ARRAY')
		{
		    foreach my $tag (@{$value})
		    {
			my $link = $config{field_tags}{$field} . '/' . titlepage($tag);
			add_link($page, $link, $lc_field);
		    }
		}
		elsif (!ref $value)
		{
		    my $link = $config{field_tags}{$field} . '/' . titlepage($value);
		    add_link($page, $link, $lc_field);
		}
	    }
	}
    } # if field_tags
} # scan_for_tags

# Calculate the lookup order
# <module, >module, AZ
# This is crabbed from the PmWiki Markup function
sub add_lookup_order  {
    my $id = shift;
    my $when = shift;

    # may have given an explicit ordering
    if ($when =~ /^[A-Z][A-Z]$/o)
    {
	$Fields{$id}{seq} = $when;
    }
    else
    {
	my $cmp = '=';
	my $seq_field = $when;
	if ($when =~ /^([<>])(.+)$/o)
	{
	    $cmp = $1;
	    $seq_field = $2;
	}
	$Fields{$seq_field}{dep}{$id} = $cmp;
	if (exists $Fields{$seq_field}{seq}
	    and defined $Fields{$seq_field}{seq})
	{
	    $Fields{$id}{seq} = $Fields{$seq_field}{seq} . $cmp;
	}
    }
    if ($Fields{$id}{seq})
    {
	foreach my $i (keys %{$Fields{$id}{dep}})
	{
	    my $m = $Fields{$id}{dep}{$i};
	    add_lookup_order($i, "$m$id");
	}
	delete $Fields{$id}{dep};
    }
} # add_lookup_order

sub build_fields_lookup_order {

    # remove the _first, _last and _middle dummy fields
    # because we don't need them anymore
    delete $Fields{_first};
    delete $Fields{_last};
    delete $Fields{_middle};
    my %lookup_spec = ();
    # Make a hash of the lookup sequences
    foreach my $id (sort keys %Fields)
    {
	my $seq = ($Fields{$id}{seq}
		   ? $Fields{$id}{seq}
		   : 'MM');
	if (!exists $lookup_spec{$seq})
	{
	    $lookup_spec{$seq} = {};
	}
	$lookup_spec{$seq}{$id} = 1;
    }

    # get the field-lookup order by (a) sorting by lookup_spec
    # and (b) sorting by field-name for the fields that registered
    # the same field-lookup order
    foreach my $ord (sort keys %lookup_spec)
    {
	push @FieldsLookupOrder, sort keys %{$lookup_spec{$ord}};
    }
} # build_fields_lookup_order

sub htmlize_value {
    my %params = @_;

    my $field = $params{field};
    my $value = $params{value};
    my $page = $params{page};

    return $value if (!defined $value || !$value);

    my $pagesource = $pagesources{$page};
    return undef unless $pagesource;
    my $page_type = pagetype($pagesource);

    return $value if (!$page_type);

    my $retval = $value;

    if (!ref $value)
    {
	$retval = 
	IkiWiki::htmlize($page, $page, $page_type, $value);
    }
    elsif (ref $value eq 'ARRAY')
    {
	# When HTML-izing an array, make it a list
	$retval = IkiWiki::htmlize($page, $page,
	    $page_type,
	    "\n\n* " . join("\n* ", @{$value}) . "\n");
    }
    return $retval;
} # htmlize_value

sub make_loop_value {
    my %params = @_;

    my $field = $params{field};
    my $value = $params{value};

    return undef if (!$value);

    my $page = $params{page};
    my $type = $params{type};

    my $retval = undef;

    if (ref $value eq 'ARRAY')
    {
	$retval = [];
	foreach my $v (@{$value})
	{
	    push @{$retval}, {$field => $v};
	}
    }
    elsif (!ref $value)
    {
	$retval = [{$field => $value}];
    }
    
    if (exists $config{field_tags}{$field})
    {
	my @loop = ();
	my @orig_loop = @{$retval};
	for (my $i = 0; $i < @orig_loop; $i++)
	{
	    my $tag = $orig_loop[$i]->{$field};
	    my $link = $config{field_tags}{$field} . '/' . titlepage($tag);
	    $orig_loop[$i]->{"${field}-tagpage"} = $link;
	    push @loop, {$field => $link};
	}
	if ($type eq 'loop')
	{
	    $retval = \@orig_loop;
	}
	else # tagpage_loop
	{
	    $retval = \@loop;
	}
    }
    return $retval;
} # make_loop_value

sub make_tagpage_value {
    my %params = @_;

    my $field = $params{field};
    my $value = $params{value};
    my $page = $params{page};

    my $retval = undef;

    if (exists $config{field_tags}{$field})
    {
	if (ref $value eq 'ARRAY')
	{
	    my @tagpages = ();
	    foreach my $tag (@{$value})
	    {
		my $link = $config{field_tags}{$field} . '/' . titlepage($tag);
		push @tagpages, $link;
	    }
	    $retval = join(' ', @tagpages);
	}
	elsif (!ref $value)
	{
	    $retval = $config{field_tags}{$field} . '/' . titlepage($value);
	}
    }
    
    return $retval;
} # make_tagpage_value

# standard values deduced from other values
sub calculated_values {
    my $field_name = shift;
    my $page = shift;

    return undef unless defined $page;
    my $value = undef;

    # Exception for titles
    # If the title hasn't been found, construct it
    if ($field_name eq 'title')
    {
	$value = pagetitle(IkiWiki::basename($page));
    }
    elsif ($field_name eq 'pagetitle')
    {
	$value = pagetitle(IkiWiki::basename($page));
    }
    elsif ($field_name eq 'baseurl')
    {
	$value = IkiWiki::baseurl($page);
    }
    elsif ($field_name eq 'titlecaps')
    {
	$value = (exists $pagestate{$page}{meta}{title}
	    ? $pagestate{$page}{meta}{title} : undef);
        if (!$value)
        {
            if (defined $Cache{$page}{title})
            {
                $value = $Cache{$page}{title};
            }
        }
        if (!$value)
        {
            for (my $i = 0; (!$value && $i < @FieldsLookupOrder); $i++)
            {
                my $id = $FieldsLookupOrder[$i];
                if (exists $pagestate{$page}{$id}{title})
                {
                    $value = $pagestate{$page}{$id}{title};
                }
                elsif (exists $Fields{$id}{get_value})
                {
                    $value = $Fields{$id}{get_value}->('title', $page);
                }
            }
        }
        if (!$value)
        {
            $value = pagetitle(IkiWiki::basename($page));
        }
        if ($value)
        {
            $Cache{$page}{title} = $value;
        }

	$value =~ s/\.\w+$//; # remove extension
	$value =~ s/ (
		      (^\w)    #at the beginning of the line
		      |      # or
		      (\s\w)   #preceded by whitespace
		     )
	    /\U$1/xg;
    }
    # and set "page" if desired
    elsif ($field_name eq 'page')
    {
	$value = $page;
    }
    # the page above this page; aka the current directory
    elsif ($field_name eq 'parent_page')
    {
	if ($page =~ m{^(.*)/[-\.\w]+$}o)
	{
	    $value = $1;
	}
	else # top-level page
	{
	    $value = 'index';
	}
    }
    elsif ($field_name eq 'basename')
    {
	$value = IkiWiki::basename($page);
    }
    # apply the "titlepage" function to the field value(s)
    elsif ($field_name =~ /^(.*)-titlepage$/)
    {
	my $basename = $1;
	$value = field_get_value($basename, $page);
	if (ref $value eq 'ARRAY')
	{
	    my @values = ();
	    foreach my $v (@{$value})
	    {
		push @values, IkiWiki::titlepage($v);
	    }
	    $value = \@values;
	}
	elsif (!ref $value)
	{
	    $value = IkiWiki::basename($value);
	}
    }
    elsif ($config{field_allow_config}
	and $field_name =~ /^config-(.*)/)
    {
	my $key = $1;
	if (exists $config{$key}
		and defined $config{$key})
	{
	    $value = $config{$key};
	}
    }

    return $value;
} # calculated_values

sub field_is_null ($$) {
    my $page=shift;
    my $field_name=shift;

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $page);

    # testing if the value is null, undefined etc.
    if (defined $val and $val) {
	return IkiWiki::FailReason->new("$field_name of $page is not null");
    }
    else {
	return IkiWiki::SuccessReason->new("$field_name of $page is null");
    }
} # field_is_null

my %match_a_field_globs = ();

# match field funcs
# page-to-check, wanted
sub match_a_field ($$) {
    my $page=shift;
    my $wanted=shift;

    # The field name is first; the rest is the match
    my ($field_name, $glob) = split(/\s+/, $wanted, 2);
    if (!$field_name || !$glob)
    {
	return IkiWiki::FailReason->new("cannot match field");
    }

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $page);
    if (!defined $val)
    {
	return IkiWiki::FailReason->new("$page does not have a $field_name", "" => 1);
    }

    if ($val eq $glob) # quick test for equality
    {
	return IkiWiki::SuccessReason->new("$glob equals $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
    }

    # turn glob into a safe regexp
    if (!exists $match_a_field_globs{$glob})
    {
	my $re=IkiWiki::glob2re($glob);
	$match_a_field_globs{$glob} = qr/^$re$/i;
    }
    my $regexp = $match_a_field_globs{$glob};

    if ($val=~$regexp) {
	return IkiWiki::SuccessReason->new("$regexp matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
    }
    else {
	return IkiWiki::FailReason->new("$regexp does not match $field_name of $page", "" => 1);
    }
} # match_a_field

my %match_a_field_item_globs = ();

# check against individual items of a field
# (treat the field as an array)
# page-to-check, wanted
sub match_a_field_item ($$) {
    my $page=shift;
    my $wanted=shift;

    # The field name is first; the rest is the match
    my ($field_name, $glob) = split(/\s+/, $wanted, 2);
    if (!$field_name || !$glob)
    {
	return IkiWiki::FailReason->new("cannot match field");
    }
    $field_name =~ tr/A-Z/a-z/;

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $page);
    if (!defined $val)
    {
	return IkiWiki::FailReason->new("$page does not have a $field_name", "" => 1);
    }

    if ($val eq $glob) # quick test for equality
    {
	return IkiWiki::SuccessReason->new("$glob equals $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
    }

    # turn glob into a safe regexp
    if (!exists $match_a_field_globs{$glob})
    {
	my $re=IkiWiki::glob2re($glob);
	$match_a_field_globs{$glob} = qr/^$re$/i;
    }
    my $regexp = $match_a_field_globs{$glob};

    if (ref $val) # value is not a scalar
    {
	for (my $i = 0; $i < @{$val}; $i++)
	{
	    my $itemval = ${val}->[$i];
	    if ($itemval=~$regexp) {
		return IkiWiki::SuccessReason->new("$regexp matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
	    }
	}
	# not found
	return IkiWiki::FailReason->new("$regexp does not match $field_name of $page", "" => 1);
    }
    else
    {
	if ($val=~$regexp) {
	    return IkiWiki::SuccessReason->new("$regexp matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
	}
	else {
	    return IkiWiki::FailReason->new("$regexp does not match $field_name of $page", "" => 1);
	}
    }

} # match_a_field_item

# ===============================================
# PageSpec functions
# ---------------------------

package IkiWiki::PageSpec;

sub match_field ($$;@) {
    my $page=shift;
    my $wanted=shift;
    return IkiWiki::Plugin::field::match_a_field($page, $wanted);
} # match_field

sub match_destfield ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};

    # Match the field on the destination page, not the source page
    return IkiWiki::Plugin::field::match_a_field($params{destpage}, $wanted);
} # match_destfield

sub match_field_item ($$;@) {
    my $page=shift;
    my $wanted=shift;
    return IkiWiki::Plugin::field::match_a_field_item($page, $wanted);
} # match_field

sub match_destfield_item ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};

    # Match the field on the destination page, not the source page
    return IkiWiki::Plugin::field::match_a_field_item($params{destpage}, $wanted);
} # match_destfield

sub match_field_null ($$;@) {
    my $page=shift;
    my $wanted=shift;
    return IkiWiki::Plugin::field::field_is_null($page, $wanted);
} # match_field_null

sub match_field_tagged ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    # The field name is first; the rest is the match
    my ($field_name, $glob) = split(/\s+/, $wanted, 2);
    if (!$field_name || !$glob)
    {
	return IkiWiki::FailReason->new("cannot match field");
    }
    $field_name =~ tr/A-Z/a-z/;
    return match_link($page, $glob, linktype => $field_name, @_);
}

# ===============================================
# SortSpec functions
# ---------------------------
package IkiWiki::SortSpec;

sub cmp_field {
    my $field = shift;
    error(gettext("sort=field requires a parameter")) unless defined $field;

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = "" unless defined $left;
    $right = "" unless defined $right;
    $left = join(' ', @{$left}) if ref $left eq 'ARRAY';
    $right = join(' ', @{$right}) if ref $right eq 'ARRAY';
    return $left cmp $right;
}

sub cmp_field_natural {
    my $field = shift;
    error(gettext("sort=field_natural requires a parameter")) unless defined $field;

    eval {use Sort::Naturally};
    error $@ if $@;

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = "" unless defined $left;
    $right = "" unless defined $right;
    $left = join(' ', @{$left}) if ref $left eq 'ARRAY';
    $right = join(' ', @{$right}) if ref $right eq 'ARRAY';
    return Sort::Naturally::ncmp($left, $right);
}

sub cmp_field_number {
    my $field = shift;
    error(gettext("sort=field_number requires a parameter")) unless defined $field;

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = 0 unless defined $left;
    $right = 0 unless defined $right;

    $left = 0 if ref $left eq 'ARRAY';
    $right = 0 if ref $right eq 'ARRAY';
    # Multiply by a hundred to deal with floating-point problems
    $left = $left * 100;
    $right = $right * 100;
    return $left <=> $right;
}

1;
