#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# create dirs for results
mkdir -p /var/lib/jenkins/userContent/dbd/ /var/lib/jenkins/userContent/buildinfo/ /var/lib/jenkins/userContent/rbuild/

cleanup_all() {
	rm -r $TMPDIR
}

cleanup_userContent() {
	rm -f /var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_*.rbuild.log > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/dbd/${SRCPACKAGE}_*.debbindiff.html > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/buildinfo/${SRCPACKAGE}_*.buildinfo > /dev/null 2>&1
}

unschedule_from_db() {
	# unmark build as properly finished
	sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM sources_scheduled WHERE name = '$SRCPACKAGE';"
}

TMPDIR=$(mktemp --tmpdir=$PWD -d)
trap cleanup_all INT TERM EXIT
cd $TMPDIR
RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT name,date_scheduled FROM sources_scheduled WHERE date_build_started = '' ORDER BY date_scheduled LIMIT 1")
if [ -z "$RESULT" ] ; then
	echo "No packages scheduled, sleeping 30m."
	sleep 30m
else
	set +x
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f1)
	SCHEDULED_DATE=$(echo $RESULT|cut -d "|" -f2)
	echo "============================================================================="
	echo "Trying to build ${SRCPACKAGE} reproducibly now."
	echo "============================================================================="
	set -x
	DATE=$(date +'%Y-%m-%d %H:%M')
	# mark build attempt
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO sources_scheduled VALUES ('$SRCPACKAGE','$SCHEDULED_DATE','$DATE');"

	RBUILDLOG=/var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_None.rbuild.log
	echo "Starting to build ${SRCPACKAGE} on $DATE" | tee ${RBUILDLOG}
	echo "The jenkins build log is/was available at $BUILD_URL/console" | tee -a ${RBUILDLOG}
	# host has only sid in deb-src in sources.list
	set +e
	apt-get source --download-only --only-source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
	RESULT=$?
	if [ $RESULT != 0 ] ; then
		# sometimes apt-get cannot download a package for whatever reason.
		# if so, wait some time and try again. only if that fails, give up.
		echo "Download of ${SRCPACKAGE} sources failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		echo "Sleeping 5m before re-trying..." | tee -a ${RBUILDLOG}
		sleep 5m
		apt-get source --download-only --only-source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
		RESULT=$?
	fi
	if [ $RESULT != 0 ] ; then
		echo "Warning: Download of ${SRCPACKAGE} sources failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"None\", \"404\", \"$DATE\")"
		set +x
		echo "Warning: Maybe there was a network problem, or ${SRCPACKAGE} is not a source package, or was removed or renamed. Please investigate." | tee -a ${RBUILDLOG}
		unschedule_from_db
		exit 0
	else
		set -e
		VERSION=$(grep "^Version: " ${SRCPACKAGE}_*.dsc| egrep -v '(GnuPG v|GnuPG/MacGPG2)' | cut -d " " -f2-)
		# EPOCH_FREE_VERSION was too long
		EVERSION=$(echo $VERSION | cut -d ":" -f2)
		# preserve RBUILDLOG as TMPLOG, then cleanup userContent from previous builds,
		# and then access RBUILDLOG with it's correct name (=eversion)
		TMPLOG=$(mktemp)
		mv ${RBUILDLOG} ${TMPLOG}
		cleanup_userContent
		RBUILDLOG=/var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_${EVERSION}.rbuild.log
		mv ${TMPLOG} ${RBUILDLOG}
		cat ${SRCPACKAGE}_${EVERSION}.dsc | tee -a ${RBUILDLOG}
		# check whether the package is not for us...
		SUITABLE=false
		ARCHITECTURES=$(grep "^Architecture: " ${SRCPACKAGE}_*.dsc| cut -d " " -f2- | sed -s "s# #\n#g" | sort -u)
		set +x
		for ARCH in ${ARCHITECTURES} ; do
			if [ "$ARCH" = "any" ] || [ "$ARCH" = "all" ] || [ "$ARCH" = "amd64" ] || [ "$ARCH" = "linux-any" ] || [ "$ARCH" = "linux-amd64" ] || [ "$ARCH" = "any-amd64" ] ; then
				SUITABLE=true
				break
			fi
		done
		set -x
		if ! $SUITABLE ; then
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"not for us\", \"$DATE\")"
			set +x
			echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$(echo "${ARCHITECTURES}" | xargs echo )\" and thus was skipped." | tee -a ${RBUILDLOG}
			unschedule_from_db
			exit 0
		fi
		set +e
		NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
		( timeout 15m nice ionice -c 3 sudo DEB_BUILD_OPTIONS="parallel=$NUM_CPU" pbuilder --build --debbuildopts "-b" --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid ${SRCPACKAGE}_*.dsc ) 2>&1 | tee -a ${RBUILDLOG}
		if [ -f /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes ] ; then
			mkdir b1 b2
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes b1
			# the .changes file might not contain the original sources archive
			# so first delete files from .dsc, then from .changes file
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}.dsc
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes
			set +x
			echo "============================================================================="
			echo "Re-building ${SRCPACKAGE} now."
			echo "============================================================================="
			set -x
			timeout 12h nice ionice -c 3 sudo DEB_BUILD_OPTIONS="parallel=$NUM_CPU" pbuilder --build --debbuildopts "-b" --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid ${SRCPACKAGE}_${EVERSION}.dsc
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes b2
			# and again (see comment 5 lines above)
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}.dsc
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes
			cat b1/${SRCPACKAGE}_${EVERSION}_amd64.changes | tee -a ${RBUILDLOG}
			LOGFILE=$(ls ${SRCPACKAGE}_${EVERSION}.dsc)
			LOGFILE=$(echo ${LOGFILE%.dsc}.debbindiff.html)
			BUILDINFO=${SRCPACKAGE}_${EVERSION}_amd64.buildinfo
			( timeout 15m /var/lib/jenkins/debbindiff.git/debbindiff.py --html ./${LOGFILE} b1/${SRCPACKAGE}_${EVERSION}_amd64.changes b2/${SRCPACKAGE}_${EVERSION}_amd64.changes ) 2>&1 >> ${RBUILDLOG}
			RESULT=$?
			set -e
			echo | tee -a ${RBUILDLOG}
			if [ $RESULT -eq 124 ] ; then
				echo "$(date) - debbindiff.py was killed after running into timeouot..." | tee -a ${RBUILDLOG}
			elif [ $RESULT -eq 1 ] ; then
				echo "$(date) - debbindiff.py found issues, please investigate $JENKINS_URL/userContent/dbd/${LOGFILE}" | tee -a ${RBUILDLOG}
			fi
			if [ ! -f ./${LOGFILE} ] && [ -f b1/${BUILDINFO} ] ; then
				cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/
				figlet ${SRCPACKAGE}
				echo "debbindiff.py found no differences in the changes files, and a .buildinfo file also exist." | tee -a ${RBUILDLOG}
				echo "${SRCPACKAGE} built successfully and reproducibly." | tee -a ${RBUILDLOG}
				sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"reproducible\",  \"$DATE\")"
				unschedule_from_db
			else
				cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/ || true
				if [ -f ./${LOGFILE} ] ; then
					# FIXME: work around debbindiff not having external CSS support (#764470)
					# should really be fixed in debbindiff and just moved....
					if grep -q "Generated by debbindiff 3" ./${LOGFILE} ; then
						sed '/\<style\>/,/<\/style>/{//!d}' ./${LOGFILE} |grep -v "style>" | sed -s 's#</head>#  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />\n  <link href="../static/style_dbd.css" type="text/css" rel="stylesheet" />\n</head>#' > /var/lib/jenkins/userContent/dbd/${LOGFILE}
					else
						mv ./${LOGFILE} /var/lib/jenkins/userContent/dbd/
					fi
				fi
				sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"unreproducible\", \"$DATE\")"
				unschedule_from_db
				set +x
				echo -n "${SRCPACKAGE} failed to build reproducibly" | tee -a ${RBUILDLOG}
				if [ ! -f b1/${BUILDINFO} ] ; then
					echo "and a .buildinfo file is missing too." | tee -a ${RBUILDLOG}
				else
					echo "." | tee -a ${RBUILDLOG}
				fi
			fi
		else
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"FTBFS\", \"$DATE\")"
			unschedule_from_db
			set +x
			echo "${SRCPACKAGE} failed to build from source."
		fi
	fi

fi
set -x
cd ..
cleanup_all
trap - INT TERM EXIT

