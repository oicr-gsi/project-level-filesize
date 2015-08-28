#!/usr/bin/perl

############################################################################################################################################################
# project-filesize-reporting.pl
#
#
# Overview: This script creates a csv file containing the disk usage and quota information for all OICR labs non-seqware and seqware files.
# Parameters: A file containing all of the non-seqware directories whose disk usage information need to be generated.
#
# Usage:
# ./project-filesize-reporting.pl <Working Dir> <Script Dir>
#
# Then run generateFileSizeWebPages.pl.
#
############################################################################################################################################################

=pod

How this script works:
1. Get a list of all projects (ProjectList.file) from the file provenance report
2. Get all dirs  to have disk usage calculated for (AllDirs.file).  Based on input file, will find all children dirs of given dirs (maxdepth 1)
3. Find the disk usage of all dirs (Non-SeqWare) found in step 2 from the reporting.file table in the SeqWare DB, save to a CSV
4. Find the disk usage of all projects (SeqWare) in the file table in the SeqWare DB, append to csv from 3.

A few useful points:
-The format of the CSV file is Date Recorded,File Path,File Size Sum (Bytes),Quota (TB)
-If this is not the first run of the script, a tmp csv file is made since the old one is needed for ./generateFileSizeWebPages.pl to calculate data generation velocity
-Set up db connection with .pgpass and pg_config files (Google for more details)

=cut

use strict;
use warnings;
use DBI;

my $WorkingDir = $ARGV[0];
my $ScriptDir = $ARGV[1];
chomp($WorkingDir);
chomp($ScriptDir);

# Connect to database
$ENV{PGSYSCONFDIR} = $ScriptDir;
my $dbh = DBI->connect("dbi:Pg:service=prod", undef, undef, { AutoCommit => 1 }) or die "Can't connect to the database: $DBI::errstr\n";

# Setup input
my $InputPath = "$ScriptDir/NonSeqWare_Labs.txt";
unless (-e $InputPath)  {       die "Cannot find input location: '$InputPath'\n";       }

# Get Current Date
my $DateRec = `date +"%T %D"`;
chomp($DateRec);

my $Quota = "";

# AllDirs.file stores all directories that we are calculating size for non-SW files
my $AllDirs = "$WorkingDir/AllDirs.file";

if (-e $AllDirs) {
	`rm $AllDirs`;
}

# Stores columns 2 (Study Title) and 49 (File Size) from the File Provenance Report (FPR)
my $FPR = "$WorkingDir/FileProvReport.tsv";

# File Provenance report is used to get data on SW files
print "Grabbing File Provenance Report and extracting data.\n";
`find /.mounts/labs/seqprodbio/private/backups/hsqwprod-db/ -regextype sed -regex ".*seqware_files_report.*gz" | sort -r | head -1 | xargs zcat | cut -f2,49| tail -n +2 | sort -s -k 1,1 > $FPR`;

# Project List which stores a list of all projects 
my $ProjectFile = "$WorkingDir/ProjectList.file";

# Make an array of all the different projects
print "Determining all projects.\n";
my @projects;

# Grab list of projects from the FPR
`cut -f1 $FPR | sort | uniq > $ProjectFile`;

# Store Projects into an array
open my $PROJECT_FH, "<", $ProjectFile or die "Can't read file '$ProjectFile'\n";

while (<$PROJECT_FH>){
	chomp($_);
	push (@projects, $_);
}

close ($PROJECT_FH);

# Get all possible dirs to examine given the input file (Goes one deep in each)
print "Finding non-SeqWare dirs.\n";
open my $INPUT_FILE_FH, "<", $InputPath or die "Can't read file '$InputPath'\n";

while (<$INPUT_FILE_FH>) {
	chomp($_);
	print `find $_ -mindepth 1 -maxdepth 1 -type d >> $AllDirs`;
}

close ($INPUT_FILE_FH);

# If this script has been run before, we can generate Data Generation Velocity
my $OutputFile;
if (-e "$WorkingDir/project-sizes.csv"){
	$OutputFile = "$WorkingDir/project-sizes.csv.tmp";
} else {
	$OutputFile = "$WorkingDir/project-sizes.csv";
}

print "Calculating directory sizes of non-SeqWare Files.\n";

open my $ALL_DIR_FH, "<", $AllDirs or die "Can't read file '$AllDirs'\n";
open my $OUTPUT_FILE_FH, ">", $OutputFile or die "Can't create file '$OutputFile'\n";

my $FileSizeSum = 0; # Total size of all files in a directory

# Print header of output file
print $OUTPUT_FILE_FH "Date Recorded,File Path,File Size Sum (Bytes),Quota (TB)\n";

# Calculate disk usage for non-seqware directories
while (<$ALL_DIR_FH>) {
	chomp($_);

	$FileSizeSum = 0;
	my $sql = 'SELECT file_size FROM reporting.file WHERE file_path LIKE ?';
	my $sth = $dbh->prepare($sql);

	print "$_\n";

	$sth->execute($_ . "%");
	
	while (my @row = $sth->fetchrow_array) {
		$FileSizeSum = $FileSizeSum + $row[0];
	}
	
	# Alter Path so that Quota can be found
	my $IFSPath = $_;
	$IFSPath =~ s/.mounts/ifs/g;
	$Quota =  `/oicr/local/sw/hpcquota/hpcquota-1.0.1/bin/hpcquota -d "$IFSPath" --no-header --units=GiB 2>/dev/null | sed 's/ \\+/\\t/g' | cut -f3`;
	chomp($Quota);

	if ($Quota ne "") {
		print $OUTPUT_FILE_FH "$DateRec,$_,$FileSizeSum,$Quota\n";
	} else {
		print $OUTPUT_FILE_FH "$DateRec,$_,$FileSizeSum,N/A\n";
	}
}

close ($ALL_DIR_FH);
$FileSizeSum = 0; # Now total size of all files related to the given project

# Calculate disk usage of projects for SW and store to file
print "Calculating directory sizes of SeqWare Projects.\n";

open my $FPR_FH, "<", $FPR or die "Can't read file '$FPR'\n";
foreach (@projects) {
	chomp($_);
	while (my $Line = <$FPR_FH>) {
		chomp($Line);
		my ($Project, $Size) = split (/\t/, $Line);
		if ("$_" eq "$Project") {
			if ($Size ne "") {
				$FileSizeSum = $FileSizeSum + $Size;
			}
		}
	}
	if ($_ eq "") {
		print $OUTPUT_FILE_FH "$DateRec,Ungrouped,$FileSizeSum,N/A\n";
	} else {
		print $OUTPUT_FILE_FH "$DateRec,$_,$FileSizeSum,N/A\n";
	}
	$FileSizeSum = 0;
	seek $FPR_FH, 0, 0;
}

close ($FPR_FH);
close ($OUTPUT_FILE_FH);

# Disconnect from database
$dbh->disconnect;

# Clean up files
`rm $AllDirs`;
`rm $ProjectFile`;
`rm $FPR`;

print "Script completed in ";
print time - $^T;
print " seconds\n";
