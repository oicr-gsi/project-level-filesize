#!/bin/bash
set -eu

if [[ $# != 1 ]]; then
  echo "Illegal number of arguments, one argument expected: file provenance report path" >&2
  exit 1
fi

FPR=$1

if [[ ! -e ${FPR} && ! -r ${FPR} ]]; then
  echo "Cannot read file provenance report" >&2
  exit 1
fi

zcat -f ${FPR} | awk -F'\t' '
NR>1 { 
  file_count[$45]+=1; 
  if(length($2)==0) { 
    project = "Ungrouped" 
  } else { 
    project = $2 
  }; 
  if(file_count[$45] == 1) { 
    project_sizes[project]+=$49 
  } 
} 
END { 
  for (i in project_sizes) { 
    print "'"$(date +"%T %D"),"'" i "," project_sizes[i] ",N/A"
  } 
}
' | sort -s -k 2,2
