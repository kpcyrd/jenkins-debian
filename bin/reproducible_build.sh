#!/bin/bash

# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
#         © 2015-2016 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

create_results_dirs() {
	mkdir -vp $BASE/dbd/${SUITE}/${ARCH}
	mkdir -vp $BASE/dbdtxt/${SUITE}/${ARCH}
	mkdir -vp $BASE/logs/${SUITE}/${ARCH}
	mkdir -vp $BASE/logdiffs/${SUITE}/${ARCH}
	mkdir -vp $BASE/rbuild/${SUITE}/${ARCH}
	mkdir -vp $BASE/buildinfo/${SUITE}/${ARCH}
}

handle_race_condition() {
	echo | tee -a $BUILDLOG
	local RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT job FROM schedule WHERE package_id='$SRCPKGID'")
	local msg="Warning, package ${SRCPACKAGE} (id=$SRCPKGID) in ${SUITE} on ${ARCH} is probably already building at $RESULT, while this is $BUILD_URL.\n"
	printf "$msg" | tee -a $BUILDLOG
	printf "$(date -u) - $msg" >> /var/log/jenkins/reproducible-race-conditions.log
	echo "$(date -u) - Terminating this build quickly and nicely..." | tee -a $RBUILDLOG
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		SAVE_ARTIFACTS=0
		if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	fi
	# cleanup
	cd
	rm -r $TMPDIR || true
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

save_artifacts() {
		local random=$(head /dev/urandom | tr -cd '[:alnum:]'| head -c5)
		local ARTIFACTS="artifacts/r00t-me/${SRCPACKAGE}_${SUITE}_tmp-${random}"
		local URL="$REPRODUCIBLE_URL/$ARTIFACTS/"
		local HEADER="$BASE/$ARTIFACTS/.HEADER.html"
		mkdir -p $BASE/$ARTIFACTS
		cp -r $TMPDIR/* $BASE/$ARTIFACTS/
		echo | tee -a ${RBUILDLOG}
		local msg="Artifacts from this build have been preserved. They will be available for 24h only, so download them now.\n"
		msg="${msg}WARNING: You shouldn't trust packages downloaded from this host, they can contain malware or the worst of your fears, packaged nicely in debian format.\n"
		msg="${msg}If you are not afraid facing your fears while helping the world by investigating reproducible build issues, you can download the artifacts from the following location: $URL\n"
		printf "$msg" | tee -a $BUILDLOG
		echo "<p>" > $HEADER
		printf "$msg" | sed 's#$#<br />#g' >> $HEADER
		echo "Package page: <a href=\"$REPRODUCIBLE_URL/${SUITE}/${ARCH}/${SRCPACKAGE}\">$REPRODUCIBLE_URL/${SUITE}/${ARCH}/${SRCPACKAGE}</a><br />" >> $HEADER
		echo "</p>" >> $HEADER
		chmod 644 $HEADER
		echo | tee -a ${RBUILDLOG}
		# irc message
		if [ ! -z "$NOTIFY" ] ; then
			local MESSAGE="Artifacts for ${SRCPACKAGE}, $STATUS in ${SUITE}/${ARCH}: $URL"
			if [ "$NOTIFY" = "diffoscope" ] ; then
				MESSAGE="$MESSAGE (error running $DIFFOSCOPE)"
			fi
			irc_message "$MESSAGE"
		fi
}

cleanup_all() {
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		save_artifacts
	elif [ ! -z "$NOTIFY" ] && [ $SAVE_ARTIFACTS -eq 0 ] ; then
		irc_message "$REPRODUCIBLE_URL/$SUITE/$ARCH/$SRCPACKAGE done: $STATUS"
	fi
	[ ! -f $RBUILDLOG ] || gzip -9fvn $RBUILDLOG
	if [ "$MODE" = "master" ] ; then
		# XXX quite ugly: this is just needed to update the sizes of the
		# compressed files in the html. It's cheap and quite safe so, *shrugs*...
		gen_package_html $SRCPACKAGE
		cd
		rm -r $TMPDIR || true
	fi
}

update_db_and_html() {
	#
	# as we still experience problems with locked database, in this function
	# each sqlite command is run as: command || command, thus doubling the chance
	# each will succeed... (no further comment… it was probably not designed to
	# accessed by 40 jobs…)
	#
	# save everything as status of this package in the db
	STATUS="$@"
	if [ -z "$VERSION" ] ; then
		VERSION="None"
	fi
	local OLD_STATUS=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT status FROM results WHERE package_id='${SRCPKGID}'" || \
			   sqlite3 -init $INIT ${PACKAGES_DB} "SELECT status FROM results WHERE package_id='${SRCPKGID}'")
	# irc+mail notifications for changing status in unstable and experimental
	if [ "$SUITE" != "testing" ] ; then
		if [ "${OLD_STATUS}" = "reproducible" ] && [ "$STATUS" != "depwait" ] && \
		  ( [ "$STATUS" = "unreproducible" ] || [ "$STATUS" = "FTBFS" ] ) ; then
			MESSAGE="${REPRODUCIBLE_URL}/${SUITE}/${ARCH}/${SRCPACKAGE} : reproducible ➤ ${STATUS}"
			echo -e "\n$MESSAGE" | tee -a ${RBUILDLOG}
			irc_message "$MESSAGE"
			# disable ("regular") irc notification unless it's due to diffoscope problems
			if [ ! -z "$NOTIFY" ] && [ "$NOTIFY" != "diffoscope" ] ; then
				NOTIFY=""
			fi
		fi
		if [ "$OLD_STATUS" != "$STATUS" ] && [ "$NOTIFY_MAINTAINER" -eq 1 ] && \
		  [ "$OLD_STATUS" != "depwait" ] && [ "$STATUS" != "depwait" ] && \
		  [ "$OLD_STATUS" != "404" ] && [ "$STATUS" != "404" ]; then
			# spool notifications and mail them once a day
			mkdir -p /srv/reproducible-results/notification-emails
			echo "$(date -u +'%Y-%m-%d %H:%M') $REPRODUCIBLE_URL/$SUITE/$ARCH/$SRCPACKAGE changed from $OLD_STATUS -> $STATUS" >> /srv/reproducible-results/notification-emails/$SRCPACKAGE
		fi
	fi
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration, node1, node2, job) VALUES ('$SRCPKGID', '$VERSION', '$STATUS', '$DATE', '$DURATION', '$NODE1', '$NODE2', '$JOB')" || \
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration, node1, node2, job) VALUES ('$SRCPKGID', '$VERSION', '$STATUS', '$DATE', '$DURATION', '$NODE1', '$NODE2', '$JOB')"
	if [ ! -z "$DURATION" ] ; then  # this happens when not 404 and not_for_us
		sqlite3 -init $INIT ${PACKAGES_DB} "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration, node1, node2, job, schedule_message) VALUES ('$SRCPACKAGE', '$VERSION', '$SUITE', '$ARCH', '$STATUS', '$DATE', '$DURATION', '$NODE1', '$NODE2', '$JOB', '$SCHEDULE_MESSAGE')" || \
		sqlite3 -init $INIT ${PACKAGES_DB} "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration, node1, node2, job, schedule_message) VALUES ('$SRCPACKAGE', '$VERSION', '$SUITE', '$ARCH', '$STATUS', '$DATE', '$DURATION', '$NODE1', '$NODE2', '$JOB', '$SCHEDULE_MESSAGE')"
	fi
	# unmark build since it's properly finished
	sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id='$SRCPKGID';" || \
	sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id='$SRCPKGID';"
	gen_package_html $SRCPACKAGE
	echo
	echo "$(date -u) - successfully updated the database and updated $REPRODUCIBLE_URL/rb-pkg/${SUITE}/${ARCH}/$SRCPACKAGE.html"
	echo
}

update_rbuildlog() {
	chmod 644 $RBUILDLOG
	mv $RBUILDLOG $BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
	RBUILDLOG=$BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
}

diff_copy_buildlogs() {
	local DIFF="$BASE/logdiffs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.diff"
	if [ -f b1/build.log ] ; then
		if [ -f b2/build.log ] ; then
			printf "Diff of the two buildlogs:\n\n--\n" | tee -a $DIFF
			diff -u b1/build.log b2/build.log | tee -a $DIFF
			if [ ${PIPESTATUS[0]} -eq 0 ] ; then
				echo "The two build logs are identical! \o/" | tee -a $DIFF
			fi
			echo -e "\nCompressing the 2nd log..."
			gzip -9vn $DIFF
			gzip -9cvn b2/build.log > $BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build2.log.gz
			chmod 644 $BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build2.log.gz
		elif [ $FTBFS -eq 0 ] ; then
			echo "Warning: No second build log, what happened?" | tee -a $RBUILDLOG
		fi
		set -x # # to debug diffoscope/schroot problems
		echo "Compressing the 1st log..."
		gzip -9cvn b1/build.log > $BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build1.log.gz
		chmod 644 $BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build1.log.gz
	else
		echo "Error: No first build log, not even looking for the second" | tee -a $RBUILDLOG
	fi
}

handle_404() {
	echo "Warning: Download of ${SRCPACKAGE} sources from ${SUITE} failed." | tee -a ${RBUILDLOG}
	ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
	echo "Warning: Maybe there was a network problem, or ${SRCPACKAGE} is not a source package in ${SUITE}, or it was removed or renamed. Please investigate. Sleeping 30m as this should not happen." | tee -a ${RBUILDLOG}
	DURATION=''
	EVERSION="None"
	update_rbuildlog
	update_db_and_html "404"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	sleep 30m
	exit 0 # RBUILDLOG and SAVE_ARTIFACTS and NOTIFY are used in cleanup_all called at exit
}

handle_depwait() {
	echo "Downloading the build dependencies failed" | tee -a "$RBUILDLOG"
	echo "Maybe there was a network problem, or the build dependencies are currently uninstallable; consider filing a bug in the last case." | tee -a "$RBUILDLOG"
	echo "Network problems are automatically rescheduled after some hours." | tee -a "$RBUILDLOG"
	calculate_build_duration
	update_db_and_html "depwait"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ -n "$NOTIFY" ] ; then NOTIFY="depwait" ; fi
}

handle_not_for_us() {
	# a list of valid architecture for this package should be passed to this function
	echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$(echo "$@" | xargs echo )\" and thus was skipped." | tee -a ${RBUILDLOG}
	DURATION=''
	update_rbuildlog
	update_db_and_html "not for us"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	exit 0 # RBUILDLOG and SAVE_ARTIFACTS and NOTIFY are used in cleanup_all called at exit
}

handle_ftbfs() {
	if ! "$DEBUG" ; then set +x ; fi
	local BUILD
	echo "${SRCPACKAGE} failed to build from source."
	for BUILD in "1" "2"; do
		local nodevar="NODE$BUILD"
		local node=""
		eval node=\$$nodevar
		if [ ! -f "$BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ] ; then
			continue
		fi
		if zgrep -F "E: pbuilder-satisfydepends failed." "$BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ; then
			handle_depwait
			return
		fi
		for NEEDLE in '^tar:.*Cannot write: No space left on device' 'fatal error: error writing to .* No space left on device' './configure: line .* printf: write error: No space left on device' 'cat: write error: No space left on device' '^dpkg-deb.*No space left on device' '^cp: (erreur|impossible).*No space left on device' '^tee: .* No space left on device' '^zip I/O error: No space left on device' '^mkdir .*: No space left on device' ; do
			if zgrep -e "$NEEDLE" "$BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ; then
				handle_enospace $node
				return
			fi
		done
		# notify about unkown diskspace issues where we are not 100% sure yet those are diskspace issues
		if zgrep -e "No space left on device" "$BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ; then
			MESSAGE="${BUILD_URL}console for ${SRCPACKAGE} (ftbfs in $SUITE/$ARCH) _probably_ had a diskspace issue on $node. Please check, tune handle_ftbfs() and reschedule the package."
			echo $MESSAGE | tee -a /var/log/jenkins/reproducible-diskspace-issues.log
			irc_message "$MESSAGE"
		fi
	done
	calculate_build_duration
	update_db_and_html "FTBFS"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
}

handle_ftbr() {
	# a ftbr explaination message could be passed
	local FTBRmessage="$@"
	echo | tee -a ${RBUILDLOG}
	echo "$(date -u) - ${SRCPACKAGE} failed to build reproducibly in ${SUITE} on ${ARCH}." | tee -a ${RBUILDLOG}
	cp b1/${BUILDINFO} $BASE/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1 || true  # will fail if there is no .buildinfo
	if [ ! -z "$FTRmessage" ] ; then
		echo "$(date -u) - ${FTBRmessage}." | tee -a ${RBUILDLOG}
	fi
	if [ -f ./${DBDREPORT} ] ; then
		mv ./${DBDREPORT} $BASE/dbd/${SUITE}/${ARCH}/
	else
		echo "$(date -u) - $DIFFOSCOPE produced no output (which is strange)." | tee -a $RBUILDLOG
	fi
	if [ -f ./$DBDTXT ] ; then
		mv ./$DBDTXT $BASE/dbdtxt/$SUITE/$ARCH/
		gzip -9n $BASE/dbdtxt/$SUITE/$ARCH/$DBDTXT
	fi
	calculate_build_duration
	update_db_and_html "unreproducible"
}

handle_reproducible() {
	if [ ! -f ./${DBDREPORT} ] && [ -f b1/${BUILDINFO} ] ; then
		cp b1/${BUILDINFO} $BASE/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1
		figlet ${SRCPACKAGE}
		echo | tee -a ${RBUILDLOG}
		echo "$DIFFOSCOPE found no differences in the changes files, and a .buildinfo file also exists." | tee -a ${RBUILDLOG}
		echo "${SRCPACKAGE} from $SUITE built successfully and reproducibly on ${ARCH}." | tee -a ${RBUILDLOG}
		calculate_build_duration
		update_db_and_html "reproducible"
	elif [ -f ./$DBDREPORT ] ; then
		echo "Diffoscope claims the build is reproducible, but there is a diffoscope file. Please investigate." | tee -a $RBUILDLOG
		handle_ftbr
	elif [ ! -f b1/$BUILDINFO ] ; then
		echo "Diffoscope claims the build is reproducible, but there is no .buildinfo file. Please investigate." | tee -a $RBUILDLOG
		handle_ftbr
	fi
}

unregister_build() {
	# unregister this build so it will immeditiatly tried again
	sqlite3 -init $INIT ${PACKAGES_DB} "UPDATE schedule SET date_build_started = NULL, job = NULL WHERE package_id='$SRCPKGID'"
	NOTIFY=""
}

handle_env_changes() {
	unregister_build
	MESSAGE="$(date -u ) - ${BUILD_URL}console encountered a problem: $1"
	echo -e "$MESSAGE" | tee -a /var/log/jenkins/reproducible-env-changes.log
	# no need to slow down
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

handle_remote_error() {
	unregister_build
	MESSAGE="${BUILD_URL}console got remote error $1"
	echo "$(date -u ) - $MESSAGE" | tee -a /var/log/jenkins/reproducible-remote-error.log
	echo "Sleeping 5m before aborting the job."
	sleep 5m
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

handle_enospace() {
	unregister_build
	MESSAGE="${BUILD_URL}console hit diskspace issues with $SRCPACKAGE on $SUITE/$ARCH on $1, sleeping 30m."
	echo "$MESSAGE"
	echo "$MESSAGE" | mail -s "$JOB on $1 ran into diskspace problems" qa-jenkins-scm@lists.alioth.debian.org
	echo "Sleeping 2h before aborting the job."
	sleep 2h
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

dbd_timeout() {
	local msg="$DIFFOSCOPE was killed after running into timeout after $1"
	if [ ! -s ./${DBDREPORT} ] ; then
		echo "$(date -u) - $DIFFOSCOPE produced no output and was killed after running into timeout after ${1}..." >> ${DBDREPORT}
	else
		msg="$msg, but there is still $REPRODUCIBLE_URL/dbd/$SUITE/$ARCH/$DDBREPORT"
	fi
	SAVE_ARTIFACTS=1
	NOTIFY="diffoscope"
	handle_ftbr "$msg"
}

call_diffoscope_on_buildinfo_files() {
	local TMPLOG=$(mktemp --tmpdir=$TMPDIR)
	echo | tee -a ${RBUILDLOG}
	local TIMEOUT="120m"
	DBDSUITE=$SUITE
	if [ "$SUITE" = "experimental" ] ; then
		# there is no extra diffoscope-schroot for experimental ( because we specical case ghc enough already )
		DBDSUITE="unstable"
	fi
	set -x # to debug diffoscope/schroot problems
	# TEMP is recognized by python's tempfile module to create temp stuff inside
	local TEMP=$(mktemp --tmpdir=$TMPDIR -d dbd-tmp-XXXXXXX)
	DIFFOSCOPE="$(schroot --directory $TMPDIR -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1 || true)"
	LOG_RESULT=$(echo $DIFFOSCOPE | grep '^E: 15binfmt: update-binfmts: unable to open' || true)
	if [ ! -z "$LOG_RESULT" ] ; then
		echo "$(date -u) - schroot jenkins-reproducible-${DBDSUITE}-diffoscope not available, will sleep 2min and retry."
		sleep 2m
		DIFFOSCOPE="$(schroot --directory $TMPDIR -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1 || echo 'diffoscope_version_not_available')"
	fi
	echo "$(date -u) - $DIFFOSCOPE will be used to compare the two builds:" | tee -a ${RBUILDLOG}
	set +e
	set -x
	# remember to also modify the retry diffoscope call 15 lines below
	( timeout $TIMEOUT nice schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-diffoscope \
		-- sh -c "export TMPDIR=$TEMP ; diffoscope \
			--html $TMPDIR/${DBDREPORT} \
			--text $TMPDIR/$DBDTXT \
			$TMPDIR/b1/${BUILDINFO} \
			$TMPDIR/b2/${BUILDINFO}" \
	2>&1 ) >> $TMPLOG
	RESULT=$?
	LOG_RESULT=$(grep '^E: 15binfmt: update-binfmts: unable to open' $TMPLOG || true)
	if [ ! -z "$LOG_RESULT" ] ; then
		rm -f $TMPLOG $TMPDIR/${DBDREPORT} $TMPDIR/$DBDTXT
		echo "$(date -u) - schroot jenkins-reproducible-${DBDSUITE}-diffoscope not available, will sleep 2min and retry."
		sleep 2m
		# remember to also modify the retry diffoscope call 15 lines above
		( timeout $TIMEOUT nice schroot \
			--directory $TMPDIR \
			-c source:jenkins-reproducible-${DBDSUITE}-diffoscope \
			-- sh -c "export TMPDIR=$TEMP ; diffoscope \
				--html $TMPDIR/${DBDREPORT} \
				--text $TMPDIR/$DBDTXT \
				$TMPDIR/b1/${BUILDINFO} \
				$TMPDIR/b2/${BUILDINFO}" \
		2>&1 ) >> $TMPLOG
		RESULT=$?
	fi
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG | tee -a $RBUILDLOG  # print dbd output
	rm $TMPLOG
	echo | tee -a ${RBUILDLOG}
	case $RESULT in
		0)
			handle_reproducible
			;;
		1)
			handle_ftbr "$DIFFOSCOPE found issues, please check $REPRODUCIBLE_URL/dbd/${SUITE}/${ARCH}/${DBDREPORT}"
			;;
		2)
			SAVE_ARTIFACTS=1
			NOTIFY="diffoscope"
			handle_ftbr "$DIFFOSCOPE had trouble comparing the two builds. Please investigate $REPRODUCIBLE_URL/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log"
			;;
		124)
			dbd_timeout $TIMEOUT
			;;
		*)
			handle_ftbr "Something weird happened when running $DIFFOSCOPE (which exited with $RESULT) and I don't know how to handle it"
			irc_message "Something weird happened when running $DIFFOSCOPE (which exited with $RESULT) and I don't know how to handle it. Please check $BUILDLOG and $REPRODUCIBLE_URL/$SUITE/$ARCH/$SRCPACKAGE"
			;;
	esac
}

choose_package() {
	local RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "
		SELECT s.suite, s.id, s.name, sch.date_scheduled, sch.save_artifacts, sch.notify, s.notify_maintainer, sch.message
		FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id
		WHERE sch.date_build_started is NULL
		AND s.architecture='$ARCH'
		ORDER BY date_scheduled LIMIT 5"|sort -R|head -1)
	if [ -z "$RESULT" ] ; then
		echo "No packages scheduled, sleeping 30m."
		sleep 30m
		exit 0
	fi
	SUITE=$(echo $RESULT|cut -d "|" -f1)
	SRCPKGID=$(echo $RESULT|cut -d "|" -f2)
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f3)
	SAVE_ARTIFACTS=$(echo $RESULT|cut -d "|" -f5)
	NOTIFY=$(echo $RESULT|cut -d "|" -f6)
	NOTIFY_MAINTAINER=$(echo $RESULT|cut -d "|" -f7)
	SCHEDULE_MESSAGE=$(echo $RESULT|cut -d "|" -f8)
	# remove previous build attempts which didnt finish correctly:
	JOB_PREFIX="${JOB_NAME#reproducible_builder_}/"
	BAD_BUILDS=$(mktemp --tmpdir=$TMPDIR)
	sqlite3 -init $INIT ${PACKAGES_DB} "SELECT package_id, date_build_started, job FROM schedule WHERE job LIKE '${JOB_PREFIX}%'" > $BAD_BUILDS
	if [ -s "$BAD_BUILDS" ] ; then
		local STALELOG=/var/log/jenkins/reproducible-stale-builds.log
		# reproducible-stale-builds.log is mailed once a day by reproducible_maintenance.sh
		echo "$(date -u) - stale builds found, cleaning db from these:" | tee -a $STALELOG
		cat $BAD_BUILDS | tee -a $STALELOG
		sqlite3 -init $INIT ${PACKAGES_DB} "UPDATE schedule SET date_build_started = NULL, job = NULL WHERE job LIKE '${JOB_PREFIX}%'"
		echo >> $STALELOG
	fi
	rm -f $BAD_BUILDS
	# mark build attempt, first test if none else marked a build attempt recently
	echo "ok, let's check if $SRCPACKAGE is building anywhere yet…"
	RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT date_build_started FROM schedule WHERE package_id='$SRCPKGID'")
	if [ -z "$RESULT" ] ; then
		echo "ok, $SRCPACKAGE is not building anywhere…"
		# try to update the schedule with our build attempt, then check no else did it, if so, abort
		sqlite3 -init $INIT ${PACKAGES_DB} "UPDATE schedule SET date_build_started='$DATE', job='$JOB' WHERE package_id='$SRCPKGID' AND date_build_started IS NULL"
		RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT date_build_started FROM schedule WHERE package_id='$SRCPKGID' AND date_build_started='$DATE' AND job='$JOB'")
		if [ -z "$RESULT" ] ; then
			echo "hm, seems $SRCPACKAGE is building somewhere… failed to update the schedule table with our build ($SRCPKGID, $DATE, $JOB)."
			handle_race_condition
		fi
	else
		echo "hm, seems $SRCPACKAGE is building somewhere… schedule table now listed it as building somewhere else."
		handle_race_condition
	fi
	local ANNOUNCE=""
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		ANNOUNCE="Artifacts will be preserved."
	fi
	create_results_dirs
	echo "============================================================================="
	echo "Initialising reproducibly build of ${SRCPACKAGE} in ${SUITE} on ${ARCH} on $(hostname -f) now. $ANNOUNCE"
	echo "============================================================================="
	# force debug mode for certain packages
	case $SRCPACKAGE in
		xxxxxxx)
			export DEBUG=true
			set -x
			irc_message "$SRCPACKAGE/$SUITE/$ARCH started building at ${BUILD_URL}console"
			;;
		*)      ;;
	esac
	if [ "$NOTIFY" = "2" ] ; then
		irc_message "$SRCPACKAGE/$SUITE/$ARCH started building at ${BUILD_URL}console"
	elif [ "$NOTIFY" = "0" ] ; then  # the build script has a different idea of notify than the scheduler,
		NOTIFY=''                  # the scheduler uses integers, build.sh uses strings.
	fi
	echo "$(date -u ) - starting to build ${SRCPACKAGE}/${SUITE}/${ARCH} on $(hostname -f) on '$DATE'" | tee ${RBUILDLOG}
	echo "The jenkins build log is/was available at ${BUILD_URL}console" | tee -a ${RBUILDLOG}
}

download_source() {
	set +e
	local TMPLOG=$(mktemp --tmpdir=$TMPDIR)
	if [ "$MODE" != "master" ] ; then
		schroot --directory $TMPDIR -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} 2>&1 | tee ${TMPLOG}
	else
		# the build master only needs to the the .dsc file
		schroot --directory $TMPDIR -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source --print-uris source ${SRCPACKAGE} | grep \.dsc|cut -d " " -f1|xargs -r wget --timeout=180 --tries=3 2>&1 | tee ${TMPLOG}
	fi
	local ENGLISH_RESULT=$(egrep 'E: (Unable to find a source package for|Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway))' ${TMPLOG})
	local FRENCH_RESULT=$(egrep 'E: (Unable to find a source package for|impossible de récupérer.*(Unable to connect to|Échec de la connexion|Size mismatch|Cannot initiate the connection to|Bad Gateway))' ${TMPLOG}) 
	PARSED_RESULT="${ENGLISH_RESULT}${FRENCH_RESULT}"
	cat ${TMPLOG} >> ${RBUILDLOG}
	rm ${TMPLOG}
	set -e
}

download_again_if_needed() {
	if [ "$(ls ${SRCPACKAGE}_*.dsc 2> /dev/null)" = "" ] || [ ! -z "$PARSED_RESULT" ] ; then
		# sometimes apt-get cannot download a package for whatever reason.
		# if so, wait some time and try again. only if that fails, give up.
		echo "$(date -u ) - download of ${SRCPACKAGE} sources (for ${SUITE}) failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		echo "$(date -u ) - sleeping 5m before re-trying..." | tee -a ${RBUILDLOG}
		sleep 5m
		download_source
	fi
}

get_source_package() {
	PARSED_RESULT=""
	download_source
	download_again_if_needed
	download_again_if_needed
	download_again_if_needed # yes, this is called three times. this should really not happen
	if [ "$(ls ${SRCPACKAGE}_*.dsc 2> /dev/null)" = "" ] || [ ! -z "$PARSED_RESULT" ] ; then
		if [ "$MODE" = "master" ] ; then
			handle_404
		else
			exit 404
		fi
	fi
	VERSION="$(grep '^Version: ' ${SRCPACKAGE}_*.dsc| head -1 | egrep -v '(GnuPG v|GnuPG/MacGPG2)' | cut -d ' ' -f2-)"
	EVERSION="$(echo $VERSION | cut -d ':' -f2)"  # EPOCH_FREE_VERSION was too long
	DBDREPORT="${SRCPACKAGE}_${EVERSION}.diffoscope.html"
	DBDTXT="${SRCPACKAGE}_${EVERSION}.diffoscope.txt"
	BUILDINFO="${SRCPACKAGE}_${EVERSION}_${ARCH}.buildinfo"
}

check_suitability() {
	# check whether the package is not for us...
	local SUITABLE=false
	local ARCHITECTURES=$(grep "^Architecture: " ${SRCPACKAGE}_*.dsc| cut -d " " -f2- | sed -s "s# #\n#g" | sort -u)

	# packages that are *only* arch:all can be tried on any arch
	if [ "$ARCHITECTURES" = "all" ]; then
		ARCHITECTURES="any"
	fi

	for arch in ${ARCHITECTURES} ; do
		if [ "$arch" = "any" ] || [ "$arch" = "$ARCH" ] || [ "$arch" = "linux-any" ] || [ "$arch" = "linux-$ARCH" ] || [ "$arch" = "any-$ARCH" ] ; then
			SUITABLE=true
			break
		fi
		# special case arm…
		if [ "$ARCH" = "armhf" ] && [ "$arch" = "any-arm" ] ; then
			SUITABLE=true
			break
		fi

	done
	if ! $SUITABLE ; then handle_not_for_us $ARCHITECTURES ; fi
}

first_build() {
	echo "============================================================================="
	echo "Building ${SRCPACKAGE} in ${SUITE} on ${ARCH} on $(hostname -f) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$TMPDIR)
	cat > "$TMPCFG" << EOF
BUILDUSERID=1111
BUILDUSERNAME=pbuilder1
export DEB_BUILD_OPTIONS="parallel=$NUM_CPU"
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
export LANG="C"
unset LC_ALL
export LANGUAGE="en_US:en"
EOF
	# remember to change the sudoers setting if you change the following command
	# FIXME: call with --buildinfo-identifier=dummy instead and below
	( sudo timeout -k 18.1h 18h /usr/bin/ionice -c 3 /usr/bin/nice \
	  /usr/sbin/pbuilder --build \
		--configfile $TMPCFG \
		--debbuildopts "-b --buildinfo-identifier=${ARCH}" \
		--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
		--buildresult $TMPDIR/b1 \
		--logfile b1/build.log \
		${SRCPACKAGE}_${EVERSION}.dsc
	) 2>&1 | tee -a $RBUILDLOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - pbuilder was killed by timeout after 18h." | tee -a b1/build.log $RBUILDLOG
	fi
	if ! "$DEBUG" ; then set +x ; fi
	rm $TMPCFG
}

second_build() {
	echo "============================================================================="
	echo "Re-Building ${SRCPACKAGE} in ${SUITE} on ${ARCH} on $(hostname -f) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$TMPDIR)
	NEW_NUM_CPU=$NUM_CPU	# on amd64+i386 we vary this based on node choices (by design), on armhf only sometimes.
	# differ locale+language depending on the architecture (mostly for readability by different people…)
	case $ARCH in
		armel)	locale=it_CH
			language=it
			;;
		i386)	locale=de_CH
			language=de
			;;
		*)	locale=fr_CH
			language=fr
			;;
	esac
	cat > "$TMPCFG" << EOF
BUILDUSERID=2222
BUILDUSERNAME=pbuilder2
export DEB_BUILD_OPTIONS="parallel=$NUM_CPU"
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="$locale.UTF-8"
export LC_ALL="$locale.UTF-8"
export LANGUAGE="$locale:$language"
umask 0002
EOF
	set +e
	# remember to change the sudoers setting if you change the following command
	# (the 2nd build gets a longer timeout trying to make sure the first build
	# aint wasted when then 2nd happens on a highly loaded node)
	# fix: call with --buildinfo-identifier=dummy instead (and above)
	sudo timeout -k 24.1h 24h /usr/bin/ionice -c 3 /usr/bin/nice \
		/usr/bin/unshare --uts -- \
		/usr/sbin/pbuilder --build \
			--configfile $TMPCFG \
			--hookdir /etc/pbuilder/rebuild-hooks \
			--debbuildopts "-b --buildinfo-identifier=${ARCH}" \
			--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
			--buildresult $TMPDIR/b2 \
			--logfile b2/build.log \
			${SRCPACKAGE}_${EVERSION}.dsc
	PRESULT=$?
	set -e
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - pbuilder was killed by timeout after 24h." | tee -a b2/build.log
	fi
	if ! "$DEBUG" ; then set +x ; fi
	rm $TMPCFG
}

remote_build() {
	local BUILDNR=$1
	local NODE=$2
	local PORT=$3
	set +e
	ssh -o "BatchMode = yes" -p $PORT $NODE /bin/true
	RESULT=$?
	# abort job if host is down
	if [ $RESULT -ne 0 ] ; then
		# sleep 15min if this happens on the first node
		# but 1h if this happens on the 2nd node
		SLEEPTIME=$(echo "$BUILDNR*$BUILDNR*15"|bc)
		echo "$(date -u) - $NODE seems to be down, sleeping ${SLEEPTIME}min before aborting this job."
		unregister_build
		sleep ${SLEEPTIME}m
		exec /srv/jenkins/bin/abort.sh
	fi
	ssh -o "BatchMode = yes" -p $PORT $NODE /srv/jenkins/bin/reproducible_build.sh $BUILDNR ${SRCPACKAGE} ${SUITE} ${TMPDIR}
	RESULT=$?
	# 404-256=148... (ssh 'really' only 'supports' exit codes below 255...)
	if [ $RESULT -eq 148 ] ; then
		handle_404
	elif [ $RESULT -ne 0 ] ; then
		handle_remote_error "with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE} on ${SUITE}/${ARCH}"
	fi
	rsync -e "ssh -o 'BatchMode = yes' -p $PORT" -r $NODE:$TMPDIR/b$BUILDNR $TMPDIR/
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		echo "$(date -u ) - rsync from $NODE failed, sleeping 2m before re-trying..." | tee -a ${RBUILDLOG}
		sleep 2m
		rsync -e "ssh -o 'BatchMode = yes' -p $PORT" -r $NODE:$TMPDIR/b$BUILDNR $TMPDIR/
		RESULT=$?
		if [ $RESULT -ne 0 ] ; then
			handle_remote_error "when rsyncing remote build #$BUILDNR results from $NODE"
		fi
	fi
	ls -lR $TMPDIR
	ssh -o "BatchMode = yes" -p $PORT $NODE "rm -r $TMPDIR"
	set -e
	if [ $BUILDNR -eq 1 ] ; then
		cat $TMPDIR/b1/build.log >> ${RBUILDLOG}
	fi
}

check_buildinfo() {
	local TMPFILE1=$(mktemp --tmpdir=$TMPDIR)
	local TMPFILE2=$(mktemp --tmpdir=$TMPDIR)
	grep-dctrl -s Build-Environment -n ${SRCPACKAGE} ./b1/$BUILDINFO > $TMPFILE1
	grep-dctrl -s Build-Environment -n ${SRCPACKAGE} ./b2/$BUILDINFO > $TMPFILE2
	set +e
	diff $TMPFILE1 $TMPFILE2
	RESULT=$?
	set -e
	if [ $RESULT -eq 1 ] ; then
		printf "$(date -u) - $BUILDINFO in ${SUITE} on ${ARCH} varies, probably due to mirror update. Doing the first build again, please check ${BUILD_URL}console for now..." >> /var/log/jenkins/reproducible-hit-mirror-update.log
		echo
		echo "============================================================================="
		echo "$(date -u) - The build environment varies according to the two .buildinfo files, probably due to mirror update. Doing the first build on $NODE1 again."
		echo "============================================================================="
		echo
		get_node_ssh_port $NODE1
		remote_build 1 $NODE1 $PORT
		grep-dctrl -s Build-Environment -n ${SRCPACKAGE} ./b1/$BUILDINFO > $TMPFILE1
		set +e
		diff $TMPFILE1 $TMPFILE2
		RESULT=$?
		rm $TMPFILE1 $TMPFILE2
		set -e
		if [ $RESULT -eq 1 ] ; then
			handle_env_changes "different packages were installed in the 1st+2nd builds and also in the 2nd+3rd build.\n$(ls -l ./b1/$BUILDINFO) on $NODE1\n$(ls -l ./b2/$BUILDINFO) on $NODE2\n"
		fi
	fi
	rm -f $TMPFILE1 $TMPFILE2
}

build_rebuild() {
	FTBFS=1
	mkdir b1 b2
	get_node_ssh_port $NODE1
	remote_build 1 $NODE1 $PORT
	if [ ! -f b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] && [ -f b1/${SRCPACKAGE}_*_${ARCH}.changes ] ; then
			echo "Version mismatch between main node (${SRCPACKAGE}_${EVERSION}_${ARCH}.dsc expected) and first build node ($(ls b1/*dsc)) for $SUITE/$ARCH, aborting. Please upgrade the schroots..." | tee -a ${RBUILDLOG}
			# reschedule the package for later and quit the build without saving anything
			sqlite3 -init $INIT ${PACKAGES_DB} "UPDATE schedule SET date_build_started = NULL, job = NULL, date_scheduled='$(date -u +'%Y-%m-%d %H:%M')' WHERE package_id='$SRCPKGID'"
			NOTIFY=""
			exit 0
	elif [ -f b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
		# the first build did not FTBFS, try rebuild it.
		get_node_ssh_port $NODE2
		remote_build 2 $NODE2 $PORT
		if [ -f b2/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
			# both builds were fine, i.e., they did not FTBFS.
			FTBFS=0
			cat b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes | tee -a ${RBUILDLOG}
		else
			echo "$(date -u) - the second build failed, even though the first build was successful." | tee -a ${RBUILDLOG}
		fi
	fi
}

#
# below is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d -t rbuild-debian-XXXXXXXX)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
RBUILDLOG=$(mktemp --tmpdir=$TMPDIR)
JOB="${JOB_NAME#reproducible_builder_}/${BUILD_ID}"
PORT=0

#
# determine mode
#
if [ "$1" = "" ] ; then
	echo "Error, needs at least one parameter."
	exit 1
elif [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	SRCPACKAGE="$2"
	SUITE="$3"
	ARCH="$(dpkg --print-architecture)"
	SAVE_ARTIFACTS="0"
	TMPDIR="$4"
	[ -d $TMPDIR ] || mkdir -p $TMPDIR
	cd $TMPDIR
	get_source_package
	mkdir b$MODE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi
	echo "$(date -u) - build #$MODE for $SRCPACKAGE/$SUITE/$ARCH on $HOSTNAME done."
	exit 0
elif [ "$2" != "" ] ; then
	MODE="master"
	NODE1="$(echo $1 | cut -d ':' -f1).debian.net"
	NODE2="$(echo $2 | cut -d ':' -f1).debian.net"
	# overwrite ARCH for remote builds
	for i in $ARCHS ; do
		# try to match ARCH in nodenames
		if [[ "$NODE1" =~ .*-$i.* ]] ; then
			ARCH=$i
		fi
	done
	if [ -z "$ARCH" ] ; then
		echo "Error: could not detect architecture, exiting."
		exit 1
	fi
fi

#
# main - only used in master-mode
#
delay_start
choose_package  # defines SUITE, PKGID, SRCPACKAGE, SAVE_ARTIFACTS, NOTIFY
get_source_package

cat ${SRCPACKAGE}_${EVERSION}.dsc | tee -a ${RBUILDLOG}

check_suitability
build_rebuild  # defines FTBFS redefines RBUILDLOG
if [ $FTBFS -eq 0 ] ; then
	check_buildinfo
fi
cleanup_pkg_files
diff_copy_buildlogs
update_rbuildlog
if [ $FTBFS -eq 1 ] ; then
	handle_ftbfs
elif [ $FTBFS -eq 0 ] ; then
	call_diffoscope_on_buildinfo_files  # defines DIFFOSCOPE, update_db_and_html defines STATUS
fi
print_out_duration

cd ..
cleanup_all
trap - INT TERM EXIT

