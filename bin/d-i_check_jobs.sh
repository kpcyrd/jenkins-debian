#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# default settings
#
#set -x
set -e
export LC_ALL=C
export http_proxy="http://localhost:3128"

#
# define some variables
#
URL="http://anonscm.debian.org/viewvc/d-i/trunk/.mrconfig?view=co"
FAIL=false
DI_JOBPATTERN=d-i_build_
TMPFILE=$(mktemp)

#
# check for missing d-i package build jobs
# for this, we compare referred git repos in .mrconfig against locally existing jenkins jobs
# 	(see http://wiki.debian.org/DebianInstaller/CheckOut)
#
echo "Scanning $URL for reffered git repos which have no jenkins job associated."
curl $URL > $TMPFILE 2>/dev/null
PACKAGES=$( grep git.debian.org/git/d-i $TMPFILE|cut -d "/" -f6-)
JOB_TEMPLATES=$(mktemp)
PROJECT_JOBS=$(mktemp)
#
# check for each git repo if a jenkins job exists
#
for PACKAGE in $PACKAGES ; do
	if [ ! -d ~jenkins/jobs/${DI_JOBPATTERN}${PACKAGE} ] ; then
		echo "Warning: No build job '${DI_JOBPATTERN}${PACKAGE}'."
		FAIL=true
		#
		# prepare yaml bits
		#
		echo "      - '{name}_build_$PACKAGE':" >> $PROJECT_JOBS
		echo "         gitrepo: 'git://git.debian.org/git/d-i/$PACKAGE'" >> $PROJECT_JOBS
		echo "- job-template:" >> $JOB_TEMPLATES
		echo "    defaults: d-i-build" >> $JOB_TEMPLATES
		echo "    name: '{name}_build_anna'" >> $JOB_TEMPLATES
	else
		echo "Ok: Job '${DI_JOBPATTERN}${PACKAGE}' exists."
	fi
done
#
# check for each job if there still is a git repo
#
for JOB in $(ls -1 ~jenkins/jobs/ | grep ${DI_JOBPATTERN}) ; do
	REPONAME=${JOB:10}
	grep -q git+ssh://git.debian.org/git/d-i/$REPONAME $TMPFILE || echo "Warning: Git repo $REPONAME not found in $URL, but job $JOB exists."
done 
# cleanup
rm $TMPFILE

#
# check for missing d-i manual language build jobs
#
# FIXME: implement this check ;-)
echo "Warning: check for missing d-i manual build jobs not implemented"

#
# fail this job if missing d-i jobs are detected
#
echo
if $FAIL ; then 
	figlet "Missing jobs!"
	echo
	echo "Add these job templates to job-cfg/d-i.yaml:"
	cat $JOB_TEMPLATES
	echo
	echo
	echo "Append this to the project definition in job-cfg/d-i.yaml:"
	cat $PROJECT_JOBS
	echo
	rm $JOB_TEMPLATES $PROJECT_JOBS
	exit 1
else
	figlet ok
fi
