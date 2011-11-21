#! /usr/bin/perl -w
use strict;
use warnings;

# Released under the GPL 3.0 http://www.gnu.org/copyleft/gpl.html
# By Martin Cleaver http://martin.cleaver.org
# 21 Nov 2011

# This script puts into Freshbooks time logged from a CSV file
# I use it with MediaAtelia's TimeLog 4, but it should work with any CSV output
# Use your favourite time tracker's system to make Project names with a project code appended.
# This should look like "(PppTtt)" - including the parenthesis. The pp and tt codes are Project Number and Task Number that corresponds to FreshBooks.

# Pass the name of the CSV file as a parameter to this script

my $input = $ARGV[0] || die "Pass name of CSV file containing Freshbooks time";

# IN THE CSV FILE
# The time counted in the Duration column into the date of the Start Column
# The PppTtt refers to a Project and Task number in Freshbooks.
# Freshbooks uses these to determine which client, project and task to use.
# The script will ignore unknown fields
# The category field is ignored.
# The client field is ignored.
# If pp and tt are XX then the row is skipped


# Sample CSV file
# Project,Category,Duration,Start,Notes,Client
#Natural Gas Fracking (P18T10),Default 75,1.1,2011-08-20,Earthquake Experiment,Energy In Depth
#BP Oilrig Accounting (P40T10),Default 75,1.8,2011-08-21,,Martin Cleaver
#Impeachment Proof of Concept (P38T8),Default 125,0.1,2011-08-24,,Monika Lewinsky


# HOW DO YOU GET THOSE pp and tt NUMBERS?
# I've asked FreshBooks to make those numbers available via the UI: http://community.freshbooks.com/forums/viewtopic.php?pid=39161
#
# In the meantime it's a bit awkward, but you need to do it only once after you've added new project codes.
# If you get stuck please comment on the thread http://community.freshbooks.com/forums/viewtopic.php?pid=39161 
#
# Three choices - 1) greasemonkey 2) view source 3) use a REST client
# 1) My Greasemonkey Script
# Install Greasemonkey or Tampermonkey (for Chrome) - see http://userscripts.org/scripts/show/118709
#
# 2) View source
# You can get the project number by going to the project in Freshbooks, Time Tracking, Projects, Project and doing view source.
# Look for "projectid-" the PP after projectid is the project number. e.g. projectid-38.
# or you can see all of the projects 
# You can get the task number by going to Time Tracking -> Tasks -> Task Item -> Edit Task -> View Source. Search for "taskid". The number you want is in the value="tt"
# e.g. name='taskid' value='10'
#
# 3) 
# Use REST to discover them
# On my Mac I use RESTClient.app
# URL=https://blendedperspectives.freshbooks.com/api/2.1/xml-in 
# Method=POST
# BODY=<?xml version="1.0" encoding="utf-8"?><request method="project.list">
#<per_page>100</per_page></request>
#  This comes from http://developers.freshbooks.com/docs/projects/#project.list to list the projects
# AUTH:
#  AuthType: Basic
#  Username=your API key; (Store it below, in $key)
#  Password: anything (it is ignored)


# This script is a horrid hack. 
# But it works. You are welcome to make it better.

our ($key, $xml_in) = (0,0);
# You need to keep your freshbooks API key and XML_IN values in a configuration file
# That needs to set 
#our $key = 'fbfbfbfbfbfbfbfb000000'; # your API key
#our $xml_in = 'https://youraccount.freshbooks.com/api/2.1/xml-in';

my $config_file = 'csvtime2freshbooks.config';
require $config_file;

die 'Set $key to your API key in '.$config_file unless $key;
die 'Set $xml_in in '.$config_file.' to your FreshBooks XML_IN URL' unless $xml_in;

# SMELL
# So script cannot detect duplicates.
# TimeLog4 doesn't let me use the List -> Open List with Numbers (Settings) to export the TimeLog unique id into the Numbers CSV
# And I can't insert the response from FreshBooks back into TimeLog 



use POSIX qw(strftime);
my $today = strftime "%Y-%m-%d", localtime;

# SMELL - these parameters should be configurable.
my $start = 1; # 1, or a previous value of $limit - $count...
# ... if you need to start from somewhere other than the first row
my $limit = 1000; # how many records to input; a sample of 1 is a good test!
my $justPretend = 0;
# TODO - a log would be nice



# ---- You shouldn't need to modify anything after here

