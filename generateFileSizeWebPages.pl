#!/usr/bin/perl

###################################################################################################################################################################################
# generateFileSizeWebPages.pl
#
#
# Overview:  Takes output from the project-filesize-reporting.pl script and generates HTML files to display the data.  The output goes to /.mounts/labs/PDE/web/filesize_reports
# 	     and can be found at http://www-pde.hpc.oicr.on.ca/filesize_reports/groups-size.html
#
# Usage:
# ./generateFileSizeWebPages.pl <WorkingDir> <ScriptDir>
#
####################################################################################################################################################################################
=pod

How the script works:
After running project-filesize-reporting.pl, you will have a csv file containing the SeqWare and all the given non-SeqWare projects/directories.
That script will either produce project-sizes.csv or project-sizes.csv.tmp.

For the first run of that script (project-filesize-reporting.pl), you get the non-tmp csv file.  For the second run and beyond, you get the .tmp csv.  If the script finds a
project-sizes.csv in the current directory, then it assumes that the script has been run before.  It then will create this .tmp csv file.

This script also uses the .tmp idea.  For the first run of this script, it will just be able to display the file size and quota information; it
cannot display the velocity since it has nothing to compare sizes to.  The second time and beyond this script is run, it will have both a project-sizes.csv and project-sizes.csv.tmp.
Since it has both files, it can properly determine the data generation velocity.

The HTML file content are created from template strings.
There is two template HTML strings for the group page and individual lab pages.
	-start of the HTML file, up until the rows of the table
	-the remaining part of the HTML file, starting from the end of the table

These two parts are almost identical between labs, it is the table row content that differentiates these.
The row content is generated using the groups.yml file and the .csv file from the previous script.

=cut

use strict;
use warnings;
use DBI;
use YAML qw(LoadFile);
use Math::Round;

# Check the number of inputs
my $NumberOfInputs = @ARGV;

# Check that the correct number of inputs are supplied
if ( $NumberOfInputs != 2 ) {
        die "You have entered $NumberOfInputs argument(s).  This script require 2 arguments to run.\n";
}

my $WorkingDir = $ARGV[0];
my $ScriptDir = $ARGV[1];
chomp($WorkingDir);
chomp($ScriptDir);

# YAML file with group information
my $yaml = "$ScriptDir/groups.yml";

# Make sure appropriate file exists
if (! -e "$WorkingDir/project-sizes.csv"){
	print "Requires project-sizes.csv file.  Please run project-filesize-reporting.pl before running this script.\n";
	exit;
}

my $GeneratedTime = `date`;
chomp($GeneratedTime);

# Create HTML template files
my $HTMLHeader = "<nav class=\"navbar navbar-default\"><div class=\"container-fluid\"><!-- Brand and toggle get grouped for better mobile display --><div class=\"navbar-header\"><button type=\"button\" class=\"navbar-toggle collapsed\" data-toggle=\"collapse\" data-target=\"#bs-example-navbar-collapse-1\"><span class=\"sr-only\">Toggle navigation</span><span class=\"icon-bar\"></span><span class=\"icon-bar\"></span><span class=\"icon-bar\"></span></button><a class=\"navbar-brand\" href=\"http://www-pde.hpc.oicr.on.ca/landing/\"><img alt=\"GSI\" src=\"images/dna_helix.png\" width=\"25px\"></a></div><!-- Collect the nav links, forms, and other content for toggling --><div class=\"collapse navbar-collapse\" id=\"bs-example-navbar-collapse-1\"><ul class=\"nav navbar-nav\"><li><a href=\"http://www-pde.hpc.oicr.on.ca/landing/\">Home <span class=\"sr-only\">(current)</span></a></li><li><a href=\"http://www.hpc.oicr.on.ca/archive/web/seqwareBrowser/seqwareBrowser.html\">SeqWare Browser</a></li><li><a href=\"http://www-gsi.hpc.oicr.on.ca/sw-dm/studies\">Management</a></li><li class=\"active\"><a href=\"http://www-pde.hpc.oicr.on.ca/filesize_reports/groups-size.html\">Disk Usage</a></li><li><a href=\"mailto:gsi\@oicr.on.ca\">Contact GSI</a></li></ul></div><!-- /.navbar-collapse --></div><!-- /.container-fluid --></nav>";

