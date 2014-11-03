#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# called by ~jenkins/.procmailrc
# to turn jenkins email notifications into irc announcements with kgb
# see http://kgb.alioth.debian.org/
#
LOGFILE=/var/log/jenkins/email.log
# FIXME: add logrotate rule for /var/log/jenkins/email.log

debug123() {
	if $DEBUG ; then
		echo "Debug: $1 $2 $3" >> $LOGFILE
	fi
}

#
# parse email headers to check if they come from jenkins
#
HEADER=true
VALID_MAIL=false
MY_LINE=""
while read line ; do
	if [ "$HEADER" == "true" ] ; then
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
			NEXT=read line
			if [ "${NEXT:1}" = " " ] ; then
				SUBJECT="${SUBJECT}${NEXT}"
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
	DEBUG=true
	# catch first line of email body (to send to IRC later)
	if [ "$HEADER" == "false" ] && [ -z "$MY_LINE" ] ; then
		MY_LINE=$line
		debug123 "#1" MY_LINE $MY_LINE
		# if this is a multipart email it comes from the email extension plugin
		if [ "${line:0:7}" = "------=" ] || [ "${line:0:9}" = "Content-T" ] ; then
			debug123 "#2" line $line
			MY_LINE=""
		else
			debug123 "#3" line $line
			MY_LINE=$(echo $line | tr -d \< | tr -d \> | cut -d " " -f1-2)
			debug123 "#4" MY_LINE $MY_LINE
		fi
	fi
	DEBUG=false
done
# check that it's a valid job
if [ -z $JENKINS_JOB ] ; then
	VALID_MAIL=false
fi	
debug123 "#5" MY_LINE $MY_LINE

# only send notifications for valid emails
if [ "$VALID_MAIL" == "true" ] ; then
	echo -e "----------\nvalid email\n-----------" >> $LOGFILE
	date >> $LOGFILE
	echo "Job:     $JENKINS_JOB" >> $LOGFILE
	echo "Subject: $SUBJECT" >> $LOGFILE
	echo "My line: $MY_LINE" >> $LOGFILE
	# only notify if there is a channel to notify
	if [ ! -z $CHANNEL ] ; then
		# log message
		echo "#$CHANNEL: $SUBJECT. $MY_LINE" >> $LOGFILE
		MESSAGE="$SUBJECT. $MY_LINE"
		# notify kgb
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE" && echo "kgb informed successfully." >> $LOGFILE
		echo >> $LOGFILE
	else
		echo "But no irc channel detected." >> $LOGFILE
	fi
else
	echo -e "----------\nbad luck\n-----------" >> $LOGFILE
fi