sub getProjectAndTask {
    my $timelog4project = shift;
    if (! $timelog4project ) {
	die "No project code - it should be (PxTy) where x=project number, y=task number from FreshBooks";
    }
    print "Extracting project & task for ".$timelog4project."\n";

    my ($project, $task) = $timelog4project =~ m!.*\(P(..?)T(..?)\).*!;
    if (! $project) {
	die "Couldn't parse project $timelog4project";
    }
    if (! $task) {
	die "Couldn't parse task";
    }
    print "   Project: $project Task: $task\n";
    return ($project, $task);
}


use Tie::Handle::CSV;

my $fh = Tie::Handle::CSV->new($input, header => 1);

my $lineNumber = 1; # Because spreadsheets show to users first line as line 1
my $countDone = 0; 
my $totalHours = 0; 

print "Starting at line $start\n";
print "Stopping after $limit lines\n";
while (my $csv_line = <$fh>) {
    $lineNumber++;

    print "\n";
    print "LINE: $lineNumber C: $countDone; $csv_line\n";
    if ($lineNumber <$start) {
	print " (skipping until line $start)\n";
	next;
    }
    if ($countDone >= $limit) {
	print "ABORTING AS COUNT ($countDone) >= LIMIT ($limit)\n";
	last;
    };
    my $date =$csv_line->{'Start'};
    $date =~ s/\(W.*\)//;

    my $project;
    my $task;
    # Get the project code from Timelog, if it has it.
    if (! $csv_line->{'Project'}) {
	die "No Project column! Aborting - assuming end of data at line $lineNumber!"; # The csv should always have the column, even if it is blank.
    } else {
	($project, $task) = getProjectAndTask($csv_line->{'Project'});
    }

    if ($project eq 'XX' && $task eq 'XX') {
	print " (skipping line as not for Freshbooks)\n";
	next;
    }

    # Allow it to be overridden with a column in the csv.
    if ($csv_line->{'FB Code'}) {
	($project, $task) = getProjectAndTask('('.$csv_line->{'FB Code'}.')');
    }


    my $notes = $csv_line->{'Notes'};
    $notes =~ s/\&/\&amp;/g; # SMELL - use XML::Writer
    $notes =~ s/\'//g; # BUG - quotes kill my crap script
    $notes =~ s/\"//g; # BUG - quotes kill my crap script

    $notes .= " ($input, row $lineNumber, on $today)";
    my $category =  $csv_line->{'Category'};
    my $hours = $csv_line->{'Duration'};
    my $freshbooks_task_number = $task;
    if (! $task ) {
	die "Couldn't find task number (for category $category)";
    }

    if ($date) {
	logTime($date, $hours, $project, $task, $notes);
	$totalHours += $hours;
    } else {
	print "skipping duration ($hours) s as date is blank (this is probably the total line (it should equal $totalHours))\n";
    }
    $countDone ++;
}

close $fh;

my ($lateDate, $lastHours, $lastProject, $lastTask, $lastNotes);
sub logTime {
    my ($date, $hours, $project, $task, $notes) = @_;
    print "\nDATE: $date, $hours, $project, $task, $notes\n";

#    if ($lastProject) {
#	if ($lastProject eq $project &&
#	    $lastTask eq $task) {

#	    if ($notes ne "") {
#		$lastHours 
#		
#
#    ($lateDate, $lastHours, $lastProject, $lastTask, $lastNotes);
    

    logTimeXML($date, $hours, $project, $task, $notes);
}


sub logTimeXML {
    my ($date, $hours, $project, $task, $notes) = @_;

my $xml = <<MESSAGE

<request method="time_entry.create">
<time_entry>
<project_id>$project</project_id>
<task_id>$task</task_id>
<hours>$hours</hours>
<date>$date</date>
<notes>$notes</notes>
</time_entry>
</request>
MESSAGE
    ;




my $cmd="curl -s -S -u $key:X $xml_in -d '$xml'";

print $cmd."\n";
    my $cmdResponse;

    if ($justPretend) {
	print "NOT ACTUALLY RUNNING THIS as justPretend is not false\n";
	return;
    }

    $cmdResponse = `$cmd`;
    print $cmdResponse;

    $cmdResponse =~ m!status="(.*)"!;
    my $status = $1;
    
    if ($status ne "ok") {
	print "ABORTED: '$status' ne 'ok' in response:\n";
	print $cmdResponse;
	die "OOPS";
    }

}