my $HTMLGroupTemplateStart = "<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"><link href=\"dataTables.bootstrap.css\" rel=\"stylesheet\"></head><body>$HTMLHeader<div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><div class=\"page-header\"><h1>Per Lab Disk Usage</h1></div><ol class=\"breadcrumb\"><li class=\"active\">Groups</li></ol><h4>Total Disk Space Used (TB) : TOTAL_SIZE</h4><table id=\"group_table\" class=\"table table-hover\"><thead><tr><th>Group</th><th>Size (TB)</th><th>Data Generation Velocity (TB/Day)</th></tr></thead><tbody>"; 
my $HTMLGroupTemplateEnd = "</tbody></table><p>Last updated $GeneratedTime</p></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script><script type=\"text/javascript\" charset=\"utf8\" src=\"DataTables-1.10.7/media/js/jquery.dataTables.js\"></script><script type=\"text/javascript\" src=\"dataTables.bootstrap.js\"></script><script>\$(document).ready( function () { \$('#group_table').DataTable({paging:false, searching:false, info:false});});</script></body></html>";

my $HTMLSingleTemplateStart = "<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"><link href=\"dataTables.bootstrap.css\" rel=\"stylesheet\"></head><body>$HTMLHeader<div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><div class=\"page-header\"><h1>LABNAME Disk Usage</h1></div><ol class=\"breadcrumb\"><li><a href=\"groups-size.html\">Groups</a></li><li class=\"active\">LABNAME</li></ol><h4>Total Disk Space Used (TB) : TOTAL_SIZE</h4><table id=\"single_table\" class=\"table table-hover\"><thead><tr><th>Project/Directory</th><th>Size (TB)</th><th>Data Generation Velocity (TB/Day)</th><th>Quota (TB)</th></thead></tr><tbody>"; 
my $HTMLSingleTemplateEnd = "</tbody></table><p>Last updated $GeneratedTime</p></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script><script type=\"text/javascript\" charset=\"utf8\" src=\"DataTables-1.10.7/media/js/jquery.dataTables.js\"></script><script type=\"text/javascript\" src=\"dataTables.bootstrap.js\"></script><script>\$(document).ready( function () { \$('#single_table').DataTable({paging:false, searching:false, info:false});});</script></body></html>";

my $HTMLGroupCenter = ""; # Will become the rows of the table for the Group page
my $HTMLSingleCenter = ""; # Will become the rows of each table for a specific lab page

# Open and store YAML file
open my $YAML_FH, '<', $yaml or die "can't open config file '$yaml'";
my $config = LoadFile($YAML_FH);

# Setup for more global variables
my $HTMLSuffix = "size.html"; 
my $OutputDir = "/.mounts/labs/PDE/web/filesize_reports";
my $DefaultHTMLSuffix = "size.html"; # Used only when the script has been run before
my $ProjectCSV = "$WorkingDir/project-sizes.csv"; # CSV file with dir size information
my $PreviousRun = 0; # 0 => no previous run, 1 => a previous run exists
my $LabDiskUsage = 0; # Disk usage of a specific group/lab
my $OldProjectDiskUsage = 0; # Previous disk usage for a specific group/lab
my $OldLabDiskUsage = 0; # Previous disk usage of a specific group/lab
my $TotalDiskUsage = 0; # Total disk usage of all labs

# If this is not the first run of the script, .tmp is used on the new files which are created based on the most recent information in the database.
# They are compared with the previous project-sizes.csv file to determine data generation velocity
if (-e "$WorkingDir/project-sizes.csv.tmp") {
	$HTMLSuffix .= ".tmp";
	$PreviousRun = 1;
	$ProjectCSV .= ".tmp";
}

