#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# create dirs for results
mkdir -p /var/lib/jenkins/userContent/dbd/
mkdir -p /var/lib/jenkins/userContent/rbuild/
mkdir -p /var/lib/jenkins/userContent/buildinfo/

cleanup_all() {
	rm -r $TMPDIR $TMPCFG
}

cleanup_userContent() {
	rm -f /var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_*.rbuild.log > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/dbd/${SRCPACKAGE}_*.debbindiff.html > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/buildinfo/${SRCPACKAGE}_*.buildinfo > /dev/null 2>&1
}

update_db_and_html() {
	# unmark build as properly finished
	sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id='$SRCPKGID';"
	set +x
	gen_packages_html $SRCPACKAGE
	echo
	echo "Successfully updated the database and updated $REPRODUCIBLE_URL/rb-pkg/$SRCPACKAGE.html"
	echo
}

call_debbindiff() {
	LOGFILE=$(ls ${SRCPACKAGE}_${EVERSION}.dsc)
	LOGFILE=$(echo ${LOGFILE%.dsc}.debbindiff.html)
	BUILDINFO=${SRCPACKAGE}_${EVERSION}_amd64.buildinfo
	# the schroot for debbindiff gets updated once a day. wait patiently if that's the case
	if [ -f $DBDCHROOT_WRITELOCK ] || [ -f $DBDCHROOT_READLOCK ] ; then
		for i in $(seq 0 100) ; do
			sleep 15
			echo "sleeping 15s, debbindiff schroot is locked."
			if [ ! -f $DBDCHROOT_WRITELOCK ] && [ ! -f $DBDCHROOT_READLOCK ] ; then
				break
			fi
		done
		if [ -f $DBDCHROOT_WRITELOCK ] || [ -f $DBDCHROOT_READLOCK ]  ; then
			echo "Warning: lock $DBDCHROOT_WRITELOCK or [ -f $DBDCHROOT_READLOCK ] still exists, exiting."
			exit 1
		fi
	else
		# we create (more) read-lock(s) but stop on write locks...
		# write locks are only done by the schroot setup job
		touch $DBDCHROOT_READLOCK
	fi
	echo "$(date) - $(schroot --directory /tmp -c source:jenkins-reproducible-sid-debbindiff debbindiff -- --version) will be used to compare the two builds now." | tee -a ${RBUILDLOG}
	( timeout 15m schroot --directory /tmp -c source:jenkins-reproducible-sid-debbindiff debbindiff -- --html $TMPDIR/${LOGFILE} $TMPDIR/b1/${SRCPACKAGE}_${EVERSION}_amd64.changes $TMPDIR/b2/${SRCPACKAGE}_${EVERSION}_amd64.changes ) 2>&1 >> ${RBUILDLOG}
	RESULT=$?
	set +x
	set -e
	rm -f $DBDCHROOT_READLOCK
	echo | tee -a ${RBUILDLOG}
	if [ $RESULT -eq 124 ] ; then
		echo "$(date) - debbindiff was killed after running into timeout... maybe there is still $REPRODUCIBLE_URL/dbd/${LOGFILE}" | tee -a ${RBUILDLOG}
		if [ ! -s ./${LOGFILE} ] ; then
			echo "$(date) - debbindiff produced no output and was killed after running into timeout..." >> ${LOGFILE}
		fi
	elif [ $RESULT -eq 1 ] ; then
		DEBBINDIFFOUT="debbindiff found issues, please investigate $REPRODUCIBLE_URL/dbd/${LOGFILE}"
	elif [ $RESULT -eq 2 ] ; then
		DEBBINDIFFOUT="debbindiff had trouble comparing the two builds. Please investigate $REPRODUCIBLE_URL/rbuild/${SRCPACKAGE}_${EVERSION}.rbuild.log"
	fi
	if [ $RESULT -eq 0 ] && [ ! -f ./${LOGFILE} ] && [ -f b1/${BUILDINFO} ] ; then
		cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/ > /dev/null 2>&1
		figlet ${SRCPACKAGE}
		echo
		echo "debbindiff found no differences in the changes files, and a .buildinfo file also exist." | tee -a ${RBUILDLOG}
		echo "${SRCPACKAGE} built successfully and reproducibly." | tee -a ${RBUILDLOG}
		# FIXME calculate build_duration and push it to the db
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('${SRCPKGID}', '${VERSION}', 'reproducible',  '$DATE')"
		update_db_and_html
	else
		echo | tee -a ${RBUILDLOG}
		echo -n "$(date) - ${SRCPACKAGE}/${SUITE} failed to build reproducibly " | tee -a ${RBUILDLOG}
		cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/ > /dev/null 2>&1 || true
		if [ -f ./${LOGFILE} ] ; then
			echo -n ", $DEBBINDIFFOUT" | tee -a ${RBUILDLOG}
			mv ./${LOGFILE} /var/lib/jenkins/userContent/dbd/
		else
			echo -n ", debbindiff produced no output (which is strange)"
		fi
		if [ ! -f b1/${BUILDINFO} ] ; then
			echo " and a .buildinfo file is missing." | tee -a ${RBUILDLOG}
		else
			echo "." | tee -a ${RBUILDLOG}
		fi
		OLD_STATUS=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT status FROM results WHERE package_id='${SRCPKGID}'")
		if [ "${OLD_STATUS}" = "reproducible" ]; then
			MESSAGE="${SRCPACKAGE}: status changed from reproducible -> unreproducible. ${REPRODUCIBLE_URL}/${SRCPACKAGE}"
			echo "\n$MESSAGE" | tee -a ${RBUILDLOG}
			#kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE" || true # don't fail the whole job
		fi
		# FIXME calculate build_duration and push it to the db
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('${SRCPKGID}', '${VERSION}', 'unreproducible', '$DATE')"
		update_db_and_html
	fi
}

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)
TMPCFG=$(mktemp -t pbuilderrc_XXXX)
trap cleanup_all INT TERM EXIT
cd $TMPDIR

