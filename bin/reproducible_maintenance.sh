#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

DIRTY=false
REP_RESULTS=/srv/reproducible-results

# backup db
if [ "$HOSTNAME" = "jenkins" ] ; then
	echo "$(date -u) - backup db and update public copy."
	# prepare backup
	mkdir -p $REP_RESULTS/backup
	cd $REP_RESULTS/backup

	# keep 30 days and the 1st of the month
	DAY=(date -d "30 day ago" '+%d')
	DATE=$(date -d "30 day ago" '+%Y-%m-%d')
	if [ "$DAY" != "01" ] &&  [ -f reproducible_$DATE.db.xz ] ; then
		rm -f reproducible_$DATE.db.xz
	fi

	# actually do the backup
	DATE=$(date '+%Y-%m-%d')
	if [ ! -f reproducible_$DATE.db.xz ] ; then
		cp -v $PACKAGES_DB .
		DATE=$(date '+%Y-%m-%d')
		mv -v reproducible.db reproducible_$DATE.db
		xz reproducible_$DATE.db
	fi

	# provide copy for external backups
	cp -v $PACKAGES_DB $BASE/
fi

echo "$(date -u) - updating the schroots and pbuilder now..."
set +e
ARCH=$(dpkg --print-architecture)
for s in $SUITES ; do
	if [ "$(hostname)" = "jenkins" ] ; then
		echo "$(date -u) - nothing to do on $(hostname -f)..."
		break
	fi
	if [ "$ARCH" = "armhf" ] && [ "$s" != "unstable" ] ; then
		continue
	fi
	#
	# schroot update
	#
	echo "$(date -u) - updating the $s/$ARCH schroot now."
	for i in 1 2 3 ; do
		schroot --directory /root -u root -c source:jenkins-reproducible-$s -- apt-get update
		RESULT=$?
		if [ $RESULT -eq 1 ] ; then
			# sleep 31-100 secs
			echo "Sleeping some time... (to workaround network problems like 'Hash Sum mismatch'...)"
			/bin/sleep $(echo "scale=1 ; ($(shuf -i 1-700 -n 1)/10)+30" | bc )
			echo "$(date -u) - Retrying to update the $s/$ARCH schroot."
		elif [ $RESULT -eq 0 ] ; then
			continue
		fi
	done
	if [ $RESULT -eq 1 ] ; then
		echo "Warning: failed to update the $s/$ARCH schroot."
		DIRTY=true
	fi
	#
	# pbuilder update
	#
	echo "$(date -u) - updating pbuilder for $s/$ARCH now."
	# use host apt proxy configuration for pbuilder
	if [ ! -z "$http_proxy" ] ; then
		pbuilder_http_proxy="--http-proxy $http_proxy"
	fi
	for i in 1 2 3 ; do
		sudo pbuilder --update $pbuilder_http_proxy --basetgz /var/cache/pbuilder/$s-reproducible-base.tgz
		RESULT=$?
		if [ $RESULT -eq 1 ] ; then
			# sleep 31-100 secs
			echo "Sleeping some time... (to workaround network problems like 'Hash Sum mismatch'...)"
			/bin/sleep $(echo "scale=1 ; ($(shuf -i 1-700 -n 1)/10)+30" | bc )
			echo "$(date -u) - Retrying to update pbuilder for $s/$ARCH."
		elif [ $RESULT -eq 0 ] ; then
			continue
		fi
	done
	if [ $RESULT -eq 1 ] ; then
		echo "Warning: failed to update pbuilder for $s/$ARCH."
		DIRTY=true
	fi
done
set -e

