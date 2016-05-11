#!/usr/bin/perl
# Latexml and latex plugin
# based on the WikiText plugin.
# Written by Josef Urban, modified by Joe Corneli
package IkiWiki::Plugin::tex;

use warnings;
use strict;
use Encode;
use IkiWiki 3.00;
use File::Temp qw/ :mktemp  /;
use File::Basename;

sub import {
	hook(type => "getsetup", id => "tex", call => \&getsetup);
	hook(type => "htmlize", id => "tex", call => \&htmlize);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
}

sub htmlize (@) {
	my %params=@_;
	my($pname, $directories, $suffix) = fileparse($params{page});
	my $content = $params{content};

	return latexml($pname, $directories, $content);
}

# Run latexml on $content, giving the file name $pname.tex, return the html
# Can create temp dir in /tmp, which should be removed at some point (after debuging).
sub latexml {
    my ($pname, $directories, $content) = @_;
    my $ProblemFile = $pname . '.tex';
    my $result = "";

    # set to 0 for doing things in $config{srcdir} (preferred),
    # set to 1 for doing things in /tmp
    my $DoTmp = 0;

    # set to 0 if no XML (eg only latexmlpost);
    # useful for initial populating of the wiki (provided the .xml files exist)
    my $DoXML = 1;

    # latexml;
    my $latexml =  ($DoXML == 0)? "true": "/usr/local/bin/latexml";

    # latexmlpost binary
    my $latexmlpost = "/usr/local/bin/latexmlpost";

    my $latexmlc = "/usr/bin/latexmlc";

    if($DoTmp == 1)
    {
	my $TemporaryProblemDirectory = mkdtemp("/tmp/latexml_XXXX");

	system("chmod 0777 $TemporaryProblemDirectory");

	open(PFH, ">$TemporaryProblemDirectory/$ProblemFile") or die "$ProblemFile not writable";
	printf(PFH "%s",$content);
	close(PFH);

	$result = `cd $TemporaryProblemDirectory; $latexml $ProblemFile --destination=$ProblemFile.xml; $latexmlpost $ProblemFile.xml --destination=$ProblemFile.xhtml; cat $ProblemFile.xhtml`;

        debug("result:- $result");
    }
    else
    {
	open(PFH, ">$config{srcdir}/$directories$ProblemFile") or die "$ProblemFile not writable";
	printf(PFH "%s",$content);
	close(PFH);
	
	$result = decode_utf8(`cd $config{srcdir}/$directories; $latexmlc --post --local $ProblemFile`);

        debug("result-: $result");

#	$result = `cd $config{srcdir}/$directories; $latexml $ProblemFile --destination=$ProblemFile.xml; $latexmlpost $ProblemFile.xml --destination=$ProblemFile.xhtml; cat $ProblemFile.xhtml`;
    }

#    $result =~ s/\"[a-zA-Z0-9_-]+\.html\#/\"\#/g;

#    system("rm -rf $TemporaryProblemDirectory");

#    return '<link href="'. $config{url} . '/coqdoc.css" rel="stylesheet" type="text/css"/>' . "\n". $result;
    return $result;
}

1
