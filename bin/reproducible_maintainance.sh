#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

DIRTY=false

# prepare backup
REP_RESULTS=/srv/reproducible-results
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
cp -v $PACKAGES_DB /var/lib/jenkins/userContent/

# delete old temp directories
OLDSTUFF=$(find $REP_RESULTS -maxdepth 1 -type d -name "tmp.*" -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Warning: old temp directories found in $REP_RESULTS"
	find $REP_RESULTS -maxdepth 1 -type d -name "tmp.*" -mtime +2 -exec rm -rv {} \;
	echo "These old directories have been deleted."
	echo
	DIRTY=true
fi

# find old schroots
OLDSTUFF=$(find /schroots/ -maxdepth 1 -type d -name "reproducible-*-*" -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Warning: old schroots found in /schroots, which have been deleted:"
	find /schroots/ -maxdepth 1 -type d -name "reproducible-*-*" -mtime +2 -exec sudo rm -rf {} \;
	echo "$OLDSTUFF"
	echo
	DIRTY=true
fi

# find and warn about pbuild leftovers
OLDSTUFF=$(find /var/cache/pbuilder/result/ -mtime +1 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	# delete known files
	cd /var/cache/pbuilder/result/
	echo "Attempting file detection..."
	for i in $(find . -maxdepth 1 -mtime +1 -type f -exec basename {} \;) ; do
		case $i in
			stderr|stdout)	rm -v $i
					;;
			seqan-*.bed)	rm -v $i	# leftovers reported in #766741
					;;
			*)		;;
		esac
	done
	cd -
	# report the rest
	OLDSTUFF=$(find /var/cache/pbuilder/result/ -mtime +1 -exec ls -lad {} \;)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo "Warning: old files or directories found in /var/cache/pbuilder/result/"
		echo "$OLDSTUFF"
		echo "Please cleanup manually."
	fi
	echo
	DIRTY=true
fi

# find failed builds due to network problems and reschedule them
# only grep through the last 5h (300 minutes) of builds...
# this job runs every 4h
FAILED_BUILDS=$(find /var/lib/jenkins/userContent/rbuild -type f ! -mmin +300 -exec egrep -l -e "E: Failed to fetch.*Connection failed" -e "E: Failed to fetch.*Size mismatch" {} \;)
if [ ! -z "$FAILED_BUILDS" ] ; then
	echo
	echo "Warning: the following failed builds have been found"
	echo "$FAILED_BUILDS"
	echo
	echo "Rescheduling packages: "
	for SUITE in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f7 | sort -u) ; do
		CANDIDATES=$(for PKG in $(echo $FAILED_BUILDS | sed "s# #\n#g" | grep "/$SUITE/" | cut -d "/" -f9 | cut -d "_" -f1) ; do echo -n "$PKG " ; done)
		check_candidates
		if [ $TOTAL -ne 0 ] ; then
			echo " - in $SUITE: $CANDIDATES"
			schedule_packages $PACKAGE_IDS
		fi
	done
	DIRTY=true
fi

# find+terminate processes which should not be there
HAYSTACK=$(mktemp)
RESULT=$(mktemp)
PBUIDS="1234 1111 2222"
ps axo pid,user,size,pcpu,cmd > $HAYSTACK
for i in $PBUIDS ; do
	for ZOMBIE in $(pgrep -u $i -P 1 || true) ; do
		# faked-sysv comes and goes...
		grep ^$ZOMBIE $HAYSTACK | grep -v faked-sysv >> $RESULT 2> /dev/null || true
	done
done
if [ -s $RESULT ] ; then
	echo
	echo "Warning: processes found which should not be there, killing them now:"
	cat $RESULT
	echo
	ZOMBIES=$(cat $RESULT | cut -d " " -f1 | xargs echo)
	sudo kill -9 $(echo $ZOMBIES)
	echo "'kill -9 $(echo $ZOMBIES)' done."
	echo
	DIRTY=true
fi
rm $HAYSTACK $RESULT

# find packages which build didnt end correctly
QUERY="
	SELECT s.id, s.name, p.date_scheduled, p.date_build_started
		FROM schedule AS p JOIN sources AS s ON p.package_id=s.id
		WHERE p.date_scheduled != ''
		AND p.date_build_started != ''
		AND p.date_build_started < datetime('now', '-36 hours')
		ORDER BY p.date_scheduled
	"
PACKAGES=$(mktemp)
sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed." 
if grep -q '|' $PACKAGES ; then
	echo
	echo "Warning: packages found where the build was started more than 36h ago:"
	echo "pkg_id|name|date_scheduled|date_build_started"
	echo
	cat $PACKAGES
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

# find packages which have been removed from unstable
# commented out for now. This can't be done using the database anymore
QUERY="SELECT source_packages.name FROM source_packages
		WHERE source_packages.name NOT IN
		(SELECT sources.name FROM sources)
	LIMIT 25"
#PACKAGES=$(sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY")
PACKAGES=''
if [ ! -z "$PACKAGES" ] ; then
	echo
	echo "Removing these removed packages from database:"
	echo $PACKAGES
	echo
	QUERY="DELETE FROM source_packages
			WHERE source_packages.name NOT IN
			(SELECT sources.name FROM sources)
		LIMIT 25"
	sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY"
	cd /var/lib/jenkins/userContent
	for i in PACKAGES ; do
		find rb-pkg/ rbuild/ notes/ dbd/ -name "${i}_*" -exec rm -v {} \;
	done
	cd -
fi

# delete jenkins html logs from reproducible_builder_* jobs as they are mostly redundant
# (they only provide the extended value of parsed console output, which we dont need here.)
OLDSTUFF=$(find /var/lib/jenkins/jobs/reproducible_builder_* -maxdepth 3 -mtime +0 -name log_content.html  -exec rm -v {} \; | wc -l)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Removed $OLDSTUFF jenkins html logs."
	echo
fi

if ! $DIRTY ; then
	echo "Everything seems to be fine."
	echo
fi
