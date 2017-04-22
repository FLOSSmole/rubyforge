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
# parseHtmlRF.pl <datasource_id>
#
# pulls the Rubyforge (RF) html from the database and parses it for the 
# database environment(s), programming language, license, intended audience, etc
# then writes that to the database
#
#
# dbInfo.pl should include your database connection info,
# Including username, password, and dsn in the following format:
# my $dsn = "DBI:mysql:database_name:database_url";
# my $username = "username_goes_here";
# my $password = "password_goes_here";
#
################################################################

use strict;
use LWP::Simple;
use DBI;

my $datasource_id = shift @ARGV;
my $DEBUG = 0;
my $DBFILE = "dbInfo.txt";
open (INPUT, $DBFILE);
my @dbinfo = <INPUT>;
close (INPUT);

my $dsn      = $dbinfo[0];
my $username = $dbinfo[1];
my $password = $dbinfo[2];
chomp($dsn);
chomp($username);
chomp($password);

my $dbh = DBI->connect($dsn, $username, $password, {RaiseError=>1});

if ($DEBUG)
{
    # set up unixname here
    # (for debug, use a random test project)  
    my $unixname = "wee";
    print "\n\nDEBUG: working on $unixname\n";
    getDetails($unixname, $dbh, $datasource_id);
    $dbh->disconnect();
}
else
{
    #-- SELECT list of rubyforge projects from projects table in DB       
    my $sth = $dbh->prepare(qq{SELECT proj_unixname 
                               FROM rf_project_indexes pi 
                               WHERE datasource_id=?
                               ORDER BY proj_unixname});
    $sth->execute($datasource_id);
    my $projectsInDB = $sth->fetchall_arrayref;
    $sth->finish();

    foreach my $row (@$projectsInDB) 
    {
        my ($unixname) = @$row;
        
        print "\n\nNow working on $unixname...\n";
        getDetails($unixname, $dbh, $datasource_id);
    }   
    $dbh->disconnect(); 
}

