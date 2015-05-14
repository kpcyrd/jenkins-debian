#!/bin/bash

# Copyright 2012,2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
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
CLEANUP=$(mktemp)

#
# check for missing d-i package build jobs
# for this, we compare referred git repos in .mrconfig against locally existing jenkins jobs
# 	(see http://wiki.debian.org/DebianInstaller/CheckOut)
#
echo
echo "Scanning $URL for referred git repos which have no jenkins job associated."
curl $URL > $TMPFILE 2>/dev/null
PACKAGES=$( grep git.debian.org/git/d-i $TMPFILE|cut -d "/" -f6-|cut -d " " -f1)
#
# check for each git repo if a jenkins job exists
#
for PACKAGE in $PACKAGES ; do
	if grep -A 1 git+ssh://git.debian.org/git/d-i/$PACKAGE $TMPFILE | grep -q "deleted = true" ; then
		# ignore deleted repos
		echo "Info: git+ssh://git.debian.org/git/d-i/$PACKAGE ignored as it has been deleted."
		continue
	elif [ ! -d ~jenkins/jobs/${DI_BUILD_JOB_PATTERN}${PACKAGE} ] ; then
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
echo
#
# check for each job if there still is a git repo
#
echo "Checking if there are jenkins jobs for which there is no repo in $URL - or only a deleted one."
for JOB in $(ls -1 ~jenkins/jobs/ | grep ${DI_BUILD_JOB_PATTERN}) ; do
	REPONAME=${JOB:10}
	if grep -q git+ssh://git.debian.org/git/d-i/$REPONAME $TMPFILE ; then
		if grep -A 1 git+ssh://git.debian.org/git/d-i/$REPONAME $TMPFILE | grep -q "deleted = true" ; then
			echo "Warning: Job $JOB exists, but has 'deleted = true' set in .mrconfig."
			if ! grep -q "'git://git.debian.org/git/d-i/$REPONAME'" /srv/jenkins/job-cfg/d-i.yaml ; then
				echo "jenkins-jobs delete $JOB" >> $CLEANUP
			else
				echo "# Please remove $JOB from job-cfg/d-i.yaml before deleting the job." >> $CLEANUP
			fi
		else
			echo "Ok: Job $JOB for git+ssh://git.debian.org/git/d-i/$REPONAME found."
		fi
	else
		echo "Warning: Git repo $REPONAME not found in $URL, but job $JOB exists."
	fi
done 
# cleanup
rm $TMPFILE
echo

#
# check for missing d-i manual language build jobs
#
# first the xml translations...
#
cd ~jenkins/jobs/d-i_manual/workspace/manual
IGNORE="build debian doc README scripts build-stamp doc-base-stamp po"
for DIRECTORY in * ; do
	# Some languages are unsupported
	case $DIRECTORY in
		eu)	echo "The manual for the language $DIRECTORY has been disabled."
			continue ;;
	esac
	for i in $IGNORE ; do
		if [ "$DIRECTORY" = "$i" ] ; then
			DIRECTORY=""
			break
		fi
	done
	if [ "$DIRECTORY" = "" ] ; then
		continue
	else
		for FORMAT in pdf html ; do
			if [ $FORMAT = pdf ] ; then
				# Some languages are unsupported in PDF
				case $DIRECTORY in
					el|ja|vi|zh_CN|zh_TW) continue ;;
				esac
			fi
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
#
# ...and now for translations kept in po files....
#
cd po
IGNORE="pot README"
for DIRECTORY in * ; do
	for i in $IGNORE ; do
		if [ "$DIRECTORY" = "$i" ] ; then
			DIRECTORY=""
			break
		fi
	done
	if [ "$DIRECTORY" = "" ] ; then
		continue
	else
		for FORMAT in pdf html ; do
			if [ $FORMAT = pdf ] ; then
				# Some languages are unsupported in PDF
				case $DIRECTORY in
					el|ja|vi|zh_CN|zh_TW) continue ;;
				esac
			fi
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
	rm -f $JOB_TEMPLATES $PROJECT_JOBS $CLEANUP
	exit 1
elif [ -s $CLEANUP ] ; then
	echo
	echo "Warning: some jobs exist which should be deleted, run these commands to clean up:"
	echo
	cat $CLEANUP
	echo
	echo "Jobs need to be deleted from job-cfg/d-i.yaml first, before deleting them with jenkins-jobs, cause else they will be recreated and then builds will be attempted, which will fail and cause notifications..."
else
	echo "Everything ok."
fi
rm -f $CLEANUP
echo
