#!/usr/bin/perl

# This script will generate HTML files for project-level filesize reporting, and move them to the appropriate web url.
# USAGE:
# ./generateFileSizeWebPages.pl
# This script expects you to run, in the same directory, the project-filesize-reporting.pl script.

=pod

How the script works:
After running project-filesize-reporting.pl, you will have a csv file containing the SeqWare and all the given non-SeqWare projects/directories.
That script will either produce project-sizes.csv or project-sizes.csv.tmp.

For the first run of that script, you get the default csv file.  For the second run and beyond, you get the .tmp csv.  If the script finds a
project-sizes.csv in the current directory, then it assumes that the script has been run before.  It then will create this .tmp csv file.

This script will base the generated HTML files information off of the .tmp script (if one exists), and any velocity information is determined using
the original and the .tmp csv.  Once this script is completed, the .tmp csv will be copied to the default one, and the .tmp will be removed.

This script also uses the .tmp idea.  For the first run of this script, it will just be able to display the file size and quota information; it
cannot display the velocity since it has nothing to compare sizes to.  The second time and beyond this script is run, it will store all the HTML files as
.tmp files, and once completed will copy the .tmp files to the original HTML files.

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

# YAML file with group information
my $yaml = shift @ARGV;

# Make sure appropriate file exists
if (! -e "project-sizes.csv"){
	print "Requires project-sizes.csv file.  Please run project-filesize-reporting.pl before running this script.\n";
	exit;
}

# Create HTML template files
my $HTMLGroupTemplateStart = "<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"><link href=\"dataTables.bootstrap.css\" rel=\"stylesheet\"></head><body><div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><div class=\"page-header\"><h1>Group File Sizes</h1></div><ol class=\"breadcrumb\"><li class=\"active\">Groups</li></ol><table id=\"group_table\" class=\"table table-hover\"><thead><tr><th>Group</th><th>Data Generation Velocity (GB/Day)</th></tr></thead><tbody>"; 
my $HTMLGroupTemplateEnd = "</tbody></table></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script><script type=\"text/javascript\" charset=\"utf8\" src=\"DataTables-1.10.7/media/js/jquery.dataTables.js\"></script><script type=\"text/javascript\" src=\"dataTables.bootstrap.js\"></script><script>\$(document).ready( function () { \$('#group_table').DataTable({paging:false, searching:false, info:false});});</script></body></html>";

my $HTMLSingleTemplateStart = "<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"><link href=\"dataTables.bootstrap.css\" rel=\"stylesheet\"></head><body><div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><div class=\"page-header\"><h1>LABNAME File Sizes</h1></div><ol class=\"breadcrumb\"><li><a href=\"groups-size.html\">Groups</a></li><li class=\"active\">LABNAME</li></ol><table id=\"single_table\" class=\"table table-hover\"><thead><tr><th>Project/Directory</th><th>Size (GB)</th><th>Data Generation Velocity (GB/Day)</th><th>Quota (GB)</th></thead></tr><tbody>"; 
my $HTMLSingleTemplateEnd = "</tbody></table></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script><script type=\"text/javascript\" charset=\"utf8\" src=\"DataTables-1.10.7/media/js/jquery.dataTables.js\"></script><script type=\"text/javascript\" src=\"dataTables.bootstrap.js\"></script><script>\$(document).ready( function () { \$('#single_table').DataTable({paging:false, searching:false, info:false});});</script></body></html>";

my $HTMLGroupCenter = ""; # Will become the rows of the table for the Group page
my $HTMLSingleCenter = ""; # Will become the rows of each table for a specific lab page

# Open and store YAML file
open my $YAML_FH, '<', $yaml or die "can't open config file '$yaml'";
my $config = LoadFile($YAML_FH);

# Setup for global variables
my $lab_output = "size.html"; 
my $output_dir = "/.mounts/labs/PDE/web/filesize_reports";
my $default_lab_output = "size.html"; # Used only when the script has been run before
my $ProjectCSV = "project-sizes.csv"; # CSV file with dir size information
my $PreviousRun = 0; # 0 => no previous run, 1 => a previous run exists
my $GroupSizeSum = 0; # Directory size of a specific group/lab
my $OldFileSizeSum = 0; # Previous subdirectory size for a specific group/lab
my $OldGroupSizeSum = 0; # Previous directory size of a specific group/lab

# Function for converting a value in bytes to gb
# Pre: a size in bytes
# Post: a size in GB
sub bytes_to_gb {
	my $value = `units -- '$_[0] bytes' 'gigabytes' | head -1 | cut -f2 -d' '`;
	chomp($value);
	return $value;
}

# If this is not the first run of the script, .tmp is used on the new files which are created based on the most recent information in the database.
# They are compared with the previous project-sizes.csv file to determine data generation velocity
if (-e "project-sizes.csv.tmp") {
	$lab_output .= ".tmp";
	$PreviousRun = 1;
	$ProjectCSV .= ".tmp";
}

# Open file which will become the Groups HTML page
open my $GROUP_FH, '>', "groups-$lab_output" or die "can't write to 'group-$lab_output'";

# Print top portion of Group HTML page to appropriate file
print $GROUP_FH $HTMLGroupTemplateStart;