# Open file which will become the Groups HTML page
open my $GROUP_FH, '>', "$WorkingDir/groups-$HTMLSuffix" or die "can't write to '$WorkingDir/group-$HTMLSuffix'";

# Iterate through YAML file
while ( my ($k1, $v1) = each %$config) {
	$LabDiskUsage = 0;
	$OldLabDiskUsage = 0;
	print "$k1\n";

	# Open a file which will become a specific Lab HTML page
	open my $SINGLE_FH, '>', "$WorkingDir/$k1-$HTMLSuffix" or die "can't write to '$WorkingDir/$k1-$HTMLSuffix'";

	# Setup top portion of Lab HTML page
	my $HTMLLab = $HTMLSingleTemplateStart;
	$HTMLLab =~ s/LABNAME/$k1/g;

	# Iterate through SeqWare and Non-SeqWare Projects/Directories
	while (my ($k2, $v2) = each %$v1 ){
		foreach $a (@$v2) {
			# Open file containing filesize information
			open my $PROJECT_SIZES_FH, '<', $ProjectCSV or die "can't read from '$ProjectCSV'\n";
			
			# Get old file size sum for a given dir/project
			if ($PreviousRun == 1) {
				$OldProjectDiskUsage =  `grep -w "$a" "$WorkingDir/project-sizes.csv" | cut -f3 -d','`;
				if ($OldProjectDiskUsage ne "") {
					$OldLabDiskUsage += $OldProjectDiskUsage;
				}
			}
			
			# Iterate through csv file
			while(my $line = <$PROJECT_SIZES_FH>){
				chomp($line);
				my ($DateRecorded, $FilePath, $ProjectDiskUsage, $Quota) = split (',', $line);
				if ($FilePath eq $a) {
					$LabDiskUsage += $ProjectDiskUsage;

					# Add rows to Lab HTML page
					if ($PreviousRun == 1){ # If not the first run of the script
						if (-e "$OutputDir/$k1-size.html") { # If group/lab exists in the previous run
							my $NewFileCount = `grep -w "$a" "$OutputDir/$k1-size.html" | wc -l`; # Checks if Project/Dir is new to this run
							if ($NewFileCount == 0) {
                                                	        $HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . commify(bytes_to_tb($ProjectDiskUsage)) . "</td><td>N/A</td><td>" . commify($Quota) . "</td></tr>"; 
							} elsif ($ProjectDiskUsage - $OldProjectDiskUsage > 0) { # If positive File Size Sum
								$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . commify(bytes_to_tb($ProjectDiskUsage)) . "</td><td>+" . commify(bytes_to_tb($ProjectDiskUsage - $OldProjectDiskUsage)) . "</td><td>" . commify($Quota) . "</td></tr>";
							} else { # If negative File Size Sum
								$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . commify(bytes_to_tb($ProjectDiskUsage)) . "</td><td>" . commify(bytes_to_tb($ProjectDiskUsage - $OldProjectDiskUsage)) . "</td><td>" . commify($Quota) . "</td></tr>";
							}
						} else { # If group/lab has just been added to YAML file
							$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . commify(bytes_to_tb($ProjectDiskUsage)) . "</td><td>N/A</td><td>" . commify($Quota) . "</td></tr>";
						}
					} else {
						$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . commify(bytes_to_tb($ProjectDiskUsage)) . "</td><td>N/A</td><td>" . commify($Quota) . "</td></tr>";
					}

				}
			}
			close($PROJECT_SIZES_FH);
		}

	}

	$TotalDiskUsage += $LabDiskUsage;
	my $PrettyLabDiskUsage = commify(bytes_to_tb($LabDiskUsage));
	$HTMLLab =~ s/TOTAL_SIZE/$PrettyLabDiskUsage/g;
        print $SINGLE_FH $HTMLLab;
        print $SINGLE_FH $HTMLSingleCenter;
        $HTMLSingleCenter = ""; 

	# Print bottom portion of Lab HTML page to appropriate file
	print $SINGLE_FH $HTMLSingleTemplateEnd;
	close($SINGLE_FH);

	# If this is not the first run of the script, then copy our .tmp files to the correct location
	if ($PreviousRun == 1){
		if (! -e "$OutputDir/$k1-size.html") { # If group/lab has just been added to YAML file
			`cat "$WorkingDir/$k1-$HTMLSuffix" > "$WorkingDir/$k1-$DefaultHTMLSuffix"`;
                        `rm "$WorkingDir/$k1-$HTMLSuffix"`;
			$HTMLGroupCenter .= "<tr><td><a href=\"$k1-$DefaultHTMLSuffix\">" . $k1 . "</a></td><td>" . $PrettyLabDiskUsage . "</td><td>N/A</td></tr>";
		} else { # Group/lab has existed in previous runs
			`cat "$WorkingDir/$k1-$HTMLSuffix" > "$WorkingDir/$k1-$DefaultHTMLSuffix"`;
			`rm "$WorkingDir/$k1-$HTMLSuffix"`;

			if ($LabDiskUsage - $OldLabDiskUsage > 0){ # if positive Group Size Sum
				$HTMLGroupCenter .= "<tr><td><a href=\"$k1-$DefaultHTMLSuffix\">" . $k1 . "</a></td><td>" . $PrettyLabDiskUsage . "</td><td>+" . commify(bytes_to_tb($LabDiskUsage - $OldLabDiskUsage)) . "</td></tr>";
			} else { # If negative Group Size Sum
				$HTMLGroupCenter .= "<tr><td><a href=\"$k1-$DefaultHTMLSuffix\">" . $k1 . "</a></td><td>" . $PrettyLabDiskUsage . "</td><td>" . commify(bytes_to_tb($LabDiskUsage - $OldLabDiskUsage)) . "</td></tr>";
			}
		}
	} else {
		$HTMLGroupCenter .= "<tr><td><a href=\"$k1-$HTMLSuffix\">" . $k1 . "</a></td><td>" . $PrettyLabDiskUsage . "</td><td>N/A</td></tr>";
	}
	

}
# Print top portion of Group HTML page to appropriate file
$TotalDiskUsage = commify(bytes_to_tb($TotalDiskUsage));
$HTMLGroupTemplateStart =~ s/TOTAL_SIZE/$TotalDiskUsage/g;
print $GROUP_FH $HTMLGroupTemplateStart;

