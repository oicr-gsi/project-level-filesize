#!/usr/bin/perl

###################################################################################################################################################################################
# generateFileSizeWebPages.pl
#
#
# Overview:  Takes two calculate_project_file_size.sh output files as input and generates HTML files to display the data.
#            The project config.yaml file is used to format the report html page.
#
# Usage:
# ./generateFileSizeWebPages.pl current_project_file_sizes.csv previous_project_file_sizes.csv config.yaml output_dir
#
####################################################################################################################################################################################

=pod

How the script works:
After running calculate_project_file_size.sh, you will have a csv file containing all the project file sizes.

The previous project file sizes csv is used to calculate data generation velocity.

The HTML file content are created from template strings.
There is two template HTML strings for the group page and individual lab pages.
	-start of the HTML file, up until the rows of the table
	-the remaining part of the HTML file, starting from the end of the table

These two parts are almost identical between labs, it is the table row content that differentiates these.
The row content is generated using the groups.yml file and the .csv file from the previous script.

Required perl libraries:
libyaml-perl
libmath-round-perl

=cut

use strict;
use warnings;
use YAML qw(LoadFile);
use Text::CSV;
use Math::Round;

# Check the number of inputs
my $NumberOfInputs = @ARGV;

# Check that the correct number of inputs are supplied
if ( $NumberOfInputs != 5 ) {
    die
"You have entered $NumberOfInputs argument(s).  This script require 5 arguments to run.\n";
}

my $CurrentData  = $ARGV[0];
my $PreviousData = $ARGV[1];
my $yaml         = $ARGV[2];
my $WorkingDir   = $ARGV[3];
my $OutputDir    = $ARGV[4];
chomp($CurrentData);
chomp($PreviousData);
chomp($yaml);
chomp($WorkingDir);
chomp($OutputDir);

# Make sure appropriate file exists
if ( !-e $CurrentData ) {
    print "current project level sizes csv file.\n";
    exit;
}

# Make sure appropriate file exists
if ( !-e $PreviousData ) {
    print "previous project level sizes csv file not accessible.\n";
    exit;
}

if ( !-e $yaml ) {
    print "config.yaml file not accessible.\n";
    exit;
}

if ( !-e $WorkingDir && !-d $WorkingDir && !dir_is_empty($WorkingDir) ) {
    print "working dir not accessible or not empty.\n";
    exit;
}

if ( !-e $OutputDir && !-d $OutputDir ) {
    print "output dir not accessible.\n";
    exit;
}

if ( $OutputDir eq $WorkingDir ) {
    print "output dir and working dir must be different.\n";
    exit;
}

#load data
my %current  = load_project_size_csv($CurrentData);
my %previous = load_project_size_csv($PreviousData);

open my $YAML_FH, '<', $yaml or die "can't open config file '$yaml'";
my $config = LoadFile($YAML_FH);
close($YAML_FH);

my $GeneratedTime = `date`;
chomp($GeneratedTime);

# Create HTML template files
my $HTMLHeader =
"<nav class=\"navbar navbar-default\"><div class=\"container-fluid\"><!-- Brand and toggle get grouped for better mobile display --><div class=\"navbar-header\"><button type=\"button\" class=\"navbar-toggle collapsed\" data-toggle=\"collapse\" data-target=\"#bs-example-navbar-collapse-1\"><span class=\"sr-only\">Toggle navigation</span><span class=\"icon-bar\"></span><span class=\"icon-bar\"></span><span class=\"icon-bar\"></span></button><a class=\"navbar-brand\" href=\"http://www-pde.hpc.oicr.on.ca/landing/\"><img alt=\"GSI\" src=\"images/dna_helix.png\" width=\"25px\"></a></div><!-- Collect the nav links, forms, and other content for toggling --><div class=\"collapse navbar-collapse\" id=\"bs-example-navbar-collapse-1\"><ul class=\"nav navbar-nav\"><li><a href=\"http://www-pde.hpc.oicr.on.ca/landing/\">Home <span class=\"sr-only\">(current)</span></a></li><li><a href=\"http://www.hpc.oicr.on.ca/archive/web/seqwareBrowser/seqwareBrowser.html\">SeqWare Browser</a></li><li><a href=\"http://www-gsi.hpc.oicr.on.ca/sw-dm/studies\">Management</a></li><li class=\"active\"><a href=\"http://www-pde.hpc.oicr.on.ca/filesize_reports/groups-size.html\">Disk Usage</a></li><li><a href=\"mailto:gsi\@oicr.on.ca\">Contact GSI</a></li></ul></div><!-- /.navbar-collapse --></div><!-- /.container-fluid --></nav>";

