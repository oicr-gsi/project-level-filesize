#!/usr/bin/perl

# This script will generate HTML files for project-level filesize reporting.
# USAGE:
# ./generateFileSizeWebPages.pl
# This script expects you to run, in the same directory, the project-filesize-reporting.pl script.

use strict;
use warnings;
use DBI;
use YAML qw(LoadFile);

# YAML file with group information
my $yaml = "groups.yaml";

# Make sure appropriate file exists
if (! -e "project-sizes.csv"){
	print "Requires project-sizes.csv file.  Please run project-filesize-reporting.pl before running this script.\n";
	exit;
}

# Create HTML template files
my $HTMLGroupTemplateStart = "<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"></head><body><div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><h1>Group File Sizes</h1><ol class=\"breadcrumb\"><li class=\"active\">Groups</li></ol><table class=\"table table-hover\"><thead><tr><th>Group</th><th>Data Generation Velocity (GB/Day)</th></tr></thead>"; 
my $HTMLGroupTemplateEnd = "</table></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script></body></html>";

my $HTMLSingleTemplateStart = "<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"></head><body><div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><h1>LABNAME File Sizes</h1><ol class=\"breadcrumb\"><li><a href=\"groups-size.html\">Groups</a></li><li class=\"active\">LABNAME</li></ol><table class=\"table table-hover\"><thead><tr><th>Project/Directory</th><th>Size (GB)</th><th>Data Generation Velocity (GB/Day)</th><th>Quota (GB)</th></thead></tr>"; 
my $HTMLSingleTemplateEnd = "</table></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script></body></html>";

my $HTMLGroupCenter = ""; # Will become the rows of the table for the Group page
my $HTMLSingleCenter = ""; # Will become the rows of each table for a specific lab page

# Open and store YAML file
open my $YAML_FH, '<', $yaml or die "can't open config file '$yaml'";
my $config = LoadFile($YAML_FH);
my $lab_output = "size.html"; 
my $default_lab_output = "size.html"; # Used only when the script has been run before

my $ProjectCSV = "project-sizes.csv"; # CSV file with dir size information
my $PreviousRun = 0; # 0 => no previous run, 1 => a previous run exists
my $GroupSizeSum = 0; # Directory size of a specific group/lab
my $OldFileSizeSum = 0; # Previous subdirectory size for a specific group/lab
my $OldGroupSizeSum = 0; # Previous directory size of a specific group/lab

# Function for converting a value in bytes to gb
sub bytes_to_gb {
	my $value = `units -- '$_[0] bytes' 'gigabytes' | head -1 | cut -f2 -d' '`;
	chomp($value);
	return $value;
}

# Create separate files based on lab
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

					# If no Quota information set to N/A
					if ($Quota eq "") {
						$Quota = "N/A";
					}

					# Add rows to Lab HTML page
					if ($PreviousRun == 1){
						my $NewFileCount = `grep "$a" "$k1-size.html" | wc -l`;
						if ($NewFileCount == 0) {
                                                        $HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>N/A</td><td>" . $Quota . "</td></tr>"; 
						} elsif ($FileSizeSum - $OldFileSizeSum > 0) {
							$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>+" . bytes_to_gb($FileSizeSum - $OldFileSizeSum) . "</td><td>" . $Quota . "</td></tr>";
						} else {
							$HTMLSingleCenter .= "<tr><td>" . $FilePath . "</td><td>" . bytes_to_gb($FileSizeSum) . "</td><td>" . bytes_to_gb($FileSizeSum - $OldFileSizeSum) . "</td><td>" . $Quota . "</td></tr>";
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
		`cat "$k1-$lab_output" > "$k1-$default_lab_output"`;
		`rm "$k1-$lab_output"`;

		
		if ($GroupSizeSum - $OldGroupSizeSum > 0){
			$HTMLGroupCenter = "<tr><td><a href=\"$k1-$default_lab_output\">" . $k1 . "</a></td><td>+" . bytes_to_gb($GroupSizeSum - $OldGroupSizeSum) . "</td></tr>";
		} else {
			$HTMLGroupCenter = "<tr><td><a href=\"$k1-$default_lab_output\">" . $k1 . "</a></td><td>" . bytes_to_gb($GroupSizeSum - $OldGroupSizeSum) . "</td></tr>";
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
`cp *.html /.mounts/labs/PDE/web/filesize_reports`;
`chmod 754 /.mounts/labs/PDE/web/filesize_reports/*.html`;

# Show script runtime
print "Script completed in ";
print time - $^T;
print " seconds\n";
