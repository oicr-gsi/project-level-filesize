#!/bin/bash

# Wrapper for generating HTML reports on Lab Disk Usage
WORKINGDIR=$1
SCRIPTDIR=$2

# Check for missing files and directories
if [ ! -e $WORKINGDIR ]
then
	echo "Working Directory $WORKINGDIR does not exist."
	exit
fi

if [ ! -e "$SCRIPTDIR/NonSeqWare_Labs.txt" ]
then
	echo "$SCRIPTDIR/NonSeqWare_Labs.txt does not exist!"
	exit
fi

if [ ! -e "$SCRIPTDIR/groups.yml" ]
then
        echo "$SCRIPTDIR/group.yml does not exist!"
        exit
fi

# Call scripts to generate HTML report
$SCRIPTDIR/project-filesize-reporting.pl $WORKINGDIR $SCRIPTDIR
$SCRIPTDIR/generateFileSizeWebPages.pl $WORKINGDIR  $SCRIPTDIR