# get details from html page
sub getDetails($unixname, $dbh, $datasource_id)
{
    my $p_unixname      = $_[0];
    my $p_dbh           = $_[1];
    my $p_datasource_id = $_[2];

    # get html page from database
    my $sth;
    $sth = $p_dbh->prepare(qq{SELECT indexhtml 
                              FROM rf_project_indexes 
                              WHERE proj_unixname=? 
                              AND datasource_id=?});
    $sth->execute($p_unixname, $p_datasource_id);
    my @indexpages = $sth->fetchrow_array; 
    $sth->finish();
    
    # ===========================    
    # gid (called 'group_id')
    # ===========================    
    if ($indexpages[0] =~ m{group_id=(\d*)})
    {
        my $gid = $1;
        
        # update the projects table with the new gid
        if ((!$DEBUG) && ($gid > 0))
        {
            my $update = $p_dbh->prepare(qq{UPDATE rf_projects 
                                        SET proj_id_num = ? 
                                        WHERE proj_unixname = ? 
                                        AND datasource_id=?});
            $update->execute($gid, $p_unixname, $p_datasource_id);
            $update->finish();
        }
        print "group_id: $gid\n";
    }
    
    # ===========================
    # registration date
    # ===========================
    if ($indexpages[0] =~ m{Registered:&nbsp;(\S*\s*\S*)(\W*)<br})
    {
        my $regDate = $1 . ":00";
        
        if (!$DEBUG)
        {
            # update the projects table
            my $update = $p_dbh->prepare(qq{UPDATE rf_projects 
                                            SET date_registered=? 
                                            WHERE proj_unixname=? 
                                            AND datasource_id=?});
            $update->execute($regDate, $p_unixname, $p_datasource_id);
            $update->finish();
        }
        print "registration date: [$regDate]\n";
    }
    
    # ===========================
    # activity percentile
    # ===========================
    if ($indexpages[0] =~ m{Activity Percentile:&nbsp;(\S*)%<br})
    {
        my $activity_percentile = $1;
            
        if (!$DEBUG)
        {
            # update the rf_projects table
            my $update = $p_dbh->prepare(qq{UPDATE rf_projects 
                                            SET activity_percentile=? 
                                            WHERE proj_unixname=? 
                                            AND datasource_id=?});
            $update->execute($activity_percentile, $p_unixname, $p_datasource_id);
            $update->finish();
        }
        print "activity percentile: [$activity_percentile]\n";
    }
    
    # ===========================
    # number of developers
    # ===========================
    if ($indexpages[0] =~ m{\">Developers:(<.*?>)(<.*?>)\s*(.*?)\s*<a href}s)
    {
        my $numDevs = $3;
        
        if (!$DEBUG)
        {
            # update the projects table
            my $update = $p_dbh->prepare(qq{UPDATE rf_projects 
                                            SET dev_count=? 
                                            WHERE proj_unixname=? 
                                            AND datasource_id=?});
            $update->execute($numDevs, $p_unixname, $p_datasource_id);
            $update->finish();
        }
        print "dev count: [$numDevs]\n";
    }
    
    # ===========================
    # environment 
    # ===========================
    if($indexpages[0] =~ m{<li>\s*Environment(.*?):\s*(<.*?)\s*</li>}s)
    {
        my $listOfEnvironments = $2;
        my @evchunks = split (/\,/, $listOfEnvironments);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_environment
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $evchunk (@evchunks)
        {
            my $evcode = 0;
            my $evdescription = "";
            
            $evchunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $evcode = $1;
            $evdescription = $2;
    
            if ((!$DEBUG) && ($evcode > 0))
            {
                $insertCodes->execute($p_unixname, $evcode, $evdescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "environment: [$evcode = $evdescription]\n";
        }
    }
    
    # ===========================
    # intended audience
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*Intended Audience(.*?):\s*(<.*?)\s*</li>}s)
    {
        my $listOfAuds = $2;
        my @iachunks = split (/\,/, $listOfAuds);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_intended_audience 
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $iachunk (@iachunks)
        {
            my $iacode = 0;
            my $iadescription = "";
            
            $iachunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $iacode = $1;
            $iadescription = $2;
    
            if ((!$DEBUG) && ($iacode > 0))
            {
                $insertCodes->execute($p_unixname, $iacode, $iadescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "intended audience: [$iacode = $iadescription]\n";
        }
    }
    
    # ===========================
    # license
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*License(.*?):\s*(<.*?)\s*</li>})
    {
        my $listOfLicenses = $2;
        my @lichunks = split (/\,/, $listOfLicenses);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_licenses
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $lichunk (@lichunks)
        {
            my $licode = 0;
            my $lidescription = "";
            
            $lichunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $licode = $1;
            $lidescription = $2;
    
            if ((!$DEBUG) && ($licode > 0))
            {
                $insertCodes->execute($p_unixname, $licode, $lidescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "license: [$licode = $lidescription]\n";
        }
    }
    
    # ===========================
    # natural language
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*Natural Language(.*?):\s*(<.*?)\s*</li>}s)
    {
        my $listOfNatLang = $2;
        my @nlchunks = split (/\,/, $listOfNatLang);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_natural_language
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $nlchunk (@nlchunks)
        {
            my $nlcode = 0;
            my $nldescription = "";
            
            $nlchunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $nlcode = $1;
            $nldescription = $2;
    
            if ((!$DEBUG) && ($nlcode > 0))
            {
                $insertCodes->execute($p_unixname, $nlcode, $nldescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "natural language: [$nlcode = $nldescription]\n";
        }
    }
    
    # ===========================
    # operating system
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*Operating System(.*?):\s*(<.*?)\s*</li>}s)
    {
        my $listOfOpSys = $2;
        my @opchunks = split (/\,/, $listOfOpSys);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_operating_system
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $opchunk (@opchunks)
        {
            my $opcode = 0;
            my $opdescription = "";
            
            $opchunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $opcode = $1;
            $opdescription = $2;
    
            if ((!$DEBUG) && ($opcode > 0))
            {
                $insertCodes->execute($p_unixname, $opcode, $opdescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "op sys: [$opcode = $opdescription]\n";
        }
    }
    
    # ===========================
    # programming language
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*Programming Language(.*?):\s*(<.*?)\s*</li>}s)
    {
        my $listOfProgLang = $2;
        my @plchunks = split (/\,/, $listOfProgLang);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_programming_language
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $plchunk (@plchunks)
        {
            my $plcode = 0;
            my $pldescription = "";
            
            $plchunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $plcode = $1;
            $pldescription = $2;
    
            if ((!$DEBUG) && ($plcode > 0))
            {
                $insertCodes->execute($p_unixname, $plcode, $pldescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "prog lang: [$plcode = $pldescription]\n";
        }
    }
    
    # ===========================
    # status
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*Development Status(.*?)form_cat=(\d+)">(\d+)\s\-\s(.*?)</a>}s)
    {
        my $stcode_on_page = $3;
        my $stdescription = $4;
        
        # only proceed this far if you have a "Development Status" line item
        if ($stcode_on_page && $stdescription)
        {
            # grab out the full Dev Status so we can have something to use to
            # lookup the correct code
            $indexpages[0] =~ m{<li>\s*Development Status(.*?):\s*(<.*?)\s*</li>}s;
            my $stfull_description = $2;
            
            $stfull_description =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            my $stcode = $1;
            
            my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_status
            (proj_unixname, code, description, code_on_page, datasource_id, date_collected) 
            VALUES (?,?,?,?,?,now())});
        
            if ((!$DEBUG) && ($stcode_on_page && $stcode && $stdescription))
            {
                $insertCodes->execute($p_unixname, $stcode, $stdescription, $stcode_on_page, $p_datasource_id);
                $insertCodes->finish();
            }
            print "status: [$stcode_on_page] [$stcode] [$stdescription]\n";
        }
    }    

    # ===========================
    # topic
    # ===========================
    if ($indexpages[0] =~ m{<li>\s*Topic(.*?):\s*(<.*?)\s*</li>}s)
    {
        my $listOfTopics = $2;
        my @tpchunks = split (/\,/, $listOfTopics);
        
        my $insertCodes = $p_dbh->prepare(qq{INSERT IGNORE INTO rf_project_topic
        (proj_unixname, code, description, datasource_id, date_collected) 
        VALUES (?,?,?,?,now())});
    
        # do this for each "description" referenced in the html code
        foreach my $tpchunk (@tpchunks)
        {
            my $tpcode = 0;
            my $tpdescription = "";
            
            $tpchunk =~ m{form_cat=(\d*)\S+>(.*?)</a>};
            $tpcode = $1;
            $tpdescription = $2;
    
            if ((!$DEBUG) && ($tpcode > 0))
            {
                $insertCodes->execute($p_unixname, $tpcode, $tpdescription, $p_datasource_id);
                $insertCodes->finish();
            }
            print "topic: [$tpcode = $tpdescription]\n";
        }
    }
    # ===========================    
    # project home page
    # as of 15-Jan-2007, the code looks like:
    # <td colspan="2" class="titlebar">Public Areas</td>
	  # </tr>
	  # <tr align="left" bgcolor="#B6B6B6">
	  # <td colspan="2" height="1"></td></tr><tr align="left"><td colspan="2"><a href="http://eventmachine.rubyforge.org"><img src="http
    # ===========================    
    if ($indexpages[0] =~ m{<td colspan="2" class="titlebar">Public Areas</td>(.*?)<a href="(.*?)"><img src="http}s)
    {
        my $real_url = $2;
        
        # update the projects table with the new gid
        if ((!$DEBUG) && ($real_url))
        {
            my $update = $p_dbh->prepare(qq{UPDATE rf_projects 
                                        SET real_url = ? 
                                        WHERE proj_unixname = ? 
                                        AND datasource_id=?});
            $update->execute($real_url, $p_unixname, $p_datasource_id);
            $update->finish();
        }
        print "url: [" . substr($real_url,0,100) . "]\n";
    }
}