# delete old temp directories
echo "$(date -u) - Deleting old temp directories."
OLDSTUFF=$(find $REP_RESULTS -maxdepth 1 -type d -name "tmp.*" -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Old temp directories found in $REP_RESULTS"
	find $REP_RESULTS -maxdepth 1 -type d -name "tmp.*" -mtime +2 -exec rm -rv {} \;
	echo "These old directories have been deleted."
	echo
	DIRTY=true
fi

# remove old and unused schroot sessions
echo "$(date -u) - Removing unused schroot sessions."
ps fax|grep -v grep |grep schroot || for i in $(schroot --all-sessions -l ) ; do ps fax|grep -v grep |grep schroot || schroot -e -c $i ; done
# to explain this:
# first, check if no process using "schroot" is running...
# then loop through all schroot sessions
# for each session
# check that schroot is still not run, and then, delete the session

# find old schroots
echo "$(date -u) - Removing old schroots."
OLDSTUFF=$(find /schroots/ -maxdepth 1 -type d -regextype posix-extended -regex "/schroots/reproducible-.*-[0-9]{1,5}" -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Old schroots found in /schroots, which will be deleted:"
	find /schroots/ -maxdepth 1 -type d -regextype posix-extended -regex "/schroots/reproducible-.*-[0-9]{1,5}" -mtime +2 -exec sudo rm -rf --one-file-system {} \;
	echo "$OLDSTUFF"
	OLDSTUFF=$(find /schroots/ -maxdepth 1 -type d -regextype posix-extended -regex "/schroots/reproducible-.*-[0-9]{1,5}" -mtime +2 -exec ls -lad {} \;)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo
		echo "Warning: Tried, but failed to delete these:"
		echo "$OLDSTUFF"
		echo "Manual cleanup needed!"
	fi
	echo
	DIRTY=true
fi

if [ "$HOSTNAME" = "jenkins" ] ; then
	#
	# find failed builds due to network problems and reschedule them
	#
	# only grep through the last 5h (300 minutes) of builds...
	# (ignore "*None.rbuild.log" because these are build which were just started)
	# this job runs every 4h
	echo "$(date -u) - Rescheduling failed builds."
	FAILED_BUILDS=$(find $BASE/rbuild -type f ! -name "*None.rbuild.log" ! -mmin +300 -exec zgrep -l -E 'E: Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway)' {} \; || true)
	if [ ! -z "$FAILED_BUILDS" ] ; then
		echo
		echo "The following builds have failed due to network problems and will be rescheduled now:"
		echo "$FAILED_BUILDS"
		echo
		echo "Rescheduling packages: "
		REQUESTER="jenkins maintenance job"
		REASON="maintenance reschedule: reschedule builds which failed due to network errors"
		for SUITE in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f8 | sort -u) ; do
			for ARCH in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f9 | sort -u) ; do
				if [ "$ARCH" = "armhf" ] && [ "$SUITE" != "unstable" ] ; then
					continue
				fi
				CANDIDATES=$(for PKG in $(echo $FAILED_BUILDS | sed "s# #\n#g" | grep "/$SUITE/$ARCH/" | cut -d "/" -f10 | cut -d "_" -f1) ; do echo "$PKG" ; done)
				# double check those builds actually failed
				TO_SCHEDULE=""
				for pkg in $CANDIDATES ; do
					QUERY="SELECT s.name FROM sources AS s JOIN results AS r ON r.package_id=s.id
						   WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND (r.status='FTBFS' OR r.status='depwait') AND s.name='$pkg'"
					TO_SCHEDULE=${TO_SCHEDULE:+"$TO_SCHEDULE "}$(sqlite3 -init $INIT $PACKAGES_DB "$QUERY")
				done
				schedule_packages $TO_SCHEDULE
			done
		done
		DIRTY=true
	fi

	#
	# find packages which build didnt end correctly
	#
	echo "$(date -u) - Rescheduling builds which didn't end correctly."
	QUERY="
		SELECT s.id, s.name, p.date_scheduled, p.date_build_started
			FROM schedule AS p JOIN sources AS s ON p.package_id=s.id
			WHERE p.date_scheduled != ''
			AND p.date_build_started != ''
			AND p.date_build_started < datetime('now', '-36 hours')
			ORDER BY p.date_scheduled
		"
	PACKAGES=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXXX)
	sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed." 
	if grep -q '|' $PACKAGES ; then
		echo
		echo "Packages found where the build was started more than 36h ago:"
		printf ".width 0 25 \n $QUERY ; " | sqlite3 -init $INIT -header -column ${PACKAGES_DB} 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
		echo
		for PKG in $(cat $PACKAGES | cut -d "|" -f1) ; do
			echo "sqlite3 ${PACKAGES_DB}  \"DELETE FROM schedule WHERE package_id = '$PKG';\""
			sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id = '$PKG';"
		done
		echo "Packages have been removed from scheduling."
		echo
		DIRTY=true
	fi
	rm $PACKAGES

	#
	# find packages which have been removed from the archive
	#
	echo "$(date -u) - Looking for packages which have been removed from the archive."
	PACKAGES=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXX)
	QUERY="SELECT name, suite, architecture FROM removed_packages
			LIMIT 25"
	sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
	if grep -q '|' $PACKAGES ; then
		DIRTY=true
		echo
		echo "Found files relative to old packages, no more in the archive:"
		echo "Removing these removed packages from database:"
		printf ".width 25 12 \n $QUERY ;" | sqlite3 -init $INIT -header -column ${PACKAGES_DB} 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
		echo
		for pkg in $(cat $PACKAGES) ; do
			PKGNAME=$(echo "$pkg" | cut -d '|' -f 1)
			SUITE=$(echo "$pkg" | cut -d '|' -f 2)
			ARCH=$(echo "$pkg" | cut -d '|' -f 3)
			QUERY="DELETE FROM removed_packages
				WHERE name='$PKGNAME' AND suite='$SUITE' AND architecture='$ARCH'"
			sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY"
			cd $BASE
			find rb-pkg/$SUITE/$ARCH rbuild/$SUITE/$ARCH dbd/$SUITE/$ARCH dbdtxt/$SUITE/$ARCH buildinfo/$SUITE/$ARCH logs/$SUITE/$ARCH logdiffs/$SUITE/$Arch -name "${PKGNAME}_*" | xargs -r rm -v || echo "Warning: couldn't delete old files from ${PKGNAME} in $SUITE/$ARCH"
		done
		cd - > /dev/null
	fi
	rm $PACKAGES

	#
	# delete jenkins html logs from reproducible_builder_* jobs as they are mostly redundant
	# (they only provide the extended value of parsed console output, which we dont need here.)
	#
	OLDSTUFF=$(find /var/lib/jenkins/jobs/reproducible_builder_* -maxdepth 3 -mtime +0 -name log_content.html  -exec rm -v {} \; | wc -l)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo
		echo "Removed $OLDSTUFF jenkins html logs."
		echo
	fi
