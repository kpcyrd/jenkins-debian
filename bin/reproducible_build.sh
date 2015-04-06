#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# support for different architectures (we have actual support only for amd64)
ARCH="amd64"

# sleep 1-12 secs to randomize start times
/bin/sleep $(echo "scale=1 ; $(shuf -i 1-120 -n 1)/10" | bc )

create_results_dirs() {
	mkdir -p /var/lib/jenkins/userContent/dbd/${SUITE}/${ARCH}
	mkdir -p /var/lib/jenkins/userContent/rbuild/${SUITE}/${ARCH}
	mkdir -p /var/lib/jenkins/userContent/buildinfo/${SUITE}/${ARCH}
}

cleanup_all() {
	if [ $SAVE_ARTIFACTS -eq 1 ] || [ $SAVE_ARTIFACTS -eq 3 ] ; then
		local random=$(head /dev/urandom | tr -cd '[:alnum:]'| head -c5)
		local ARTIFACTS="artifacts/r00t-me/${SRCPACKAGE}_${SUITE}_tmp-${random}"
		mkdir -p /var/lib/jenkins/userContent/$ARTIFACTS
		cp -r $TMPDIR/* /var/lib/jenkins/userContent/$ARTIFACTS/
		echo | tee -a ${RBUILDLOG}
		echo "Artifacts from this build are preserved. They will be available for 72h only, so download them now if you want them." | tee -a ${RBUILDLOG}
		echo "WARNING: You shouldn't trust packages you downloaded from this host, they can contain malware or the worst of your fears, packaged nicely in debian format." | tee -a ${RBUILDLOG}
		echo "If you are not afraid facing your fears while helping the world by investigating reproducible build issues, you can download the artifacts from the following location:" | tee -a ${RBUILDLOG}
		URL="https://reproducible.debian.net/$ARTIFACTS/"
		TMPFILE=$(mktemp)
		curl $URL > $TMPFILE 2>/dev/null
		sed -i "s#</table>#<tr><td colspan=\"5\"><a href=\"$REPRODUCIBLE_URL/${SUITE}/${ARCH}/${SRCPACKAGE}\">$REPRODUCIBLE_URL/${SUITE}/${ARCH}/${SRCPACKAGE}</a></td></tr></table>#g" $TMPFILE
		chmod 644 $TMPFILE
		mv $TMPFILE /var/lib/jenkins/userContent/$ARTIFACTS/index.html
		echo "$URL" | tee -a ${RBUILDLOG}
		echo | tee -a ${RBUILDLOG}
		MESSAGE="$URL published"
		if [ $SAVE_ARTIFACTS -eq 3 ] ; then
			MESSAGE="$MESSAGE, $DBDVERSION had troubles with these..."
		fi
		kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE" || true # don't fail the whole job
	elif [ $SAVE_ARTIFACTS -eq 2 ] ; then
		echo "No artifacts were saved for this build." | tee -a ${RBUILDLOG}
		kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "Check $REPRODUCIBLE_URL/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log to find out why no artifacts were saved." || true # don't fail the whole job
	fi
	rm -r $TMPDIR
}

cleanup_userContent() {
	rm -f /var/lib/jenkins/userContent/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_*.rbuild.log > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/dbd/${SUITE}/${ARCH}/${SRCPACKAGE}_*.debbindiff.html > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/buildinfo/${SUITE}/${ARCH}/${SRCPACKAGE}_*.buildinfo > /dev/null 2>&1
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

update_db_and_html() {
	# unmark build as properly finished
	sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id='$SRCPKGID';"
	set +x
	gen_packages_html $SUITE $SRCPACKAGE
	echo
	echo "Successfully updated the database and updated $REPRODUCIBLE_URL/rb-pkg/${SUITE}/${ARCH}/$SRCPACKAGE.html"
	echo
}

print_out_duration() {
	HOUR=$(echo "$DURATION/3600"|bc)
	MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date) - total duration: ${HOUR}h ${MIN}m ${SEC}s." | tee -a ${RBUILDLOG}
}

handle_404() {
	echo "Warning: Download of ${SRCPACKAGE} sources from ${SUITE} failed." | tee -a ${RBUILDLOG}
	ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration) VALUES ('${SRCPKGID}', 'None', '404', '$DATE', '')"
	echo "Warning: Maybe there was a network problem, or ${SRCPACKAGE} is not a source package in ${SUITE}, or was removed or renamed. Please investigate." | tee -a ${RBUILDLOG}
	update_db_and_html
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=2 ; fi
	exit 0
}

handle_not_for_us() {
	# a list of valid architecture for this package should be passed to this function
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration) VALUES ('${SRCPKGID}', '${VERSION}', 'not for us', '$DATE', '')"
	echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$(echo "$@" | xargs echo )\" and thus was skipped." | tee -a ${RBUILDLOG}
	update_db_and_html
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=2 ; fi
	exit 0
}

handle_ftbfs() {
	echo "${SRCPACKAGE} failed to build from source."
	calculate_build_duration
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration) VALUES ('${SRCPKGID}', '${VERSION}', 'FTBFS', '$DATE', '$DURATION')"
	sqlite3 -init $INIT ${PACKAGES_DB} "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration) VALUES ('${SRCPACKAGE}', '${VERSION}', '${SUITE}', '${ARCH}', 'FTBFS', '${DATE}', '${DURATION}')"
	update_db_and_html
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=2 ; fi
}

handle_reproducible() {
	if [ ! -f ./${DBDREPORT} ] && [ -f b1/${BUILDINFO} ] ; then
		cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1
		figlet ${SRCPACKAGE}
		echo | tee -a ${RBUILDLOG}
		echo "$DBDVERSION found no differences in the changes files, and a .buildinfo file also exists." | tee -a ${RBUILDLOG}
		echo "${SRCPACKAGE} built successfully and reproducibly." | tee -a ${RBUILDLOG}
		calculate_build_duration
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration) VALUES ('${SRCPKGID}', '${VERSION}', 'reproducible',  '$DATE', '$DURATION')"
		sqlite3 -init $INIT ${PACKAGES_DB} "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration) VALUES ('${SRCPACKAGE}', '${VERSION}', '${SUITE}', '${ARCH}', 'reproducible', '${DATE}', '${DURATION}')"
		update_db_and_html
	fi
}

handle_ftbr() {
	echo | tee -a ${RBUILDLOG}
	echo -n "$(date) - ${SRCPACKAGE} failed to build reproducibly in ${SUITE} on ${ARCH} " | tee -a ${RBUILDLOG}
	cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1 || true
	if [ -f ./${DBDREPORT} ] ; then
		echo -n ", $DEBBINDIFFOUT" | tee -a ${RBUILDLOG}
		mv ./${DBDREPORT} /var/lib/jenkins/userContent/dbd/${SUITE}/${ARCH}/
	else
		echo -n ", $DBDVERSION produced no output (which is strange)"
	fi
	echo "." | tee -a ${RBUILDLOG}
	OLD_STATUS=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT status FROM results WHERE package_id='${SRCPKGID}'")
	calculate_build_duration
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration) VALUES ('${SRCPKGID}', '${VERSION}', 'unreproducible', '$DATE', '$DURATION')"
	sqlite3 -init $INIT ${PACKAGES_DB} "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration) VALUES ('${SRCPACKAGE}', '${VERSION}', '${SUITE}', '${ARCH}', 'unreproducible', '${DATE}', '${DURATION}')"
	update_db_and_html
	if [ "${OLD_STATUS}" = "reproducible" ]; then
		MESSAGE="status changed from reproducible -> unreproducible. ${REPRODUCIBLE_URL}/${SUITE}/${ARCH}/${SRCPACKAGE}"
		echo "\n$MESSAGE" | tee -a ${RBUILDLOG}
		# kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE" || true # don't fail the whole job
	fi
}

init_debbindiff() {
	# the schroot for debbindiff gets updated once a day. wait patiently if that's the case
	if [ -f $DBDCHROOT_WRITELOCK ] || [ -f $DBDCHROOT_READLOCK ] ; then
		for i in $(seq 0 200) ; do	# this loop also exists in _common.sh and _setup_schroot.sh
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
}

dbd_timeout() {
	echo "$(date) - $DBDVERSION was killed after running into timeout after $TIMEOUT... maybe there is still $REPRODUCIBLE_URL/dbd/${SUITE}/${ARCH}/${DBDREPORT}" | tee -a ${RBUILDLOG}
	if [ ! -s ./${DBDREPORT} ] ; then
		echo "$(date) - $DBDVERSION produced no output and was killed after running into timeout after $TIMEOUT..." >> ${DBDREPORT}
	fi
	SAVE_ARTIFACTS=3
}

call_debbindiff() {
	init_debbindiff
	echo | tee -a ${RBUILDLOG}
	TIMEOUT="30m"  # don't forget to also change the "seq 0 200" loop 17 lines above
	DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-unstable-debbindiff debbindiff -- --version 2>&1)"
	echo "$(date) - $DBDVERSION will be used to compare the two builds now." | tee -a ${RBUILDLOG}
	set -x
	( timeout $TIMEOUT schroot --directory $TMPDIR -c source:jenkins-reproducible-unstable-debbindiff debbindiff -- --html ./${DBDREPORT} ./b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ./b2/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes 2>&1 ) 2>&1 >> ${RBUILDLOG}
	RESULT=$?
	set +x
	rm -f $DBDCHROOT_READLOCK
	echo | tee -a ${RBUILDLOG}
	case $RESULT in
		124)
			dbd_timeout
			;;
		0)
			handle_reproducible
		1)
			DEBBINDIFFOUT="$DBDVERSION found issues, please investigate $REPRODUCIBLE_URL/dbd/${SUITE}/${ARCH}/${DBDREPORT}"
			;;
		2)
			DEBBINDIFFOUT="$DBDVERSION had trouble comparing the two builds. Please investigate $REPRODUCIBLE_URL/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log"
			SAVE_ARTIFACTS=3
			;;
	esac
	handle_ftbr
	print_out_duration
}

choose_package () {
	local RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT s.suite, s.id, s.name, sch.date_scheduled, sch.save_artifacts FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id WHERE sch.date_build_started = '' ORDER BY date_scheduled LIMIT 1")
	SUITE=$(echo $RESULT|cut -d "|" -f1)
	SRCPKGID=$(echo $RESULT|cut -d "|" -f2)
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f3)
	SCHEDULED_DATE=$(echo $RESULT|cut -d "|" -f4)
	SAVE_ARTIFACTS=$(echo $RESULT|cut -d "|" -f5)
	if [ -z "$RESULT" ] ; then
		echo "No packages scheduled, sleeping 30m."
		sleep 30m
		exit 0
	fi
}

init() {
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		AANOUNCE=" Artifacts will be preserved."
	fi
	create_results_dirs
	echo "============================================================================="
	echo "Trying to reproducibly build ${SRCPACKAGE} in ${SUITE} on ${ARCH} now.$AANOUNCE"
	echo "============================================================================="
	# mark build attempt
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO schedule (package_id, date_scheduled, date_build_started) VALUES ('$SRCPKGID', '$SCHEDULED_DATE', '$DATE');"
	echo "Starting to build ${SRCPACKAGE}/${SUITE} on $DATE" | tee ${RBUILDLOG}
	echo "The jenkins build log is/was available at $BUILD_URL/console" | tee -a ${RBUILDLOG}
}

get_source_package() {
	schroot --directory $PWD -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
	local RESULT=$?
	if [ $RESULT != 0 ] ; then
		# sometimes apt-get cannot download a package for whatever reason.
		# if so, wait some time and try again. only if that fails, give up.
		echo "Download of ${SRCPACKAGE} sources from ${SUITE} failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		echo "Sleeping 5m before re-trying..." | tee -a ${RBUILDLOG}
		sleep 5m
		schroot --directory $PWD -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
		local RESULT=$?
	fi
	if [ $RESULT != 0 ] ; then handle_404 ; fi
}

check_suitability() {
	# check whether the package is not for us...
	local SUITABLE=false
	local ARCHITECTURES=$(grep "^Architecture: " ${SRCPACKAGE}_*.dsc| cut -d " " -f2- | sed -s "s# #\n#g" | sort -u)
	set +x
	for arch in ${ARCHITECTURES} ; do
		if [ "$arch" = "any" ] || [ "$arch" = "amd64" ] || [ "$arch" = "linux-any" ] || [ "$arch" = "linux-amd64" ] || [ "$arch" = "any-amd64" ] ; then
			local SUITABLE=true
			break
		fi
	done
	if [ "${ARCHITECTURES}" = "all" ] ; then
		local SUITABLE=true
	fi
	if ! $SUITABLE ; then handle_not_for_us $ARCHITECTURES ; fi
}

build_rebuild() {
	local FTBFS=1
	local TMPLOG=$(mktemp --tmpdir=$PWD)
	local RBUILDLOG=$(mktemp --tmpdir=$PWD) # FIXME check wheter my changes here are fine
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$PWD)
	local NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
	mkdir b1 b2
	set -x
	printf "BUILDUSERID=1111\nBUILDUSERNAME=pbuilder1\n" > $TMPCFG
	( timeout 12h nice ionice -c 3 sudo \
	  DEB_BUILD_OPTIONS="parallel=$NUM_CPU" \
	  TZ="/usr/share/zoneinfo/Etc/GMT+12" \
	  pbuilder --build \
		--configfile $TMPCFG \
		--debbuildopts "-b" \
		--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
		--buildresult b1 \
		--distribution ${SUITE} \
		${SRCPACKAGE}_*.dsc \
	) 2>&1 | tee ${TMPLOG}
	set +x
	if [ -f b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
		# the first build did not FTBFS, try rebuild it.
		echo "============================================================================="
		echo "Re-building ${SRCPACKAGE}/${VERSION} in ${SUITE} on ${ARCH} now."
		echo "============================================================================="
		set -x
		printf "BUILDUSERID=2222\nBUILDUSERNAME=pbuilder2\n" > $TMPCFG
		( timeout 12h nice ionice -c 3 sudo \
		  DEB_BUILD_OPTIONS="parallel=$NUM_CPU" \
		  TZ="/usr/share/zoneinfo/Etc/GMT-14" \
		  LANG="fr_CH.UTF-8" \
		  LC_ALL="fr_CH.UTF-8" \
		  /usr/bin/linux64 --uname-2.6 \
			/usr/bin/unshare --uts -- \
				/usr/sbin/pbuilder --build \
					--configfile $TMPCFG \
					--hookdir /etc/pbuilder/rebuild-hooks \
					--debbuildopts "-b" \
					--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
					--buildresult b2 \
					--distribution ${SUITE} \
					${SRCPACKAGE}_${EVERSION}.dsc
		) 2>&1 | tee -a ${RBUILDLOG}
		set +x
		if [ -f b2/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
			# both builds were fine, i.e., they did not FTBFS.
			local FTBFS=0
			cleanup_userContent # FIXME check wheter my changes here are fine
			mv $RBUILDLOG /var/lib/jenkins/userContent/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
			RBUIlDLOG=/var/lib/jenkins/userContent/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
			call_debbindiff
		else
			echo "The second build failed, even though the first build was successful." | tee -a ${RBUILDLOG}
		fi
	else
		cat ${TMPLOG} >> ${RBUILDLOG}
	fi
	rm ${TMPLOG} $TMPCFG
	if [ $FTBFS -eq 1 ] ; then handle_ftbfs ; fi
}


#
# below there is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date +'%Y-%m-%d %H:%M')
START=$(date +'%s')

choose_package  # defines SUITE, PKGID, SRCPACKAGE, SCHEDULED_DATE, SAVE_ARTIFACTS

DBDREPORT=$(echo ${SRCPACKAGE}_${EVERSION}.debbindiff.html)
BUILDINFO=${SRCPACKAGE}_${EVERSION}_${ARCH}.buildinfo

init
get_source_package

VERSION=$(grep "^Version: " ${SRCPACKAGE}_*.dsc| head -1 | egrep -v '(GnuPG v|GnuPG/MacGPG2)' | cut -d " " -f2-)
EVERSION=$(echo $VERSION | cut -d ":" -f2)  # EPOCH_FREE_VERSION was too long

cat ${SRCPACKAGE}_${EVERSION}.dsc | tee -a ${RBUILDLOG}

check_suitability
build_rebuild  # defines RBUILDLOG

cd ..
cleanup_all
trap - INT TERM EXIT

