#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ ! -f $PACKAGES_DB ] ; then
	echo "$PACKAGES_DB doesn't exist, no builds possible."
	exit 1
fi

# create dirs for results
mkdir -p /var/lib/jenkins/userContent/dbd/ /var/lib/jenkins/userContent/buildinfo/ /var/lib/jenkins/userContent/rbuild/

# this needs sid entries in sources.list:
grep deb-src /etc/apt/sources.list | grep sid
# try apt-get update twice, else fail gracefully, aka not.
sudo apt-get update || ( sleep $(( $RANDOM % 70 + 30 )) ; sudo apt-get update || true )

# update sources table in db
update_sources_table() {
	TMPFILE=$(mktemp)
	curl $MIRROR/dists/sid/main/source/Sources.xz > $TMPFILE
	CSVFILE=$(mktemp)
	(xzcat $TMPFILE | egrep "(^Package:|^Version:)" | sed -s "s#^Version: ##g; s#Package: ##g; s#\n# #g"| while read PKG ; do read VERSION ; echo "$PKG,$VERSION" ; done) > $CSVFILE
	sqlite3 -csv -init $INIT ${PACKAGES_DB} "DELETE from sources"
	echo ".import $CSVFILE sources" | sqlite3 -csv -init $INIT ${PACKAGES_DB}
	echo "$(date) Removing duplicate versions from sources db..."
	for PKG in $(sqlite3 ${PACKAGES_DB} 'SELECT name FROM sources GROUP BY name HAVING count(name) > 1') ; do
		BET=""
		for VERSION in $(sqlite3 ${PACKAGES_DB} "SELECT version FROM sources where name = \"$PKG\"") ; do
			if [ "$BET" = "" ] ; then
				BET=$VERSION
				continue
			elif dpkg --compare-versions "$BET" gt "$VERSION"  ; then
				sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM sources WHERE name = '$PKG' AND version = '$VERSION'"
			else
				sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM sources WHERE name = '$PKG' AND version = '$BET'"
				BET=$VERSION
			fi
		done
	done
	echo "$(date) Done removing duplicate versions from sources db..."
	# update amount of available packages (for doing statistics later)
	P_IN_TMPFILE=$(xzcat $TMPFILE | grep "^Package:" | cut -d " " -f2 | sort -u | wc -l)
	P_IN_SOURCES=$(sqlite3 ${PACKAGES_DB} 'SELECT count(name) FROM sources')
	if [ $P_IN_TMPFILE -ne $P_IN_SOURCES ] ; then
		echo "DEBUG: P_IN_SOURCES = $P_IN_SOURCES"
		echo "DEBUG: P_IN_TMPFILE = $P_IN_TMPFILE"
		exit 1
	fi
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_stats VALUES (\"sid\", \"${P_IN_SOURCES}\")"
	rm $CSVFILE # $TMPFILE is still being used
}

set +x
if [ $1 = "unknown" ] ; then
	update_sources_table
	AMOUNT=$2
	REAL_AMOUNT=0
	GUESSES=$(echo "${AMOUNT}*3" | bc)
	PACKAGES=""
	# FIXME: blacklisted is a valid status in the db which should be used...
	CANDIDATES=$(xzcat $TMPFILE | grep "^Package:" | cut -d " " -f2 | egrep -v "^(linux|cups|zurl|openclipart|eigen3|xmds2)$" | sort -R | head -$GUESSES | xargs echo)
	for PKG in $CANDIDATES ; do
		if [ $REAL_AMOUNT -eq $AMOUNT ] ; then
			continue
		fi
		RESULT=$(sqlite3 ${PACKAGES_DB} "SELECT name FROM source_packages WHERE name = \"${PKG}\"")
		if [ "$RESULT" = "" ] ; then
			PACKAGES="${PACKAGES} $PKG"
		fi
	done
elif [ $1 = "known" ] ; then
	update_sources_table
	AMOUNT=$2
	# FIXME: blacklisted is a valid status in the db which should be used...
	PACKAGES=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT DISTINCT source_packages.name FROM source_packages,sources WHERE sources.version IN (SELECT version FROM sources WHERE name=source_packages.name ORDER by sources.version DESC LIMIT 1) AND (( source_packages.status = 'unreproducible' OR source_packages.status = 'FTBFS') AND source_packages.name = sources.name AND source_packages.version != sources.version) ORDER BY source_packages.build_date LIMIT $AMOUNT" | egrep -v "^(linux|cups|zurl|openclipart|eigen3|xmds2)$" | xargs -r echo)
else
	# CANDIDATES is defined in that file
	. /srv/jenkins/bin/reproducible_candidates.sh
	PACKAGES=""
	AMOUNT=$2
	REAL_AMOUNT=0
	for i in $(seq 0 ${#CANDIDATES[@]}) ; do
		if [ $REAL_AMOUNT -eq $AMOUNT ] ; then
			continue
		fi
		PKG=${CANDIDATES[$i]}
		# FIXME: blacklisted is a valid status in the db which should be used...
		RESULT=$(sqlite3 ${PACKAGES_DB} "SELECT name FROM source_packages WHERE name = \"${PKG}\"")
		if [ "$RESULT" = "" ] ; then
			PACKAGES="${PACKAGES} $PKG"
			let "REAL_AMOUNT=REAL_AMOUNT+1"
		fi
	done
fi
AMOUNT=0
for PKG in $PACKAGES ; do
	let "AMOUNT=AMOUNT+1"
done
echo "============================================================================="
echo "The following $AMOUNT source packages will be build: ${PACKAGES}"
echo "============================================================================="
echo
rm -f $TMPFILE

cleanup_all() {
	rm -r $TMPDIR
}

cleanup_userContent() {
	rm -f /var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_*.rbuild.log > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/dbd/${SRCPACKAGE}_*.debbindiff.html > /dev/null 2>&1
	rm -f /var/lib/jenkins/userContent/buildinfo/${SRCPACKAGE}_*.buildinfo > /dev/null 2>&1
}

cleanup_prebuild() {
	rm b1 b2 -rf
	rm -f ${SRCPACKAGE}_* > /dev/null 2>&1
}

TMPDIR=$(mktemp --tmpdir=$PWD -d)
NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
COUNT_TOTAL=0
COUNT_GOOD=0
COUNT_BAD=0
COUNT_SKIPPED=0
GOOD=""
BAD=""
SOURCELESS=""
SKIPPED=""
trap cleanup_all INT TERM EXIT
cd $TMPDIR
for SRCPACKAGE in ${PACKAGES} ; do
	set +x
	echo "============================================================================="
	echo "Trying to build ${SRCPACKAGE} reproducibly now."
	echo "============================================================================="
	set -x
	let "COUNT_TOTAL=COUNT_TOTAL+1"
	cleanup_prebuild
	set +e
	DATE=$(date +'%Y-%m-%d %H:%M')
	VERSION=$(apt-cache showsrc ${SRCPACKAGE} | grep ^Version | cut -d " " -f2 | sort -r | head -1)
	# check if we tested this version already before...
	STATUS=$(sqlite3 ${PACKAGES_DB} "SELECT status FROM source_packages WHERE name = \"${SRCPACKAGE}\" AND version = \"${VERSION}\"")
	# skip if we know this version and status = reproducible or unreproducible or FTBFS
	if [ "$STATUS" = "reproducible" ] || [ "$STATUS" = "unreproducible" ] || [ "$STATUS" = "FTBFS" ] ; then
		echo "Package ${SRCPACKAGE} (${VERSION}) with status '$STATUS' skipped, no newer version available."
		let "COUNT_SKIPPED=COUNT_SKIPPED+1"
		SKIPPED="${SRCPACKAGE} ${SKIPPED}"
		continue
	fi
	RBUILDLOG=/var/lib/jenkins/userContent/rbuild/${SRCPACKAGE}_None.rbuild.log
	echo "Starting to build ${SRCPACKAGE} on $DATE" | tee ${RBUILDLOG}
	# host has only sid in deb-src in sources.list
	apt-get source --download-only --only-source ${SRCPACKAGE} >> ${RBUILDLOG} 2>&1
	RESULT=$?
	if [ $RESULT != 0 ] ; then
		echo "Warning: Download of ${SRCPACKAGE} sources failed." | tee -a ${RBUILDLOG}
		ls -l ${SRCPACKAGE}* | tee -a ${RBUILDLOG}
		SOURCELESS="${SOURCELESS} ${SRCPACKAGE}"
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"None\", \"404\", \"$DATE\")"
		set +x
		echo "Warning: Maybe there was a network problem, or ${SRCPACKAGE} is not a source package, or was removed or renamed. Please investigate." | tee -a ${RBUILDLOG}
		continue
	else
		VERSION=$(grep "^Version: " ${SRCPACKAGE}_*.dsc| grep -v "GnuPG v" | sort -r | head -1 | cut -d " " -f2-)
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
			echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"${ARCHITECTURES}\" and thus was skipped." | tee -a ${RBUILDLOG}
			let "COUNT_SKIPPED=COUNT_SKIPPED+1"
			SKIPPED="${SRCPACKAGE} ${SKIPPED}"
			dcmd rm ${SRCPACKAGE}_${EVERSION}.dsc
			continue
		fi
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
			if [ $RESULT -eq 124 ] ; then
				echo "$(date) - debbindiff.py was killed after running into timeouot..." | tee -a ${RBUILDLOG}
			elif [ $RESULT -eq 1 ] ; then
				echo "$(date) - debbindiff.py crashed..." | tee -a ${RBUILDLOG}
			fi
			if [ ! -f ./${LOGFILE} ] && [ -f b1/${BUILDINFO} ] ; then
				cp b1/${BUILDINFO} /var/lib/jenkins/userContent/buildinfo/
				figlet ${SRCPACKAGE}
				echo
				echo "${SRCPACKAGE} built successfully and reproducibly."
				sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"reproducible\",  \"$DATE\")"
				let "COUNT_GOOD=COUNT_GOOD+1"
				GOOD="${SRCPACKAGE} ${GOOD}"
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
				set +x
				echo -n "${SRCPACKAGE} failed to build reproducibly."
				if [ ! -f b1/${BUILDINFO} ] ; then
					echo " .buildinfo file is missing."
				else
					echo
				fi
				let "COUNT_BAD=COUNT_BAD+1"
				BAD="${SRCPACKAGE} ${BAD}"
			fi
			set -x
			rm b1 b2 -rf
		else
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"FTBFS\", \"$DATE\")"
			set +x
			echo "${SRCPACKAGE} failed to build from source."
		fi
		set -x
		dcmd rm ${SRCPACKAGE}_${EVERSION}.dsc
		rm -f ${SRCPACKAGE}_* > /dev/null 2>&1
	fi

	set +x
	echo "============================================================================="
	echo "$COUNT_TOTAL of $AMOUNT done. Previous package: ${SRCPACKAGE}"
	echo "============================================================================="
	set -x
done
cd ..
cleanup_all
trap - INT TERM EXIT

set +x
echo
echo
echo "$COUNT_TOTAL packages attempted to build in total."
echo "$COUNT_GOOD packages successfully built reproducibly: ${GOOD}"
echo "$COUNT_SKIPPED packages skipped (either because they were successfully built reproducibly in the past or because they are not Architecture: 'any' nor 'all' nor 'amd64'): ${SKIPPED}"
echo "$COUNT_BAD packages failed to built reproducibly: ${BAD}"
echo "The following source packages doesn't exist in sid: $SOURCELESS"
