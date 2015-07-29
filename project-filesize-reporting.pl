#!/usr/bin/perl
# Script that given a list of dirs for non-SeqWare files, will generate a csv containing filesize information.
# Also automatically gets similar data for SeqWare files from the file provenance report and stores them in the same csv file.
# USAGE:
# ./project-filesize-reporting.pl <file with list of directories> 

=pod

How this script works:
This script pulls information from three places.
For SeqWare files:
	-uses file provenance report to get all projects
For non-SeqWare files:
	-uses input file (looks at their subdirectories of depth 1)
For both:
	-once it gets the appropriate information, this script will search the seqware database for corresponding file sizes and then combine them into a .csv file.

If this is the first run, the .csv file created is called project-sizes.csv.
If not then a .tmp csv file is created, so that the previous csv file can be used to calculate project/directory velocity

=cut

use strict;
use warnings;
use DBI;

# Connect to database
my $path = `pwd`;
chomp($path);
$ENV{PGSYSCONFDIR} = $path;
my $dbh = DBI->connect("dbi:Pg:service=prod", undef, undef, { AutoCommit => 1 }) or die "Can't connect to the database: $DBI::errstr\n";

# Setup input
my $InputPath = shift @ARGV;
unless (-e $InputPath)  {       die "Cannot find input location: '$InputPath'\n";       }

# Get Current Date
my $DateRec = `date +"%T %D"`;
chomp($DateRec);

my $Quota = "";

# AllDirs.file stores all directories that we are calculating size for non-SW files
my $AllDirs = "AllDirs.file";
if (-e $AllDirs) {
	`rm $AllDirs`;
}

# Stores columns 2 (Study Title) and 49 (File Size) from the File Provenance Report (FPR)
my $FPR = "/FileProvReport.tsv";

# File Provenance report is used to get data on SW files
print "Grabbing File Provenance Report and extracting data.\n";
#`find /.mounts/labs/seqprodbio/private/backups/hsqwprod-db/ -regextype sed -regex ".*seqware_files_report.*gz" | sort -r | head -1 | xargs zcat | cut -f2,49| tail -n +2 | sort -s -k 1,1 > $FPR`;

# Project List which stores a list of all projects 
my $ProjectFile = "ProjectList.file";

# Make an array of all the different projects
print "Determining all projects.\n";
my @projects;

`cut -f1 $FPR | sort | uniq > $ProjectFile`;

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
if (-e "project-sizes.csv"){
	$OutputFile = "project-sizes.csv.tmp";
} else {
	$OutputFile = "project-sizes.csv";
}

print "Calculating directory sizes of non-SeqWare Files.\n";

open my $ALL_DIR_FH, "<", $AllDirs or die "Can't read file '$AllDirs'\n";
open my $OUTPUT_FILE_FH, ">", $OutputFile or die "Can't create file '$OutputFile'\n";

my $FileSizeSum = 0; # Total size of all files in a directory

# Print header of output file
print $OUTPUT_FILE_FH "Date Recorded,File Path,File Size Sum (Bytes),Quota (GB)\n";

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

# Calculate file size sum of projects for SW and store to file
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