fi

# find+terminate processes which should not be there
echo "$(date -u) - Looking for processes which should not be there."
HAYSTACK=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXX)
RESULT=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXX)
TOKILL=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXX)
PBUIDS="1234 1111 2222"
ps axo pid,user,size,pcpu,cmd > $HAYSTACK
for i in $PBUIDS ; do
	for PROCESS in $(pgrep -u $i -P 1 || true) ; do
		# faked-sysv comes and goes...
		grep ^$PROCESS $HAYSTACK | grep -v faked-sysv >> $RESULT 2> /dev/null || true
	done
done
if [ -s $RESULT ] ; then
	for PROCESS in $(cat $RESULT | cut -d " " -f1 | xargs echo) ; do
		AGE=$(ps -p $PROCESS -o etimes= || echo 0)
		# a single build may only take half a day, so...
		if [ $AGE -gt $(( 12*60*60 )) ] ; then
			echo "$PROCESS" >> $TOKILL
		fi
	done
	if [ -s $TOKILL ] ; then
		DIRTY=true
		PSCALL=""
		echo
		echo "Info: processes found which should not be there, killing them now:"
		for PROCESS in $(cat $TOKILL) ; do
			PSCALL=${PSCALL:+"$PSCALL,"}"$PROCESS"
		done
		ps -F -p $PSCALL
		echo
		for PROCESS in $(cat $TOKILL) ; do
			sudo kill -9 $PROCESS 2>&1
			echo "'kill -9 $PROCESS' done."
		done
		echo
	fi
fi
rm $HAYSTACK $RESULT $TOKILL
# There are naughty processes spawning childs and leaving them to their grandparents
PSCALL=""
for i in $PBUIDS ; do
	for p in $(pgrep -u $i) ; do
		AGE=$(ps -p $p -o etimes= || echo 0)
		# let's be generous and consider 14 hours here...
		if [ $AGE -gt $(( 14*60*60 )) ] ; then
			PSCALL=${PSCALL:+"$PSCALL,"}"$p"
		fi
	done
done
if [ ! -z "$PSCALL" ] ; then
	echo -e "Warning: processes found which should not be there, please fix up manually:"
	ps -F -p "$PSCALL"
	echo
fi


# remove lockfiles older than 2 days
echo "$(date -u) - Checking for lockfiles older than 2 days."
LOCKFILES=$(find /tmp/reproducible-lockfile-* -maxdepth 1 -type f -mtime +2 -exec ls -lad {} \; 2>/dev/null|| true)
if [ ! -z "$LOCKFILES" ] ; then
	echo
	echo "Removed old lockfiles:"
	find /tmp/reproducible-lockfile-* -maxdepth 1 -type f -mtime +2 -exec rm -rv {} \;
	echo
fi


# remove artifacts older than 3 days
echo "$(date -u) - Checking for artifacts older than 3 days."
ARTIFACTS=$(find $BASE/artifacts/* -maxdepth 1 -type d -mtime +3 -exec ls -lad {} \; 2>/dev/null|| true)
if [ ! -z "$ARTIFACTS" ] ; then
	echo
	echo "Removed old artifacts:"
	find $BASE/artifacts/* -maxdepth 1 -type d -mtime +3 -exec rm -rv {} \;
	echo
fi

# find + chmod files with bad permissions
echo "$(date -u) - Checking for files with bad permissions."
BADPERMS=$(find $BASE/{buildinfo,dbd,rbuild,artifacts,unstable,experimental,testing,rb-pkg} ! -perm 644 -type f 2>/dev/null|| true)
if [ ! -z "$BADPERMS" ] ; then
    DIRTY=true
    echo
    echo "Warning: Found files with bad permissions (!=644):"
    echo "Please fix permission manually"
    echo "$BADPERMS" | xargs echo chmod -v 644
    echo
fi

if ! $DIRTY ; then
	echo "$(date -u ) - Everything seems to be fine."
	echo
fi

echo "$(date -u) - the end."


