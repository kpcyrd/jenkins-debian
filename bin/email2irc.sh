#!/bin/bash

# Copyright 2012-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# from IRC:
#<h01ger> i think email2irc.sh should be thrown away and replaced
#	  with a proper python or perl script. parsing email headers
#	  with shell is insane.
#<h01ger> but it really should just be rewritten from scratch
#<h01ger> using something which has libraries to parse emails…


#
# called by ~jenkins/.procmailrc
# to turn jenkins email notifications into irc announcements with kgb
# see http://kgb.alioth.debian.org/
#
LOGFILE=/var/log/jenkins/email.log

debug123() {
	if $DEBUG ; then
		echo "Debug: $1 $2 $3" >> $LOGFILE
	fi
}

#
# parse email headers to check if they come from jenkins
#
DEBUG=false
HEADER=true
VALID_MAIL=false
MY_LINE=""
MY_2ND_LINE=""
while read -r line ; do
	if [ "$HEADER" = "true" ] ; then
		# check if email header ends
		if [[ $line =~ ^$ ]] ; then
			HEADER=false
		fi
		# valid From: line?
		if [[ $line =~ ^(From: jenkins@jenkins.debian.net) ]] ; then
			VALID_MAIL=true
		fi
		# catch Subject (to send to IRC later)
		if [[ $line =~ ^(Subject: .*) ]] ; then
			SUBJECT=${line:9}
			# the email-ext plugin sometimes sends multi line subjects..
			read -r NEXT
			if [ "${NEXT:0:1}" = " " ] || [ "${NEXT:0:1}" = $'\t' ]; then
				SUBJECT="${SUBJECT}${NEXT:1}"
			fi
		fi
		# determine the channel to send notifications to
		# by parsing the To: line
		if [[ $line =~ ^(To: .*) ]] ; then
			echo $line >> $LOGFILE
			CHANNEL=$(echo $line | cut -d "+" -f2| cut -d "@" -f1)
			echo "CHANNEL = $CHANNEL" >> $LOGFILE
		fi
		# check if it's a valid jenkins job
		if [[ $line =~ ^(X-Jenkins-Job: .*) ]] ; then
			JENKINS_JOB=${line:15}
		fi
	fi
	# catch first line of email body (to send to IRC later)
	if [ "$HEADER" = "false" ] && [ -z "$MY_LINE" ] ; then
		MY_LINE=$line
		debug123 "#1" MY_LINE $MY_LINE
		if [ -z "$MY_2ND_LINE" ] ; then
			# if this is a multipart email it comes from the email extension plugin
			if [ "${line:0:7}" = "------=" ] || [ "${line:0:9}" = "Content-T" ] ; then
				debug123 "#2" line $line
				MY_LINE=""
			else
				debug123 "#3" line $line
				MY_LINE=$(echo $line | tr -d \< | tr -d \> | cut -d " " -f1-2)
				debug123 "#4" MY_LINE $MY_LINE
			fi
			# deal with quoted-printable continuation lines: 1st line/time
			# if $MY_LINE ends with '=', then append the next line to $MY_LINE,
			# changing the '=' to a single space.
			if [[ $MY_LINE =~ ^(.*)=$ ]] ; then
				MY_2ND_LINE="$MY_LINE"
				MY_LINE=""
			fi
		else
			# deal with quoted-printable continuation lines: 2nd line/time
			# if $MY_LINE ends with '=', then append the next line to $MY_LINE,
			# changing the '=' to a single space.
			MY_2ND_LINE=$(echo $MY_2ND_LINE | sed -s 's#=$##')
			MY_LINE="${MY_2ND_LINE}$MY_LINE"
			debug123 "#5" MY_LINE $MY_LINE
			debug123 "#6" MY_2ND_LINE $MY_2ND_LINE
		fi
	fi
done
# check that it's a valid job
if [ -z $JENKINS_JOB ] ; then
	VALID_MAIL=false
fi	
debug123 "#7" MY_LINE $MY_LINE
# remove bogus noise
MY_LINE=$(echo $MY_LINE | sed -s "s#------------------------------------------##g")
debug123 "#8" MY_LINE $MY_LINE

# only send notifications for valid emails
if [ "$VALID_MAIL" = "true" ] ; then
	echo -e "----------\nvalid email\n-----------" >> $LOGFILE
	date >> $LOGFILE
	echo "Job:     $JENKINS_JOB" >> $LOGFILE
	echo "Subject: $SUBJECT" >> $LOGFILE
	echo "My line: $MY_LINE" >> $LOGFILE
	# only notify if there is a channel to notify
	if [ ! -z $CHANNEL ] ; then
		# format message
		MESSAGE="$(echo $SUBJECT | cut -d ':' -f1) $MY_LINE"
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Failure#Failed #') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Build failed in Jenkins#Failed #') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Jenkins build is back to normal#Fixed #') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Jenkins build is back to stable#Fixed #') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Jenkins build became#Became#') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Jenkins build is unstable#Unstable#') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Jenkins build is still unstable#Still unstable#') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#^Still Failing#Still failing#') "
		MESSAGE="$(echo $MESSAGE | sed -s 's# See # #') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#Changes:##') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#/console$##') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#/changes$##') "
		MESSAGE="$(echo $MESSAGE | sed -s 's#display/redirect$##') "
		# log message
		echo "Notified #$CHANNEL with $MESSAGE" >> $LOGFILE
		# notify kgb
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE" && echo "kgb informed successfully." >> $LOGFILE
		echo >> $LOGFILE
	else
		echo "But no irc channel detected." >> $LOGFILE
	fi
else
	echo -e "----------\nbad luck\n-----------" >> $LOGFILE
fi

