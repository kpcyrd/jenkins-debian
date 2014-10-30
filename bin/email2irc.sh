#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# called by ~jenkins/.procmailrc
# to turn jenkins email notifications into irc announcements with kgb
# see http://kgb.alioth.debian.org/
#
LOGFILE=/var/lib/jenkins/email_log

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
	if [ "$HEADER" == "false" ] && [ -z "$MY_LINE" ] ; then
		MY_LINE=$line
		# if this is a multipart email it comes from the email extension plugin
		if [ "${line:0:5}" = "-----" ] ; then
			read line
			read line
			MY_LINE=$(read line)
			MY_LINE=$(echo $MY_LINE | cut -d " " -f1-2)
		else
			MY_LINE=$(echo $line | tr -d \< | tr -d \>)
		fi
	fi

done
# check that it's a valid job
if [ -z $JENKINS_JOB ] ; then
	VALID_MAIL=false
fi	

# only send notifications for valid emails
if [ "$VALID_MAIL" == "true" ] ; then
	echo -e "----------\nvalid email\n-----------" >> $LOGFILE
	echo $JENKINS_JOB | cut -d ":" -f1 >> $LOGFILE
	echo $SUBJECT >> $LOGFILE
	echo $MY_LINE >> $LOGFILE
	# only notify if there is a channel to notify
	if [ ! -z $CHANNEL ] ; then
		# log message
		echo "#$CHANNEL: $SUBJECT. $MY_LINE" >> $LOGFILE
		MESSAGE="$JENKINS_JOB: $SUBJECT. $MY_LINE"
		# notify kgb
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE" && echo "kgb informed successfully." >> $LOGFILE
		echo >> $LOGFILE
	else
		echo "But no irc channel detected." >> $LOGFILE
	fi
else
	echo -e "----------\nbad luck\n-----------" >> $LOGFILE
fi

