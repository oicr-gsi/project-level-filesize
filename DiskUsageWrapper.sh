#!/bin/bash

SCRIPTDIR=$1

$SCRIPTDIR/project-filesize-reporting.pl $SCRIPTDIR/NonSeqWare_Labs.txt
$SCRIPTDIR/generateFileSizeWebPages.pl $SCRIPTDIR/groups.yml
