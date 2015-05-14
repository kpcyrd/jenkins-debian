#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# support for different architectures (we have actual support only for amd64)
ARCH="amd64"

# sleep 1-12 secs to randomize start times
/bin/sleep $(echo "scale=1 ; $(shuf -i 1-120 -n 1)/10" | bc )

irc_message() {
	local MESSAGE="$@"
	kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE" || true # don't fail the whole job
}

create_results_dirs() {
	mkdir -p $BASE/dbd/${SUITE}/${ARCH}
	mkdir -p $BASE/rbuild/${SUITE}/${ARCH}
	mkdir -p $BASE/buildinfo/${SUITE}/${ARCH}
}

handle_race_condition() {
	echo | tee -a $BUILDLOG
	local msg="Warning, package ${SRCPACKAGE} in ${SUITE} on ${ARCH} is probably already building elsewhere, exiting.\n"
	local msg="${msg}Please check $BUILD_URL and https://reproducible.debian.net/$SUITE/$ARCH/${SRCPACKAGE} for a different build.\n"
	case $1 in
		"db")
			local msg="${msg}The race condition was caught while marking the build attempt in the database.\n"
			;;
		"init")
			local msg="${msg}The race condition was caught while writing the lockfile.\n"
			;;
		"lockfile")
			local msg="${msg}The race condition was caught while checking the lockfile for pid correctness.\n"
			;;
	esac
	printf "$msg" | tee -a $BUILDLOG
	printf "$(date) - $msg" >> /var/log/jenkins/reproducible-race-conditions.log
	echo "$(date) - Terminating this build quickly and nicely..." | tee -a $RBUILDLOG
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		SAVE_ARTIFACTS=0
		if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	fi
	exit 0
}

check_for_race_conditions() {
	if [ $$ -ne $(cat "$LOCKFILE") ] ; then
		BAD_LOCKFILE=true
		handle_race_condition lockfile
	fi
}