SQL_SUITES=""
for i in $SUITES ; do
	if [ -n "$SQL_SUITES" ] ; then
		SQL_SUITES="$SQL_SUITES, '$i'"
	else
		SQL_SUITES="('$i'"
	fi
done
SQL_SUITES="$SQL_SUITES)"

RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT s.suite, s.id, s.name, sch.date_scheduled FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id WHERE sch.date_build_started = '' AND s.suite IN $SQL_SUITES ORDER BY date_scheduled LIMIT 1")
if [ -z "$RESULT" ] ; then
	echo "No packages scheduled, sleeping 30m."
	sleep 30m
else
	set +x
	SUITE=$(echo $RESULT|cut -d "|" -f1)
	SRCPKGID=$(echo $RESULT|cut -d "|" -f2)
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f3)
	SCHEDULED_DATE=$(echo $RESULT|cut -d "|" -f4)
	echo "============================================================================="
	echo "Trying to build ${SRCPACKAGE}/${SUITE} reproducibly now."
	echo "============================================================================="
	set -x
	DATE=$(date +'%Y-%m-%d %H:%M')
	# mark build attempt
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO schedule (package_id, date_scheduled, date_build_started) VALUES ('$SRCPKGID', '$SCHEDULED_DATE', '$DATE');"

	RBUILDLOG=/var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_None.rbuild.log
	echo "Starting to build ${SRCPACKAGE}/${SUITE} on $DATE" | tee ${RBUILDLOG}
	echo "The jenkins build log is/was available at $BUILD_URL/console" | tee -a ${RBUILDLOG}
	set +e
	schroot --directory $PWD -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
	RESULT=$?
	if [ $RESULT != 0 ] ; then
		# sometimes apt-get cannot download a package for whatever reason.
		# if so, wait some time and try again. only if that fails, give up.
		echo "Download of ${SRCPACKAGE}/${SUITE} sources failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		echo "Sleeping 5m before re-trying..." | tee -a ${RBUILDLOG}
		sleep 5m
		schroot --directory $PWD -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
		RESULT=$?
	fi
	if [ $RESULT != 0 ] ; then
		echo "Warning: Download of ${SRCPACKAGE}/${SUITE} sources failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		# FIXME calculate build_duration and push it to the db
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('${SRCPKGID}', 'None', '404', '$DATE')"
		set +x
		echo "Warning: Maybe there was a network problem, or ${SRCPACKAGE} is not a source package, or was removed or renamed. Please investigate." | tee -a ${RBUILDLOG}
		update_db_and_html
		exit 0
	else
		set -e
		VERSION=$(grep "^Version: " ${SRCPACKAGE}_*.dsc| head -1 | egrep -v '(GnuPG v|GnuPG/MacGPG2)' | cut -d " " -f2-)
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
		if ! $SUITABLE ; then
			set -x
			# FIXME calculate build_duration and push it to the db
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('${SRCPKGID}', '${VERSION}', 'not for us', '$DATE')"
			set +x
			echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$(echo "${ARCHITECTURES}" | xargs echo )\" and thus was skipped." | tee -a ${RBUILDLOG}
			update_db_and_html
			exit 0
		fi
		set +e
		set -x
		NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
		FTBFS=1
		TMPLOG=$(mktemp)
		printf "BUILDUSERID=1111\nBUILDUSERNAME=pbuilder1\n" > $TMPCFG
		( timeout 12h nice ionice -c 3 sudo \
		  DEB_BUILD_OPTIONS="parallel=$NUM_CPU" \
		  TZ="/usr/share/zoneinfo/Etc/GMT+12" \
		  pbuilder --build --configfile $TMPCFG --debbuildopts "-b" --basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz --distribution ${SUITE} ${SRCPACKAGE}_*.dsc
		) 2>&1 | tee ${TMPLOG}
		set +x
		if [ -f /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes ] ; then
			mkdir b1 b2
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes b1
			# the .changes file might not contain the original sources archive
			# so first delete files from .dsc, then from .changes file
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}.dsc
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes
			echo "============================================================================="
			echo "Re-building ${SRCPACKAGE}/${SUITE} now."
			echo "============================================================================="
			set -x
			printf "BUILDUSERID=2222\nBUILDUSERNAME=pbuilder2\n" > $TMPCFG
			( timeout 12h nice ionice -c 3 sudo \
			  DEB_BUILD_OPTIONS="parallel=$NUM_CPU" \
			  TZ="/usr/share/zoneinfo/Etc/GMT-14" \
			  LANG="fr_CH.UTF-8" \
			  LC_ALL="fr_CH.UTF-8" \
			  unshare --uts -- /usr/sbin/pbuilder --build --configfile $TMPCFG --hookdir /etc/pbuilder/rebuild-hooks \
			    --debbuildopts "-b" --basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz --distribution ${SUITE} ${SRCPACKAGE}_${EVERSION}.dsc
			) 2>&1 | tee -a ${RBUILDLOG}
			set +x
			if [ -f /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes ] ; then
				FTBFS=0
				dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes b2
				# and again (see comment 5 lines above)
				sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}.dsc
				sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes
				cat b1/${SRCPACKAGE}_${EVERSION}_amd64.changes | tee -a ${RBUILDLOG}
				call_debbindiff
			else
				echo "The second build failed, even though the first build was successful." | tee -a ${RBUILDLOG}
			fi
		else
			cat ${TMPLOG} >> ${RBUILDLOG}
		fi
		rm ${TMPLOG}
		if [ $FTBFS -eq 1 ] ; then
			set +x
			echo "${SRCPACKAGE} failed to build from source."
			# FIXME calculate build_duration and push it to the db
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('${SRCPKGID}', '${VERSION}', 'FTBFS', '$DATE')"
			update_db_and_html
		fi
	fi

fi
cd ..
cleanup_all
trap - INT TERM EXIT

