#!/usr/bin/perl
# Javascript Search of Fields
# which applies search to pages matching a PageSpec.
# Note that Javascript scrubbing MUST be turned off for the given page.
package IkiWiki::Plugin::jssearchfield;

use warnings;
use strict;
use IkiWiki 3.00;
use Data::Handle;
use Text::NeatTemplate;

sub import {
	hook(type => "getsetup", id => "jssearchfield", call => \&getsetup);
	hook(type => "preprocess", id => "jssearchfield", call => \&preprocess);
	hook(type => "format", id => "jssearchfield", call => \&format);
        IkiWiki::loadplugin("field");
}

# ------------------------------------------------------------
# Globals
# ----------------------------

my %PagesJS = ();

# ------------------------------------------------------------
# Hooks
# ----------------------------

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "search",
		},
}

sub preprocess (@) {
    my %params=@_;

    if ($params{page} eq $params{destpage}) {
	return set_up_search(%params);
    }
    else {
	# disable in inlined pages
	return "";
    }
}

sub format (@) {
    my %params=@_;
    my $content=$params{content};
    my $page=$params{page};

    # don't add the javascript if there isn't any
    if (!exists $PagesJS{$page}
        or !$PagesJS{$page})
    {
	return $content;
    }
    # if there is no </head> tag then we're probably in preview mode
    if (index($content, '</head>') < 0)
    {
	return $content;
    }

    my $scripting = $PagesJS{$page};

    # add the CSS and Javascript at the end of the head section
    $content=~s!(</head>)!${scripting}$1!s;

    return $content;
} # format