save_artifacts() {
		local random=$(head /dev/urandom | tr -cd '[:alnum:]'| head -c5)
		local ARTIFACTS="artifacts/r00t-me/${SRCPACKAGE}_${SUITE}_tmp-${random}"
		local URL="$REPRODUCIBLE_URL/$ARTIFACTS/"
		local HEADER="$BASE/$ARTIFACTS/.HEADER.html"
		mkdir -p $BASE/$ARTIFACTS
		cp -r $TMPDIR/* $BASE/$ARTIFACTS/
		echo | tee -a ${RBUILDLOG}
		local msg="Artifacts from this build are preserved. They will be available for 72h only, so download them now if you want them.\n"
		local msg="${msg}WARNING: You shouldn't trust packages you downloaded from this host, they can contain malware or the worst of your fears, packaged nicely in debian format.\n"
		local msg="${msg}If you are not afraid facing your fears while helping the world by investigating reproducible build issues, you can download the artifacts from the following location: $URL\n"
		printf "$msg" | tee -a $BUILDLOG
		echo "<p>" > $HEADER
		printf "$msg" | sed 's#$#<br />#g' >> $HEADER
		echo "Package page: <a href=\"$REPRODUCIBLE_URL/${SUITE}/${ARCH}/${SRCPACKAGE}\">$REPRODUCIBLE_URL/${SUITE}/${ARCH}/${SRCPACKAGE}</a><br />" >> $HEADER
		echo "</p>" >> $HEADER
		chmod 644 $HEADER
		echo | tee -a ${RBUILDLOG}
		# irc message
		if [ ! -z "$NOTIFY" ] ; then
			local MESSAGE="$URL published"
			if [ "$NOTIFY" = "debbindiff" ] ; then
				local MESSAGE="$MESSAGE, $DBDVERSION had troubles with these..."
			fi
			irc_message "$MESSAGE"
		fi
}

cleanup_all() {
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then save_artifacts ; fi
	if [ "$NOTIFY" = "failure" ] ; then
		echo "No artifacts were saved for this build." | tee -a ${RBUILDLOG}
		irc_message "Check $REPRODUCIBLE_URL/$SUITE/$ARCH/$SRCPACKAGE and $BUILD_URL to find out why no artifacts were saved (final status $STATUS)"
	elif [ ! -z "$NOTIFY" ] && [ $SAVE_ARTIFACTS -eq 0 ] ; then
		irc_message "$REPRODUCIBLE_URL/$SUITE/$ARCH/$SRCPACKAGE finished building ($STATUS)"
	fi
	rm -r $TMPDIR
	if ! $BAD_LOCKFILE ; then rm -f $LOCKFILE ; fi
}

cleanup_userContent() {
	rm -f $BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_*.rbuild.log > /dev/null 2>&1
	rm -f $BASE/dbd/${SUITE}/${ARCH}/${SRCPACKAGE}_*.debbindiff.html > /dev/null 2>&1
	rm -f $BASE/buildinfo/${SUITE}/${ARCH}/${SRCPACKAGE}_*.buildinfo > /dev/null 2>&1
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

update_db_and_html() {
	# everything passed at this function is saved as a status of this package in the db
	STATUS="$@"
	if [ -z "$VERSION" ] ; then
		VERSION="None"
	fi
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date, build_duration) VALUES ('${SRCPKGID}', '$VERSION', '$STATUS', '$DATE', '$DURATION')"
	if [ ! -z "$DURATION" ] ; then  # this happens when not 404 and not_for_us
		sqlite3 -init $INIT ${PACKAGES_DB} "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration) VALUES ('${SRCPACKAGE}', '${VERSION}', '${SUITE}', '${ARCH}', '${STATUS}', '${DATE}', '${DURATION}')"
	fi
	# unmark build since it's properly finished
	sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id='$SRCPKGID';"
	gen_packages_html $SUITE $SRCPACKAGE
	echo
	echo "Successfully updated the database and updated $REPRODUCIBLE_URL/rb-pkg/${SUITE}/${ARCH}/$SRCPACKAGE.html"
	echo
}

print_out_duration() {
	local HOUR=$(echo "$DURATION/3600"|bc)
	local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date) - total duration: ${HOUR}h ${MIN}m ${SEC}s." | tee -a ${RBUILDLOG}
}

handle_404() {
	echo "Warning: Download of ${SRCPACKAGE} sources from ${SUITE} failed." | tee -a ${RBUILDLOG}
	ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
	echo "Warning: Maybe there was a network problem, or ${SRCPACKAGE} is not a source package in ${SUITE}, or it was removed or renamed. Please investigate." | tee -a ${RBUILDLOG}
	DURATION=''
	update_db_and_html "404"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	exit 0
}

handle_not_for_us() {
	# a list of valid architecture for this package should be passed to this function
	echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$(echo "$@" | xargs echo )\" and thus was skipped." | tee -a ${RBUILDLOG}
	DURATION=''
	update_db_and_html "not for us"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	exit 0
}

handle_ftbfs() {
	echo "${SRCPACKAGE} failed to build from source."
	calculate_build_duration
	update_db_and_html "FTBFS"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
}

handle_ftbr() {
	# a ftbr explaination message could be passed
	local FTBRmessage="$@"
	echo | tee -a ${RBUILDLOG}
	echo "$(date) - ${SRCPACKAGE} failed to build reproducibly in ${SUITE} on ${ARCH}." | tee -a ${RBUILDLOG}
	cp b1/${BUILDINFO} $BASE/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1 || true  # will fail if there is no .buildinfo
	if [ ! -z "$FTRmessage" ] ; then
		echo "$(date) - ${FTBRmessage}." | tee -a ${RBUILDLOG}
	fi
	if [ -f ./${DBDREPORT} ] ; then
		mv ./${DBDREPORT} $BASE/dbd/${SUITE}/${ARCH}/
	else
		echo "$(date) - $DBDVERSION produced no output (which is strange)." | tee -a $RBUILDLOG
	fi
	calculate_build_duration
	local OLD_STATUS=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT status FROM results WHERE package_id='${SRCPKGID}'")
	update_db_and_html "unreproducible"
	# notification for changing status
	if [ "${OLD_STATUS}" = "reproducible" ]; then
		MESSAGE="status changed from reproducible → unreproducible. ${REPRODUCIBLE_URL}/${SUITE}/${ARCH}/${SRCPACKAGE}"
		echo "\n$MESSAGE" | tee -a ${RBUILDLOG}
		irc_message "$MESSAGE"
	fi
}

handle_reproducible() {
	if [ ! -f ./${DBDREPORT} ] && [ -f b1/${BUILDINFO} ] ; then
		cp b1/${BUILDINFO} $BASE/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1
		figlet ${SRCPACKAGE}
		echo | tee -a ${RBUILDLOG}
		echo "$DBDVERSION found no differences in the changes files, and a .buildinfo file also exists." | tee -a ${RBUILDLOG}
		echo "${SRCPACKAGE} from $SUITE built successfully and reproducibly on ${ARCH}." | tee -a ${RBUILDLOG}
		calculate_build_duration
		update_db_and_html "reproducible"
	elif [ -f ./$DBDREPORT ] ; then
		echo "Debbindiff says the build is reproducible, but there is a debbindiff file. Please investigate" | tee -a $RBUILDLOG
		handle_ftbr
	elif [ ! -f b1/$BUILDINFO ] ; then
		echo "Debbindiff says the build is reproducible, but there is no .buildinfo file. Please investigate" | tee -a $RBUILDLOG
		handle_ftbr
	fi
}

init_debbindiff() {
	# the schroot for debbindiff gets updated once a day. wait patiently if that's the case
	if [ -f $DBDCHROOT_WRITELOCK ] || [ -f $DBDCHROOT_READLOCK ] ; then
		for i in $(seq 0 200) ; do  # this loop also exists in _common.sh and _setup_schroot.sh
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
	local msg="$DBDVERSION was killed after running into timeout after $1"
	if [ ! -s ./${DBDREPORT} ] ; then
		echo "$(date) - $DBDVERSION produced no output and was killed after running into timeout after ${1}..." >> ${DBDREPORT}
	else
		local msg="$msg, but there is still $REPRODUCIBLE_URL/dbd/$SUITE/$ARCH/$DDBREPORT"
	fi
	SAVE_ARTIFACTS=1
	NOTIFY="debbindiff"
	handle_ftbr "$msg"
}

call_debbindiff() {
	init_debbindiff  # check and set up locks for chroot
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	echo | tee -a ${RBUILDLOG}
	local TIMEOUT="30m"  # don't forget to also change the "seq 0 200" loop 33 lines above
	DBDSUITE=$SUITE
	if [ "$SUITE" = "experimental" ] ; then
		# there is no extra debbindiff-schroot for experimental because we specical case ghc enough already ;)
		DBDSUITE="unstable"
	fi
	DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
	echo "$(date) - $DBDVERSION will be used to compare the two builds now." | tee -a ${RBUILDLOG}
	set +e
	set -x
	( timeout $TIMEOUT schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-debbindiff \
		debbindiff -- \
			--html ./${DBDREPORT} \
			./b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes \
			./b2/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG | tee -a $RBUILDLOG  # print out dbd output
	rm -f $DBDCHROOT_READLOCK $TMPLOG
	echo | tee -a ${RBUILDLOG}
	case $RESULT in
		0)
			handle_reproducible
			;;
		1)
			handle_ftbr "$DBDVERSION found issues, please investigate $REPRODUCIBLE_URL/dbd/${SUITE}/${ARCH}/${DBDREPORT}"
			;;
		2)
			SAVE_ARTIFACTS=1
			NOTIFY="debbindiff"
			handle_ftbr "$DBDVERSION had trouble comparing the two builds. Please investigate $REPRODUCIBLE_URL/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log"
			;;
		124)
			dbd_timeout $TIMEOUT
			;;
		*)
			handle_ftbr "Something weird with $DBDVERSION (exit with $RESULT) happened and I don't know how to handle it"
			irc_message "Something weird with $DBDVERSION (exit with $RESULT) happened and I don't know how to handle it. Check out $BUILDLOG and $REPRODUCIBLE_URL/$SUITE/$ARCH/$SRCPACKAGE and investigate manually"
			;;
	esac
	print_out_duration
}

choose_package () {
	local RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT s.suite, s.id, s.name, sch.date_scheduled, sch.save_artifacts, sch.notify FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id WHERE sch.date_build_started = '' ORDER BY date_scheduled LIMIT 1")
	SUITE=$(echo $RESULT|cut -d "|" -f1)
	SRCPKGID=$(echo $RESULT|cut -d "|" -f2)
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f3)
	SCHEDULED_DATE=$(echo $RESULT|cut -d "|" -f4)
	SAVE_ARTIFACTS=$(echo $RESULT|cut -d "|" -f5)
	NOTIFY=$(echo $RESULT|cut -d "|" -f6)
	if [ -z "$RESULT" ] ; then
		echo "No packages scheduled, sleeping 30m."
		sleep 30m
		exit 0
	fi
}

init() {
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		local AANOUNCE="Artifacts will be preserved."
	fi
	create_results_dirs
	echo "============================================================================="
	echo "Trying to reproducibly build ${SRCPACKAGE} in ${SUITE} on ${ARCH} now. $AANOUNCE"
	echo "============================================================================="
	# mark build attempt
	if [ -z "$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT date_build_started FROM schedule WHERE package_id = '$SRCPKGID'")" ] ; then
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO schedule (package_id, date_scheduled, date_build_started) VALUES ('$SRCPKGID', '$SCHEDULED_DATE', '$DATE');"
	else
		BAD_LOCKFILE=true
		handle_race_condition db
	fi
	if [ ! -f "$LOCKFILE" ] ; then
		echo $$ > "$LOCKFILE"
	else
		BAD_LOCKFILE=true
		handle_race_condition init
	fi
	echo "Starting to build ${SRCPACKAGE}/${SUITE} on $DATE" | tee ${RBUILDLOG}
	echo "The jenkins build log is/was available at $BUILD_URL/console" | tee -a ${RBUILDLOG}
}

get_source_package() {
	schroot --directory $PWD -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} 2>&1 | tee -a ${RBUILDLOG}
	local RESULT=$?
	if [ $RESULT != 0 ] ; then
		# sometimes apt-get cannot download a package for whatever reason.
		# if so, wait some time and try again. only if that fails, give up.
		echo "Download of ${SRCPACKAGE} sources from ${SUITE} failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		echo "Sleeping 5m before re-trying..." | tee -a ${RBUILDLOG}
		sleep 5m
		schroot --directory $PWD -c source:jenkins-reproducible-$SUITE apt-get -- --download-only --only-source source ${SRCPACKAGE} 2>&1 | tee -a ${RBUILDLOG}
		local RESULT=$?
	fi
	if [ $RESULT != 0 ] ; then handle_404 ; fi
}

check_suitability() {
	# check whether the package is not for us...
	local SUITABLE=false
	local ARCHITECTURES=$(grep "^Architecture: " ${SRCPACKAGE}_*.dsc| cut -d " " -f2- | sed -s "s# #\n#g" | sort -u)
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
	FTBFS=1
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$TMPDIR)
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
		${SRCPACKAGE}_*.dsc \
	) 2>&1 | tee -a $RBUILDLOG
	if ! "$DEBUG" ; then set +x ; fi
	if [ -f b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
		# the first build did not FTBFS, try rebuild it.
		check_for_race_conditions
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
					${SRCPACKAGE}_${EVERSION}.dsc
		) 2>&1 | tee -a ${RBUILDLOG}
	if ! "$DEBUG" ; then set +x ; fi
		if [ -f b2/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
			# both builds were fine, i.e., they did not FTBFS.
			FTBFS=0
			cat b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes | tee -a ${RBUILDLOG}
		else
			echo "The second build failed, even though the first build was successful." | tee -a ${RBUILDLOG}
		fi
	fi
	cleanup_userContent
	chmod 644 $RBUILDLOG
	mv $RBUILDLOG $BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
	RBUILDLOG=$BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
	rm $TMPCFG
	if [ $FTBFS -eq 1 ] ; then handle_ftbfs ; fi
}


#
# below is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date +'%Y-%m-%d %H:%M')
START=$(date +'%s')
RBUILDLOG=$(mktemp --tmpdir=$TMPDIR)
BAD_LOCKFILE=false

choose_package  # defines SUITE, PKGID, SRCPACKAGE, SCHEDULED_DATE, SAVE_ARTIFACTS, NOTIFY

# used to catch race conditions when the same package is being built by two parallel jobs
LOCKFILE="/tmp/${SUITE}-${ARCH}-${SRCPACKAGE}"

init
get_source_package

VERSION=$(grep "^Version: " ${SRCPACKAGE}_*.dsc| head -1 | egrep -v '(GnuPG v|GnuPG/MacGPG2)' | cut -d " " -f2-)
EVERSION=$(echo $VERSION | cut -d ":" -f2)  # EPOCH_FREE_VERSION was too long
DBDREPORT="${SRCPACKAGE}_${EVERSION}.debbindiff.html"
BUILDINFO="${SRCPACKAGE}_${EVERSION}_${ARCH}.buildinfo"

cat ${SRCPACKAGE}_${EVERSION}.dsc | tee -a ${RBUILDLOG}

check_for_race_conditions
check_suitability
check_for_race_conditions
build_rebuild  # defines FTBFS redefines RBUILDLOG
if [ $FTBFS -eq 0 ] ; then
	call_debbindiff  # defines DBDVERSION, update_db_and_html defines STATUS
fi

check_for_race_conditions
cd ..
cleanup_all
trap - INT TERM EXIT

