#!/usr/bin/perl
## This program is free software; you can redistribute it
## and/or modify it under the same terms as Perl itself.
## Please see the Perl Artistic License.
## 
## Copyright (C) 2004-2011 Megan Squire <msquire@elon.edu>
##
## We're working on this at http://flossmole.org - Come help us build 
## an open and accessible repository for data and analyses for open
## source projects.
##
## If you use this code for preparing an academic paper please
## provide a citation to 
##
## FLOSSmole (2004-2011) FLOSSmole: a project to provide academic access to data 
## and analyses of open source projects.  Available at http://flossmole.org 
################################################################
#
# scrapeRF.pl <filename> <datasource_id> <DEBUG mode>
#
# reads through the Rubyforge project RDF file and seeds database
# YOU MUST change the datasource_id below before running this file
# This script will add the following to the database:
#
# proj_unixname, long_name, url, description
#
# The rest of the data has to be scraped from the project home page on RF!
#
# dbInfo.txt should include your database connection info,
# Including username, password, and dsn in the following format:
# dsn [in the format: DBI:mysql:database_name:database_url]
# username
# password
#
# example:
#
# DBI:mysql:ossmole:mydbserver.mydomain.com
# coolgirl123
# topsecret
#
# use the $DEBUG setting to print verbose status messages
################################################################

use strict;
use XML::Parser;
use DBI;

my $file = shift @ARGV;
my $datasource_id = shift @ARGV;
my $DEBUG = shift @ARGV;
my $DBFILE;

if (($file eq undef) || ($file eq ""))
{
    print "ERROR: No file on commandline.\n";
    exit;
}

elsif (($datasource_id eq undef) || ($datasource_id == 0) || ($datasource_id eq ""))
{
    print "ERROR: No datasource ID.\n";
    exit;
}

elsif (($DEBUG eq undef) || ($DEBUG eq ""))
{
	print "ERROR: No debug status.\n";
    exit;
}

if ($DEBUG eq "DEBUG")
{
	$DBFILE = "dbInfoTest.txt";
}
else
{
	$DBFILE = "dbInfo.txt";
}
	
open (INPUT, $DBFILE);
my @dbinfo = <INPUT>;
close (INPUT);

my $dsn = $dbinfo[0];
my $username = $dbinfo[1];
my $password = $dbinfo[2];
chomp($dsn);
chomp($username);
chomp($password);

my $dbh = DBI->connect($dsn, $username, $password, {RaiseError=>1});
my $parser = XML::Parser->new(Handlers => {
	Init  => \&handle_doc_start,
	Final => \&handle_doc_end,
	Start => \&handle_elem_start,
	End   => \&handle_elem_end,
	Char  => \&handle_char_data,});
	
my $record;
my $context;
my %records;

if ($file)
{
	$parser->parsefile($file);
}
else
{
	my $input = "";
	while (<STDIN>) {$input .= $_;}
	$parser->parse($input);
}
exit;

sub handle_doc_start
{
    print "doc_start\n";
}

sub handle_doc_end
{
    print "doc_end\n";
}

sub handle_elem_start
{
    my ($expat, $name, %atts) = @_;
    $context = $name;
    if ($name eq 'item')
    {
        $record  = {};
    }
}

sub handle_elem_end
{
    my ($expat, $name) = @_;
    if ($name eq 'item')
    {
        # here are some basic variables for the rf_projects table
        my $proj_long_name = $record->{'title'};
        my $url            = $record->{'link'};
        
        # strip out the proj_unixname from the URL
        $url =~ m{http://rubyforge.org/projects/(.*?)/};
        my $proj_unixname = $1;
                        
        #save this description for use in the rf_project_description table
        my $description    = $record->{'description'};
        
        print "\n\nworking on: $proj_unixname\n";
        print "    proj_long_name: $proj_long_name";
        print "    url: $url";
        print "    description:" . substr($description, 0, 10);
        
        if ($DEBUG ne "DEBUG")
        {
            print ("inserting into production database: rf_projects");
        	my $sth = $dbh->prepare(qq{INSERT IGNORE INTO rf_projects (
                                    proj_unixname, 
                                    datasource_id, 
                                    proj_long_name,
                                    url, 
                                    date_collected) 
                                   VALUES(?,?,?,?,NOW())});
            $sth->execute($proj_unixname, $datasource_id, $proj_long_name, $url) 
            or die ($dbh->errstr);
            
            # insert the project descriptions
            print ("inserting into production database: rf_project_description");
            $sth = $dbh->prepare(qq{INSERT IGNORE INTO rf_project_description (
                                    proj_unixname, 
                                    datasource_id, 
                                    description,
                                    date_collected) 
                                   VALUES(?,?,?,NOW())});
            $sth->execute($proj_unixname, $datasource_id, $description) 
            or die ($dbh->errstr);
        }
    }
}

sub handle_char_data
{
    #print "char_data\n";
    my ($expat, $text) = @_;
    $text =~ s/&/&/g;
    $text =~ s/</&lt;/g;
    
    $record->{$context} .= $text;
}