# Print middle portion of Group HTML page to appropriate file
print $GROUP_FH $HTMLGroupCenter;

# Print bottom portion of Group HTML page to appropriate file
print $GROUP_FH $HTMLGroupTemplateEnd;
close ($GROUP_FH);
close ($YAML_FH);

# If this is not the first run of the script, then copy our .tmp files to the correct location
if ($PreviousRun == 1) {
	`cat "$WorkingDir/groups-$HTMLSuffix" > "$WorkingDir/groups-$DefaultHTMLSuffix"`;
	`rm "$WorkingDir/groups-$HTMLSuffix"`;
	`cat "$ProjectCSV" > "$WorkingDir/project-sizes.csv"`;
	`rm "$ProjectCSV"`;
}

# Move files to web and set permissions
`rm $OutputDir/*html`;
`cp $WorkingDir/*.html $OutputDir`;
`chmod 754 $OutputDir/*.html`;

# Clean up
`rm $WorkingDir/*.html`;

# Show script runtime
print "Script completed in ";
print time - $^T;
print " seconds\n";



############################################################################################################################################################################
# Custom Functions
#
############################################################################################################################################################################

# Function for converting a value in bytes to TB
# Pre: a size in bytes
# Post: a size in TB
sub bytes_to_tb {
	# Uncommenting code below will put ~0.01 anytime the size is under 0.01 TB. 
	# This breaks sorting though
#	if (abs $_[0] < 10995116277 and abs $_[0] != 0){
#		return "~0.01";
#	}
        return nearest(.01,$_[0]/(1024*1024*1024*1024));
	
}

# from Andrew Johnson <ajohnson@gpu.srv.ualberta.ca>
sub commify {
        my $input = shift;
        $input = reverse $input;
        $input =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
        return reverse $input;
}

