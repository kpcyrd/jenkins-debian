#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# FIXME: email2irc still needs cleanup / documentation
#
LOGFILE=/var/lib/jenkins/email_log

HEADER=true
VALID_MAIL=false
FIRST_LINE=""
while read line ; do
	if [ "$HEADER" == "true" ] ; then
		if [[ $line =~ ^$ ]] ; then
			HEADER=false
		fi
		if [[ $line =~ ^(From: jenkins@jenkins.debian.net) ]] ; then
			VALID_MAIL=true
		fi
		if [[ $line =~ ^(Subject: .*) ]] ; then
			SUBJECT=${line:9}
		fi
		if [[ $line =~ ^(To: .*) ]] ; then
			echo $line >> $LOGFILE
			CHANNEL=$(echo $line | cut -d "+" -f2| cut -d "@" -f1)
			echo "CHANNEL = $CHANNEL" >> $LOGFILE
		fi
		if [[ $line =~ ^(X-Jenkins-Job: .*) ]] ; then
			JENKINS_JOB=${line:15}
		fi
	fi
	if [ "$HEADER" == "false" ] && [ -z "$FIRST_LINE" ] ; then
		FIRST_LINE=$line
	fi

done
if [ -z $JENKINS_JOB ] ; then
	VALID_MAIL=false
fi	

if [ "$VALID_MAIL" == "true" ] ; then
	echo -e "----------\nvalid email\n-----------" >> $LOGFILE
	echo $JENKINS_JOB | cut -d ":" -f1 >> $LOGFILE
	SUBJECT=$(echo $SUBJECT | cut -d ":" -f1)
	echo $SUBJECT >> $LOGFILE
	echo $FIRST_LINE >> $LOGFILE
	if [ ! -z $CHANNEL ] ; then
		echo "#$CHANNEL: $SUBJECT. $FIRST_LINE" >> $LOGFILE
		#MESSAGE=$(echo "$SUBJECT. $FIRST_LINE" | colorit -c /etc/colorit.conf )
		MESSAGE="$JENKINS_JOB: $SUBJECT. $FIRST_LINE"
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE" && echo "kgb informed successfully." >> $LOGFILE
		echo >> $LOGFILE
	else
		echo "But no irc channel detected." >> $LOGFILE
	fi
else
	echo -e "----------\nbad luck\n-----------" >> $LOGFILE
fi