my $HTMLGroupTemplateStart =
"<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"><link href=\"dataTables.bootstrap.css\" rel=\"stylesheet\"></head><body>$HTMLHeader<div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><div class=\"page-header\"><h1>Per Lab Disk Usage</h1></div><ol class=\"breadcrumb\"><li class=\"active\">Groups</li></ol><h4>Total Disk Space Used (TB) : TOTAL_SIZE</h4><table id=\"group_table\" class=\"table table-hover\"><thead><tr><th>Group</th><th>Size (TB)</th><th>Data Generation Velocity (TB/Day)</th></tr></thead><tbody>";
my $HTMLGroupTemplateEnd =
"</tbody></table><p>Last updated $GeneratedTime</p></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script><script type=\"text/javascript\" charset=\"utf8\" src=\"DataTables-1.10.7/media/js/jquery.dataTables.js\"></script><script type=\"text/javascript\" src=\"dataTables.bootstrap.js\"></script><script>\$(document).ready( function () { \$('#group_table').DataTable({paging:false, searching:false, info:false});});</script></body></html>";

my $HTMLSingleTemplateStart =
"<html lang=\"en\"><head><title>FileSize Reporting Overview</title><link href=\"bootstrap/css/bootstrap.min.css\" rel=\"stylesheet\"><link href=\"dataTables.bootstrap.css\" rel=\"stylesheet\"></head><body>$HTMLHeader<div class=\"container-fluid\"><div class=\"row\"><div class=\"col-lg-10 col-lg-offset-1\"><div class=\"page-header\"><h1>LABNAME Disk Usage</h1></div><ol class=\"breadcrumb\"><li><a href=\"groups-size.html\">Groups</a></li><li class=\"active\">LABNAME</li></ol><h4>Total Disk Space Used (TB) : TOTAL_SIZE</h4><table id=\"single_table\" class=\"table table-hover\"><thead><tr><th>Project/Directory</th><th>Size (TB)</th><th>Data Generation Velocity (TB/Day)</th><th>Quota (TB)</th></thead></tr><tbody>";
my $HTMLSingleTemplateEnd =
"</tbody></table><p>Last updated $GeneratedTime</p></div></div></div><script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js\"></script><script src=\"js/bootstrap.min.js\"></script><script type=\"text/javascript\" charset=\"utf8\" src=\"DataTables-1.10.7/media/js/jquery.dataTables.js\"></script><script type=\"text/javascript\" src=\"dataTables.bootstrap.js\"></script><script>\$(document).ready( function () { \$('#single_table').DataTable({paging:false, searching:false, info:false});});</script></body></html>";

my $HTMLGroupCenter = ""; # Will become the rows of the table for the Group page
my $HTMLSingleCenter =
  "";    # Will become the rows of each table for a specific lab page

# Setup for more global variables
my $HTMLSuffix   = "size.html";
my $LabDiskUsage = 0;             # Disk usage of a specific group/lab

#my $OldProjectDiskUsage = 0;      # Previous disk usage for a specific group/lab
my $OldLabDiskUsage = 0;          # Previous disk usage of a specific group/lab
my $TotalDiskUsage  = 0;          # Total disk usage of all labs

# Open file which will become the Groups HTML page
open my $GROUP_FH, '>', "$WorkingDir/groups-$HTMLSuffix"
  or die "can't write to '$WorkingDir/group-$HTMLSuffix'";