# Iterate through YAML file
while ( my ($k1, $v1) = each %$config) {
	$GroupSizeSum = 0;
	$OldGroupSizeSum = 0;
	print "$k1\n";

	# Open a file which will become a specific Lab HTML page
	open my $SINGLE_FH, '>', "$k1-$lab_output" or die "can't write to '$k1-$lab_output'";

	# Print top portion of Lab HTML page to appropriate file
	my $HTMLLab = $HTMLSingleTemplateStart;
	$HTMLLab =~ s/LABNAME/$k1/g;
        print $SINGLE_FH $HTMLLab;

	# Iterate through SeqWare and Non-SeqWare Projects/Directories
	while (my ($k2, $v2) = each %$v1 ){
		foreach $a (@$v2) {
			# Open file containing filesize information
			open my $PROJECT_SIZES_FH, '<', $ProjectCSV or die "can't read from '$ProjectCSV'\n";
			if ($PreviousRun == 1) {
				# Get old file size sum for a given directory/project
				$OldFileSizeSum =  `grep -w "$a" "project-sizes.csv" | cut -f3 -d','`;
				if ($OldFileSizeSum ne "") {
					$OldGroupSizeSum += $OldFileSizeSum;
				}
			}
			
			# Iterate through csv file
			while(my $line = <$PROJECT_SIZES_FH>){
				chomp($line);
				my ($DateRec, $FilePath, $FileSizeSum, $Quota) = split (',', $line);
				if ($FilePath eq $a) {
					$GroupSizeSum += $FileSizeSum;

					# Add rows to Lab HTML page
					if ($PreviousRun == 1){ # If not the first run of the script
						if (-e "$output_dir/$k1-size.html") { # If group/lab exists in the previous run
							my $NewFileCount = `grep -w "$a" "$output_dir/$k1-size.html" | wc -l`; # Checks if Project/Dir is new to this run
							if ($NewFileCount == 0) {
                                                	        $HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>N/A</td><td>" . $Quota . "</td></tr>"; 
							} elsif ($FileSizeSum - $OldFileSizeSum > 0) { # If positive File Size Sum
								$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>+" . bytes_to_gb($FileSizeSum - $OldFileSizeSum) . "</td><td>" . $Quota . "</td></tr>";
							} else { # If negative File Size Sum
								$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>" . bytes_to_gb($FileSizeSum - $OldFileSizeSum) . "</td><td>" . $Quota . "</td></tr>";
							}
						} else { # If group/lab has just been added to YAML file
							$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>N/A</td><td>" . $Quota . "</td></tr>";
						}
					} else {
						$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>N/A</td><td>" . $Quota . "</td></tr>";
					}

					# Print middle portion of Lab HTML page to appropriate file
					print $SINGLE_FH $HTMLSingleCenter;
					$HTMLSingleCenter = "";
				}
			}
			close($PROJECT_SIZES_FH);
		}
	}
	# Print bottom portion of Lab HTML page to appropriate file
	print $SINGLE_FH $HTMLSingleTemplateEnd;
	close($SINGLE_FH);

	# If this is not the first run of the script, then copy our .tmp files to the correct location
	if ($PreviousRun == 1){
		if (! -e "$output_dir/$k1-size.html") { # If group/lab has just been added to YAML file
			`cat "$k1-$lab_output" > "$k1-$default_lab_output"`;
                        `rm "$k1-$lab_output"`;
			$HTMLGroupCenter = "<tr><td><a href=\"$k1-$default_lab_output\">" . $k1 . "</a></td><td>N/A</td></tr>";
		} else { # Group/lab has existed in previous runs
			`cat "$k1-$lab_output" > "$k1-$default_lab_output"`;
			`rm "$k1-$lab_output"`;

			if ($GroupSizeSum - $OldGroupSizeSum > 0){ # if positive Group Size Sum
				$HTMLGroupCenter = "<tr><td><a href=\"$k1-$default_lab_output\">" . $k1 . "</a></td><td>+" . bytes_to_gb($GroupSizeSum - $OldGroupSizeSum) . "</td></tr>";
			} else { # If negative Group Size Sum
				$HTMLGroupCenter = "<tr><td><a href=\"$k1-$default_lab_output\">" . $k1 . "</a></td><td>" . bytes_to_gb($GroupSizeSum - $OldGroupSizeSum) . "</td></tr>";
			}
		}
	} else {
		$HTMLGroupCenter = "<tr><td><a href=\"$k1-$lab_output\">" . $k1 . "</a></td><td>N/A</td></tr>";
	}
	
	# Print middle portion of Group HTML page to appropriate file
	print $GROUP_FH $HTMLGroupCenter;
}

# Print bottom portion of Group HTML page to appropriate file
print $GROUP_FH $HTMLGroupTemplateEnd;
close ($GROUP_FH);
close ($YAML_FH);

# If this is not the first run of the script, then copy our .tmp files to the correct location
if ($PreviousRun == 1) {
	`cat "groups-$lab_output" > "groups-$default_lab_output"`;
	`rm "groups-$lab_output"`;
	`cat "$ProjectCSV" > "project-sizes.csv"`;
	`rm "$ProjectCSV"`;
}

# Move files to web and set permissions
`rm $output_dir/*html`;
`cp *.html $output_dir`;
`chmod 754 $output_dir/*.html`;

# Clean up
`rm *.html`;

# Show script runtime
print "Script completed in ";
print time - $^T;
print " seconds\n";
