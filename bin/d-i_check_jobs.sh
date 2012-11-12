#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# default settings
#
set -x
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
for PACKAGE in $( grep git.debian.org/git/d-i $TMPFILE|cut -d "/" -f6-) ; do
	#
	# check if a jenkins job exists
	#
	if [ ! -d ~jenkins/jobs/${DI_JOBPATTERN}${PACKAGE} ] ; then
		echo "Warning: No build job \'${DI_JOBPATTERN}${PACKAGE}\'."
		FAIL=true
	else
		echo "Ok: Job \'${DI_JOBPATTERN}${PACKAGE}\' exists."
	fi
done
echo
rm $TMPFILE

#
# check for missing d-i manual lanague build jobs
#
# FIXME: implement this check ;-)

#
# fail this job if missing d-i jobs are detected
#
if $FAIL ; then 
	figlet "Missing jobs!"
	exit 1
else
	figlet ok
fi