# Iterate through YAML file
while ( my ( $k1, $v1 ) = each %$config ) {
    $LabDiskUsage    = 0;
    $OldLabDiskUsage = 0;
    print "$k1\n";

    # Open a file which will become a specific Lab HTML page
    open my $SINGLE_FH, '>', "$WorkingDir/$k1-$HTMLSuffix"
      or die "can't write to '$WorkingDir/$k1-$HTMLSuffix'";

    # Setup top portion of Lab HTML page
    my $HTMLLab = $HTMLSingleTemplateStart;
    $HTMLLab =~ s/LABNAME/$k1/g;

    # Iterate through SeqWare and Non-SeqWare Projects/Directories
    while ( my ( $k2, $v2 ) = each %$v1 ) {
        foreach $a (@$v2) {
            my $Project = $a;

            # Get old file size sum for a given project
            my $OldProjectDiskUsage = $previous{$a}{size};
            if ( defined $OldProjectDiskUsage && $OldProjectDiskUsage ne "" ) {
                $OldLabDiskUsage += $OldProjectDiskUsage;
            }
            else {
                print "$a is not present in previous\n";
            }

            # Get current file size sum for a given project
            my $ProjectDiskUsage = $current{$a}{size};
            my $ReportProjectDiskUsage;
            if ( defined $ProjectDiskUsage && $ProjectDiskUsage ne "" ) {
                $LabDiskUsage += $ProjectDiskUsage;
                $ReportProjectDiskUsage =
                  commify( bytes_to_tb($ProjectDiskUsage) );
            }
            else {
                $ReportProjectDiskUsage = "N/A";
                print "$a is not present in current\n";
            }

            my $ReportVelocity;
            if ( defined $OldProjectDiskUsage && defined $ProjectDiskUsage ) {
                $ReportVelocity =
                  commify(
                    bytes_to_tb( $ProjectDiskUsage - $OldProjectDiskUsage ) );
            }
            else {
                $ReportVelocity = "N/A";
            }

            my $Quota = $current{$a}{quota};
            my $ReportQuota;
            if ( defined $Quota ) {
                $ReportQuota = commify($Quota);
            }
            else {
                $ReportQuota = "N/A";
            }

            # Add rows to Lab HTML page
            $HTMLSingleCenter .=
                "<tr>" . "<td>"
              . $a . "</td>" . "<td>"
              . $ReportProjectDiskUsage . "</td>" . "<td>"
              . $ReportVelocity . "</td>" . "<td>"
              . $ReportQuota . "</td>" . "</tr>";
        }
    }

    $TotalDiskUsage += $LabDiskUsage;
    my $PrettyLabDiskUsage = commify( bytes_to_tb($LabDiskUsage) );
    $HTMLLab =~ s/TOTAL_SIZE/$PrettyLabDiskUsage/g;
    print $SINGLE_FH $HTMLLab;
    print $SINGLE_FH $HTMLSingleCenter;
    $HTMLSingleCenter = "";

    # Print bottom portion of Lab HTML page to appropriate file
    print $SINGLE_FH $HTMLSingleTemplateEnd;
    close($SINGLE_FH);

    $HTMLGroupCenter .=
        "<tr>"
      . "<td><a href=\"$k1-$HTMLSuffix\">"
      . $k1
      . "</a></td>" . "<td>"
      . $PrettyLabDiskUsage . "</td>" . "<td>"
      . commify( bytes_to_tb( $LabDiskUsage - $OldLabDiskUsage ) )
      . "</td> " . "</tr>";
}

# Print top portion of Group HTML page to appropriate file
$TotalDiskUsage = commify( bytes_to_tb($TotalDiskUsage) );
$HTMLGroupTemplateStart =~ s/TOTAL_SIZE/$TotalDiskUsage/g;
print $GROUP_FH $HTMLGroupTemplateStart;

# Print middle portion of Group HTML page to appropriate file
print $GROUP_FH $HTMLGroupCenter;

# Print bottom portion of Group HTML page to appropriate file
print $GROUP_FH $HTMLGroupTemplateEnd;
close($GROUP_FH);

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
    return nearest( .01, $_[0] / ( 1024 * 1024 * 1024 * 1024 ) );

}

# from Andrew Johnson <ajohnson@gpu.srv.ualberta.ca>
sub commify {
    my $input = shift;
    $input = reverse $input;
    $input =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
    return reverse $input;
}

sub load_project_size_csv {
    open my $FH, '<', $_[0] or die "can't open file '$_[0]'";
    my %data;
    while ( my $line = <$FH> ) {
        my ( $DateRecorded, $Project, $ProjectDiskUsage, $Quota ) = split ",",
          $line;
        $data{$Project}{'size'}  = $ProjectDiskUsage;
        $data{$Project}{'quota'} = $Quota;
    }
    close($FH);
    return %data;
}

#http://rosettacode.org/wiki/Empty_directory#Perl
sub dir_is_empty { !<$_[0]/*> }
