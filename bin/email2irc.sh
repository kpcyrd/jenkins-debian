#!/bin/bash

#
# FIXME: this needs cleanup soo much
#

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
			echo $line >> /var/lib/jenkins/email_log
			CHANNEL=$(echo $line | cut -d "+" -f2| cut -d "@" -f1)
			echo "CHANNEL = $CHANNEL" >> /var/lib/jenkins/email_log
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
	echo -e "----------\nvalid email\n-----------" >> /var/lib/jenkins/email_log
	echo $JENKINS_JOB | cut -d ":" -f1 >> /var/lib/jenkins/email_log
	SUBJECT=$(echo $SUBJECT | cut -d ":" -f1)
	echo $SUBJECT >> /var/lib/jenkins/email_log
	echo $FIRST_LINE >> /var/lib/jenkins/email_log
	if [ ! -z $CHANNEL ] ; then
		echo "#$CHANNEL: $SUBJECT. $FIRST_LINE" >> /var/lib/jenkins/email_log
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$SUBJECT. $FIRST_LINE" && echo "kgb informed successfully." >> /var/lib/jenkins/email_log
		echo >> /var/lib/jenkins/email_log
	else
		echo "But no irc channel detected." >> /var/lib/jenkins/email_log
	fi
else
	echo -e "----------\nbad luck\n-----------" >> /var/lib/jenkins/email_log
fi


