#!/bin/bash

# Copyright 2012,2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

#
# define some variables
#
URL="http://anonscm.debian.org/viewvc/d-i/trunk/.mrconfig?view=co"
FAIL=false
DI_BUILD_JOB_PATTERN=d-i_build_
DI_MANUAL_JOB_PATTERN=d-i_manual_
TMPFILE=$(mktemp)
JOB_TEMPLATES=$(mktemp)
PROJECT_JOBS=$(mktemp)

#
# check for missing d-i package build jobs
# for this, we compare referred git repos in .mrconfig against locally existing jenkins jobs
# 	(see http://wiki.debian.org/DebianInstaller/CheckOut)
#
echo "Scanning $URL for referred git repos which have no jenkins job associated."
curl $URL > $TMPFILE 2>/dev/null
PACKAGES=$( grep git.debian.org/git/d-i $TMPFILE|cut -d "/" -f6-|cut -d " " -f1)
#
# check for each git repo if a jenkins job exists
#
for PACKAGE in $PACKAGES ; do
	if [ ! -d ~jenkins/jobs/${DI_BUILD_JOB_PATTERN}${PACKAGE} ] ; then
		echo "Warning: No build job '${DI_BUILD_JOB_PATTERN}${PACKAGE}'."
		FAIL=true
		#
		# prepare yaml bits
		#
		echo "      - '{name}_build_$PACKAGE':" >> $PROJECT_JOBS
		echo "         gitrepo: 'git://git.debian.org/git/d-i/$PACKAGE'" >> $PROJECT_JOBS
		echo "- job-template:" >> $JOB_TEMPLATES
		echo "    defaults: d-i-build" >> $JOB_TEMPLATES
		echo "    name: '{name}_build_$PACKAGE'" >> $JOB_TEMPLATES
	else
		echo "Ok: Job '${DI_BUILD_JOB_PATTERN}${PACKAGE}' exists."
	fi
done
#
# check for each job if there still is a git repo
#
for JOB in $(ls -1 ~jenkins/jobs/ | grep ${DI_BUILD_JOB_PATTERN}) ; do
	REPONAME=${JOB:10}
	grep -q git+ssh://git.debian.org/git/d-i/$REPONAME $TMPFILE || echo "Warning: Git repo $REPONAME not found in $URL, but job $JOB exists."
done 
# cleanup
rm $TMPFILE

#
# check for missing d-i manual language build jobs
#
# first the xml translations...
#
cd ~jenkins/jobs/d-i_manual/workspace/manual
IGNORE="build debian doc README scripts build-stamp doc-base-stamp po"
for DIRECTORY in * ; do
	for i in $IGNORE ; do
		if [ "$DIRECTORY" == "$i" ] ; then
			DIRECTORY=""
			break
		fi
	done
	if [ "$DIRECTORY" == "" ] ; then
		continue
	else
		for FORMAT in pdf html ; do
			if [ ! -d ~jenkins/jobs/${DI_MANUAL_JOB_PATTERN}${DIRECTORY}_${FORMAT} ] ; then
				echo "Warning: No build job '${DI_MANUAL_JOB_PATTERN}${DIRECTORY}_${FORMAT}'."
				FAIL=true
				#
				# prepare yaml bits
				#
				echo "      - '{name}_manual_${DIRECTORY}_${FORMAT}':" >> $PROJECT_JOBS
				echo "         lang: '$DIRECTORY'" >> $PROJECT_JOBS
				echo "         languagename: 'FIXME: $DIRECTORY'" >> $PROJECT_JOBS
				echo "- job-template:" >> $JOB_TEMPLATES
				echo "    defaults: d-i-manual-${FORMAT}" >> $JOB_TEMPLATES
				echo "    name: '{name}_manual_${DIRECTORY}_${FORMAT}'" >> $JOB_TEMPLATES
			fi
		done
	fi
done
# FIXME: check for removed manuals (but with existing jobs) missing - for all types of manuals and build jobs
#
# ...and now the translations kept in po files....
cd po
IGNORE="pot README"
for DIRECTORY in * ; do
	for i in $IGNORE ; do
		if [ "$DIRECTORY" == "$i" ] ; then
			DIRECTORY=""
			break
		fi
	done
	if [ "$DIRECTORY" == "" ] ; then
		continue
	else
		for FORMAT in pdf html ; do
			if [ ! -d ~jenkins/jobs/${DI_MANUAL_JOB_PATTERN}${DIRECTORY}_${FORMAT} ] ; then
				echo "Warning: No build job '${DI_MANUAL_JOB_PATTERN}${DIRECTORY}_${FORMAT}'."
				FAIL=true
				#
				# prepare yaml bits - po2xml jobs just use different defaults
				#
				echo "      - '{name}_manual_${DIRECTORY}_${FORMAT}':" >> $PROJECT_JOBS
				echo "         lang: '$DIRECTORY'" >> $PROJECT_JOBS
				echo "         languagename: 'FIXME: $DIRECTORY'" >> $PROJECT_JOBS
				echo "- job-template:" >> $JOB_TEMPLATES
				echo "    defaults: d-i-manual-${FORMAT}-po2xml" >> $JOB_TEMPLATES
				echo "    name: '{name}_manual_${DIRECTORY}_${FORMAT}'" >> $JOB_TEMPLATES
			fi
		done
	fi
done

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