# ------------------------------------------------------------
# Private Functions
# ----------------------------
sub set_up_search {
    my %params=@_;
    my $page=$params{page};

    my $pages=$params{pages};
    my $fields=$params{fields};

    my @matching_pages = pagespec_match_list($params{destpage},
	$pages,
	%params);

    if (@matching_pages == 0)
    {
	return '';
    }

    my @fields = split(' ', $fields);
    my @tagfields = ($params{tagfields}
	? split(' ', $params{tagfields})
	: ());
    my @sortfields = ($params{sortfields}
	? split(' ', $params{sortfields})
	: ());
    my %is_tagfield = ();
    my %is_numeric_tagfield = ();
    foreach my $tag (@tagfields)
    {
	$is_tagfield{$tag} = 1;
	$is_numeric_tagfield{$tag} = 0;
    }

    # The Javascript.
    # Note that we are creating all the Javascript inline,
    # because the code depends on which fields are being queried.
    # And also because it's simpler not to have to have an extra file.
    # The template for the javascript is in the __DATA__ handle
    # at the end of this file.

    my %tvars = ();

    $tvars{formid} = ($params{formid} ? $params{formid} : 'jssearchfield');

    $tvars{fields_as_html} = '';
    $tvars{fields_match} = '';
    foreach my $fn (@fields)
    {
	if ($fn ne 'url' and $fn ne 'title')
	{
            my $label = "<span class='label'>$fn: </span>";
	    $tvars{fields_as_html} .=<<EOT;
	if (typeof this.$fn != 'undefined' && this.$fn != 'NONE')
	{
	    out = out + "<$result_tag class=\\"result-$fn\\">$label<span class='value'>";
	    if (\$.isArray(this.$fn))
	    {
		for (var x = 0; x < this.$fn.length; x++)
		{
		    if (x + 1 < this.$fn.length)
		    {
			out = out + this.$fn\[x] + ", ";
		    }
		    else
		    {
			out = out + this.$fn\[x];
		    }
		}
	    }
	    else
	    {
		out = out + this.$fn;
	    }
	    out = out + "</span></$result_tag>\\n";
	}
EOT
	}
	my $match_fn = ($is_tagfield{$fn}
	    ? "field_equals"
	    : "field_does_match");
	$tvars{fields_match} .=<<EOT;
	if (typeof query["$fn"] != 'undefined')
	{
		// For every search term we are working with
		for (var t = 0; t < query["$fn"].length; t++) {
		    matches_this_term = false;
		    var q = query["$fn"][t];
		    if (searchDB[sDB].$match_fn("$fn",q)) {
			matches_this_term = true;
		    }
		    if (!matches_this_term)
		    {
			matches_all_terms = false;
		    }
		}
	}
EOT
    }

    # the array of records
    my $count = 0;
    $tvars{records} = '';
    my %tagsets = ();
    for (my $i = 0; $i < @matching_pages; $i++)
    {
	my $pn = $matching_pages[$i];
	$tvars{records} .=<<EOT;
searchDB[$i] = new searchRec({
EOT
	my $title = IkiWiki::Plugin::field::field_get_value('title', $pn);
	my $url = htmllink($params{page}, $params{destpage}, $pn, linktext=>$title);
	$url =~ s/"/'/g; # use single quotes so as not to mess up the double quotes
	$tvars{records} .= 'url:"'.$url.'",';
	foreach my $fn (@fields)
	{
	    $tagsets{$fn} = {} if ($is_tagfield{$fn} and !exists $tagsets{$fn});
	    my $val = IkiWiki::Plugin::field::field_get_value($fn, $pn);
            my @val_array = ();
	    if (ref $val eq 'ARRAY')
	    {
		@val_array = @{$val};
	    }
	    elsif ($val and $is_tagfield{$fn} and $val =~ /[,\/]/)
	    {
		@val_array = split(/[,\/]\s*/, $val);
	    }
	    elsif ($val)
	    {
                push @val_array, $val;
	    }
	    else # value is null
	    {
		$val = "NONE";
                push @val_array, $val;
	    }
            if (@val_array >= 1)
            {
                my @vals = ();
		foreach my $v (@val_array)
		{
		    $v =~ tr{"}{'};
                    if ($v =~ /^[\.\d]+$/)
                    {
                        push @vals, $v;
                        if ($is_tagfield{$fn})
                        {
                            $is_numeric_tagfield{$fn} = 1;
                        }
                    }
                    else
                    {
		        push @vals, '"'.$v.'"';
                        if ($is_tagfield{$fn} and $v ne 'NONE')
                        {
                            $is_numeric_tagfield{$fn} = 0;
                        }
                    }
		    if ($is_tagfield{$fn})
		    {
                        if (!exists $tagsets{$fn}{$v})
                        {
                            $tagsets{$fn}{$v} = 0;
                            $tagsets{$fn}{"!$v"} = $total;
                        }
			$tagsets{$fn}{$v}++;
			$tagsets{$fn}{"!$v"}--;
		    }
		}
                if (@vals > 1)
                {
                    $tvars{records} .= $fn.':['.join(',', @vals).'],';
                }
                else
                {
                    $tvars{records} .= $fn.':'.$vals[0].',';
                }
            }
	}
	$tvars{records} .= "});\n";
        $count++;
    } # for matching_pages

    # and the tagsets
    $tvars{tagsets} = '';
    if (@tagfields > 0)
    {
	$tvars{tagsets} .=<<EOT;
tagFields = new Array();
EOT
	my $ind = 0;
	foreach my $fn (@tagfields)
	{
	    $tvars{tagsets} .=<<EOT;
tagFields[$ind] = "$fn";
EOT
	    $ind++;
	}
    }

    # The search form
    $tvars{search_fields} = '';
    foreach my $fn (@fields)
    {
	$tvars{search_fields} .= "<tr><td class='label'>$fn:</td><td class='q-$fn'>";
	if ($is_tagfield{$fn})
	{
	    my $null_tag = delete $tagsets{$fn}{"NONE"}; # show nulls separately
	    my $not_null_tag = delete $tagsets{$fn}{"!NONE"};
	    my @tagvals = keys %{$tagsets{$fn}};
            @tagvals = grep {! /^!/} @tagvals;
            if ($is_numeric_tagfield{$fn})
            {
	        @tagvals = sort { $a <=> $b } @tagvals;
            }
            else
            {
	        @tagvals = sort @tagvals;
            }
	    my $num_tagvals = int @tagvals;

	    $search_fields .=<<EOT;
<div class="tagcoll"><span class="toggle"><span class="togglearrow">&#9654;</span>
<span class="count">(tags: $num_tagvals)</span></span>
<div class="taglists">
<ul class="taglist">
EOT
            # first do the positives
	    foreach my $tag (@tagvals)
	    {
		$search_fields .=<<EOT;
<li><input name="$fn" type='checkbox' value="$tag" />
<label for="$fn">$tag ($tagsets{$fn}{$tag})</label></li>
EOT
	    }
	    if ($null_tag)
	    {
		$search_fields .=<<EOT;
<li><input name="$fn" type='checkbox' value="NONE" />
<label for="$fn">NONE ($null_tag)</label></li>
EOT
	    }

            # next do the negatives
	    $search_fields .=<<EOT;
</ul>
<ul class="taglist taglist2">
EOT
	    foreach my $tag (@tagvals)
	    {
		$search_fields .=<<EOT;
<li><input name="$fn" type='checkbox' value="!$tag" />
<label for="$fn">!$tag ($tagsets{$fn}{"!$tag"})</label></li>
EOT
	    }
	    if ($not_null_tag)
	    {
		$search_fields .=<<EOT;
<li><input name="$fn" type='checkbox' value="!NONE" />
<label for="$fn">!NONE ($not_null_tag)</label></li>
EOT
	    }
	    $search_fields .= "</ul></div></div>\n";
	}
	else
	{
	    $tvars{search_fields} .=<<EOT
<input type="text" name="$fn" size="60"/>
EOT
	}
	$tvars{search_fields} .= "</td></tr>\n";
    }

    # The sort form
    my $sort_fields = '';
    foreach my $fn (@sortfields)
    {
        $sort_fields .=<<EOT;
<input name="sort" type="radio" value="$fn"/><label for="sort">$fn</label>
EOT
    }

    my $handle = Data::Handle->new( __PACKAGE__ );
    my $t = HTML::Template->new(filehandle => $handle);
    $t->param(%tvars);
    my $js = $t->output();
    $PagesJS{$master_page} = $js;

    # restrict the output to the actual search field
    # as the javascript above is going into the <head> section
    my $out =<<EOT;
<p>Search through ${total} records.</p>
<form id="$tvars{formid}" name="search" action="" method="get">
<table>
${search_fields}
</table>
<span class="label">Sort:</span>
<input name="sort" type="radio" value="default" checked="yes"/><label for="sort">default</label>
<input name="sort" type="radio" value="random"/><label for="sort">random</label>
${sort_fields}
<input type="submit" value="Search!" name="search" />
<input type="reset" value="Reset" name="reset" />
</form>
<div id="message"></div>

<script type='text/javascript'>
<!--
initForm();
//-->
</script>
EOT
    return $out;
} # set_up_search

1;

__DATA__
<script type='text/javascript'>
<!--
// Error strings
ERR_NoSearchTerms	= "You didn't enter any terms to search for, please enter some terms to search for and try again.";
ERR_NoResults		= "Your search found no results.";

debug = function (log_txt) {
    if (window.console != undefined) {
        console.log(log_txt);
    }
}

// To sort an array in random order
Array.prototype.shuffle = function() {
var s = [];
while (this.length) s.push(this.splice(Math.random() * this.length, 1));
while (s.length) this.push(s.pop());
return this;
}

// sort by a field name
function sortResults(results,fn) {
    results.sort(function(a,b){
        return (fieldCompare(searchDB[a][fn], searchDB[b][fn]));
    });
    return results;
}

// Comparison function returns -1, 0 or 1
// With Null values at the end (high)
function fieldCompare(valueA,valueB) {
    if (typeof valueB == 'undefined'
	|| valueB.length == 0)
    {
        if (typeof valueA == 'undefined'
            || valueA.length == 0)
        {
            return 0; // nulls equal each other
        }
        else
        {
            return -1;
        }
    }
    else if (typeof valueA == 'undefined'
        || valueA.length == 0)
    {
	return 1;
    }

    var aVal = valueA;
    var bVal = valueB;
    if (typeof valueA == 'object')
    {
        aVal = '';
        for (var x = 0; x < valueA.length; x++) {
            aVal = aVal + valueA[x];
        };
    }
    if (typeof valueB == 'object')
    {
        bVal = '';
        for (var x = 0; x < valueB.length; x++) {
            bVal = bVal + valueB[x];
        };
    }
    if (typeof aVal == 'number' && typeof bVal == 'number')
    {
        return (aVal - bVal);
    }
    else
    {
        return ((aVal < bVal) ? -1 : ((aVal > bVal) ? 1 : 0));
    }
}

// Constructor for each search engine item.
// Used to create a record in the searchable "database"
function searchRec(ob) {
    for (x in ob)
    {
	this[x] = ob[x];
    }
    return this;
}

// See if the given value equals the value of the field
// If the field's value is an array, this will return true
// if ANY item of that array equals the given value
searchRec.prototype.field_equals = function(fn,val) {
    if (typeof val == 'undefined'
	|| val.length == 0)
    {
	return false;
    }
    else if (typeof this[fn] == 'undefined')
    {
	return false;
    }

    // starts with ! means NOT match
    var neg = val.indexOf('!'); 
    if (neg == 0)
    {
	var negval = val.substring(neg+1);
        return !this.field_equals(fn,negval);
    }
    else
    {
        if (typeof this[fn] == 'object')
        {
            for (var x = 0; x < this[fn].length; x++) {
                if (this[fn][x] == val)
                {
                    return true;
                }
            };
            return false;
        }
        else if (this[fn] == val)
        {
            return true;
        }
    }
    return false;
}

searchRec.prototype.field_cmp = function(fn,val,lessthan) {
    if (typeof val == 'undefined'
	|| val.length == 0)
    {
	return false;
    }
    else if (typeof this[fn] == 'undefined')
    {
	return false;
    }

    // starts with ! means NOT match
    var neg = val.indexOf('!'); 
    // starts with = means "or equals"
    if (neg == 0)
    {
	var negval = val.substring(neg+1);
        return !this.field_cmp(fn,negval,lessthan);
    }
    else
    {
        var eq = val.indexOf('=');
        var orequals = (eq == 0);
	var eqval = val.substring(eq+1);

        if (typeof this[fn] == 'object')
        {
            for (var x = 0; x < this[fn].length; x++) {
                if ((lessthan && orequals && this[fn][x] <= eqval)
                    || (lessthan && !orequals && this[fn][x] < val)
                    || (!lessthan && orequals && this[fn][x] >= eqval)
                    || (!lessthan && !orequals && this[fn][x] > val))
                {
                    return true;
                }
            };
            return false;
        }
        else if ((lessthan && orequals && this[fn] <= eqval)
                 || (lessthan && !orequals && this[fn] < val)
                 || (!lessthan && orequals && this[fn] >= eqval)
                 || (!lessthan && !orequals && this[fn] > val))
        {
            return true;
        }
    }
    return false;
}

// See if the given regex matches the value of the field
// If the field's value is an array, this will return true
// if ANY item of that array matches the given regex
searchRec.prototype.field_matches = function(fn,regex) {
    if (typeof regex == 'undefined'
	|| regex.length == 0)
    {
	return false;
    }
    else if (typeof this[fn] == 'undefined')
    {
	return false;
    }
    else if (typeof this[fn] == 'object')
    {
	for (var x = 0; x < this[fn].length; x++) {
	    if (this[fn][x].match(regex))
	    {
		return true;
	    }
	};
	return false;
    }
    else if (this[fn].match(regex))
    {
	return true;
    }
    return false;
}

// Check the value to see if it needs to be a regex
// and call equals or matches accordingly
searchRec.prototype.field_does_match = function(fn,qval) {
    if (typeof qval == 'undefined' || qval.length == 0)
    {
	return false;
    }
    // starts with ! means NOT match
    var neg = qval.indexOf('!'); 
    if (neg == 0)
    {
	var negval = qval.substring(neg+1);
        return !this.field_does_match(fn,negval);
    }
    else
    {
        var pos = qval.indexOf('='); 
        if (pos == 0) // starts with equals
        {
            var eqval = qval.substring(pos+1);
            return this.field_equals(fn,eqval);
        }
        else
        {
            pos = qval.indexOf('<'); 
            if (pos == 0) // starts with lessthan
            {
                var cmpval = qval.substring(pos+1);
                return this.field_cmp(fn,cmpval,true);
            }
            else
            {
                pos = qval.indexOf('>'); 
                if (pos == 0) // starts with lessthan
                {
                    var cmpval = qval.substring(pos+1);
                    return this.field_cmp(fn,cmpval,false);
                }
                else
                {
                    var regex = new RegExp(qval,"i");
                    return this.field_matches(fn,regex);
                }
            }
        }
    }
    return false;
}

// Format the search rec as a HTML string
searchRec.prototype.as_html = function() {
	var out = "<li class=\"result\"><span class=\"result-url\">" + this.url + "</span>\n";
<TMPL_VAR FIELDS_AS_HTML>
    out = out + "</li>\n";

    return out;
}

// Grabs all the desired query values from the form
// and constructs a query object
function queryRec(formid) {

	var myform = document.getElementById(formid);

	// Go through all the elements of the form
	var found = false;
	for (var i = 0; i < myform.elements.length; i++)
	{
	    var elem = myform.elements[i];
	    if (elem.type == 'text' || elem.type == 'textarea')
	    {
		// split text values on spaces
		if (typeof elem.value != 'undefined'
		    && elem.value.length > 0)
		{
		    this[elem.name] = elem.value.split(" ");
		    found = true;
		}
	    }
	    else if (elem.type == 'checkbox')
	    {
		if (elem.checked)
		{
		    if (typeof this[elem.name] == 'undefined')
		    {
			this[elem.name] = [elem.value];
		    }
		    else
		    {
			this[elem.name][this[elem.name].length] = elem.value;
		    }
		    found = true;
		}
	    }
	    else if (elem.type == 'radio')
	    {
		if (elem.checked)
		{
		    // radio buttons only have one value
		    this[elem.name] = [elem.value];

		    // the "sort" field is not a search term!
		    if (elem.name != 'sort')
		    {
			found = true;
		    }
		}
	    } // form element types
	} // form elements

	this["_terms"] = found;
	return this;
}

queryRec.prototype.as_html = function() {
	var out = "";
	for (x in this)
	{
	    if (x != "search"
		&& x != "_terms"
		&& typeof this[x] != "function"
		&& typeof this[x] != "undefined")
	    {
		var qv = "";
		for (var i = 0; i < this[x].length; i++)
		{
		    if (this[x][i].length > 0)
		    {
			qv = qv + this[x][i] + " ";
		    }
		}
		if (qv.length > 0)
		{
		    out = out + x + "=<b>" + qv + "</b> ";
		}
	    }
	}
    return out;
}

queryRec.prototype.dump = function() {
	var out = "";
	for (x in this)
	{
	    if (typeof this[x] != "function"
		&& typeof this[x] != "undefined")
	    {
		    out = out + x + ":" + this[x] + "\n";
	    }
	}
    return out;
}

// Code from http://www.optimalworks.net/blog/2007/web-development/javascript/array-detection
function is_array(array) { return !( !array || (!array.length || array.length == 0) || typeof array !== 'object' || !array.constructor || array.nodeType || array.item ); }

function doSearch (query) {

    // This is where we will be putting the results.
    results = new Array();

    if (!query["_terms"]) {
	// return EVERYTHING
	for (i=0;i < searchDB.length;i++)
	{
	    results[i] = i;
	}
	return results;
    }

    // Loop through the db for potential results
    // For every entry in the "database"
    for (sDB = 0; sDB < searchDB.length; sDB++) {
	    matches_all_terms = true; //matches until it does not
<TMPL_VAR FIELDS_MATCH>
	    if (matches_all_terms)
	    {
		results[results.length] = String(sDB);
	    }
    }
	if (results.length > 0) {
	    if (query['sort'] == 'random')
	    {
		results.shuffle();
	    }
            else if (query['sort'] == 'default')
            {
                // no sort
            }
            else if (query['sort'].length > 0)
            {
                results = sortResults(results,query['sort']);
            }
	    return results;
	}
	else {
		return ERR_NoResults;
	}
}

function writeMessage(message) {
    var writeon = document.getElementById('message');
    writeon.innerHTML = message;
}

function query_from_form() {
    var query = new queryRec("<TMPL_VAR FORMID>");
    var results = doSearch(query);
    if (results) {
        formatResults(query,results);
    }
    return false;
}

function filterTaglist(fn,results,query) {
    tagset = new Object();
    var tcount = 0;
    for (ri=0;ri < results.length;ri++)
    {
	val = searchDB[results[ri]][fn];
	if (is_array(val))
	{
	    for (j=0;j < val.length;j++)
	    {
		vv = val[j];
		if (typeof tagset[vv] == 'undefined')
		{
		    tagset[vv] = 1;
		    tcount++;
                    tagset["!"+vv] = (results.length - 1);
		}
		else
		{
		    tagset[vv]++;
                    tagset["!"+vv]--;
		}
	    }
	}
	else
	{
	    if (typeof tagset[val] == 'undefined')
	    {
		tagset[val] = 1;
		tcount++;
                tagset["!"+val] = (results.length - 1);
	    }
	    else
	    {
		tagset[val]++;
		tagset["!"+val]--;
	    }
	}
    }
    // need to include the query field if a value was negative
    if (typeof query[fn] != 'undefined')
    {
        val = query[fn];
	if (is_array(val))
	{
	    for (j=0;j < val.length;j++)
	    {
		vv = val[j];
                var neg = vv.indexOf('!'); 
                if (neg == 0)
                {
                    var negval = vv.substring(neg+1);
                    if (typeof tagset[negval] == 'undefined')
                    {
                        tagset[negval] = 0;
                        tcount++;
                        tagset["!"+negval] = (results.length);
                    }
                }
	    }
	}
	else
	{
            var neg = val.indexOf('!'); 
            if (neg == 0)
            {
                var negval = val.substring(neg+1);
                if (typeof tagset[negval] == 'undefined')
                {
                    tagset[negval] = 0;
                    tcount++;
                    tagset["!"+negval] = (results.length);
                }
	    }
	}
    }
    tcol = $("#<TMPL_VAR FORMID> .q-"+fn+" .tagcoll .taglists li");
    tcol.each(function(index){
	check = $(this).find("input");
	label = $(this).find("label");
	checkval = check.attr("value");
	if (typeof tagset[checkval] == 'undefined')
	{
	    $(this).hide();
	}
	else
	{
	    $(this).show();
	    label.html(checkval+" ("+tagset[checkval]+")");
	}
    });
    tc_total = $("#<TMPL_VAR FORMID> .q-"+fn+" .count");
    tc_total.html("(tags: "+tcount+")");
}

function initForm() {
    $("#<TMPL_VAR FORMID> .tagcoll .taglists").hide();
    $("#<TMPL_VAR FORMID> .tagcoll .toggle").click(function(){
	var tl = $(this).siblings(".taglists");
        var lab = $(this).children(".togglearrow");
	if (tl.is(":hidden")) {
	    lab[0].innerHTML = "&#9660;"
	    tl.show();
	} else {
	    lab[0].innerHTML = "&#9654;"
	    tl.hide();
	}
    });
    $("#<TMPL_VAR FORMID> input").change(function(){
	var query = new queryRec("<TMPL_VAR FORMID>");
	var results = doSearch(query);
	if (results) {
	    formatResults(query,results);
	}
	for (i=0;i<tagFields.length;i++)
	{
	    filterTaglist(tagFields[i],results,query);
	}
    });
    var search_form = document.getElementById('<TMPL_VAR FORMID>');
    search_form.setAttribute("onsubmit", 'return query_from_form()');
    writeMessage("Ready to search!")
}

function formatResults(query,results) {
	// Loop through them and make it pretty! :)
	var the_message = "";
	var qhtml = query.as_html();
	if (qhtml.length > 0)
	{
	    the_message = the_message + "<p>Searched for " + qhtml + "</p>";
	}
	if (is_array(results)) {
		the_message = the_message + "<p>Found " + results.length + " results.</p>";
	
		the_message = the_message + "<ol>";
		for (r = 0; r < results.length; r++) {
			result = searchDB[results[r]];
			
			the_message = the_message + result.as_html();
		}
		the_message = the_message + "</ol>";
	}
	// If it is not an array, then we got an error message, so display that
	// rather than results
	else {
		the_message = the_message + "<i>" + results + "</i>";
		the_message = the_message + "<br />";
	}
	the_message = the_message + "<br/>\n<a href=\"#<TMPL_VAR FORMID>\">&raquo; Back to search form</a>\n";
    writeMessage(the_message);
}

// the array of records
searchDB = new Array();
<TMPL_VAR RECORDS>

<TMPL_IF TAGSETS>
<TMPL_VAR TAGSETS>
</TMPL_IF>
//-->
</script>
