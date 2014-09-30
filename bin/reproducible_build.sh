#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# FIXME: needed as long as #763328 (RFP: /usr/bin/diffp) is unfixed...
# fetch git repo for the diffp command used later
if [ -d debbindiff.git ] ; then
	cd debbindiff.git
	git pull
	cd ..
else
	git clone git://git.debian.org/git/reproducible/debbindiff.git debbindiff.git
fi

# create dirs for results
mkdir -p results/
mkdir -p /var/lib/jenkins/userContent/diffp/ /var/lib/jenkins/userContent/pbuilder/

# create sqlite db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
if [ ! -f ${PACKAGES_DB} ] ; then
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE source_packages
		(name TEXT NOT NULL,
		version TEXT NOT NULL,
		status TEXT NOT NULL
		CHECK (status IN ("FTBFS","reproducible","unreproducible","404", "not for us")),
		build_date TEXT NOT NULL,
		diffp_path TEXT,
		PRIMARY KEY (name))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE source_stats
		(suite TEXT NOT NULL,
		amount INTEGER NOT NULL,
		PRIMARY KEY (suite))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE job_sources
		(name TEXT NOT NULL,
		job TEXT NOT NULL)'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE sources
		(name TEXT NOT NULL,
		version TEXT NOT NULL)'
fi
# 30 seconds timeout when trying to get a lock
INIT=/var/lib/jenkins/reproducible.init
cat >/var/lib/jenkins/reproducible.init <<-EOF
.timeout 30000
EOF

# this needs sid entries in sources.list:
grep deb-src /etc/apt/sources.list | grep sid
# try apt-get update twice, else fail gracefully, aka not.
sudo apt-get update || ( sleep $(( $RANDOM % 70 + 30 )) ; sudo apt-get update || true )

set +x
# if $1 is an integer, build $1 random packages
if [[ $1 =~ ^-?[0-9]+$ ]] ; then
	TMPFILE=$(mktemp)
	curl http://ftp.de.debian.org/debian/dists/sid/main/source/Sources.xz > $TMPFILE
	AMOUNT=$1
	if [ $AMOUNT -gt 0 ] ; then
		REAL_AMOUNT=0
		GUESSES=$(echo "${AMOUNT}*3" | bc)
		PACKAGES=""
		CANDIDATES=$(xzcat $TMPFILE | grep "^Package" | grep -v "^Package-List:" |  cut -d " " -f2 | egrep -v "^linux$" | sort -R | head -$GUESSES | xargs echo)
		for PKG in $CANDIDATES ; do
			if [ $REAL_AMOUNT -eq $AMOUNT ] ; then
				continue
			fi
			RESULT=$(sqlite3 ${PACKAGES_DB} "SELECT name FROM source_packages WHERE name = \"${PKG}\"")
			if [ "$RESULT" = "" ] ; then
				PACKAGES="${PACKAGES} $PKG"
				let "REAL_AMOUNT=REAL_AMOUNT+1"
			fi
		done
		AMOUNT=$REAL_AMOUNT
		for PKG in $PACKAGES ; do
			RESULT=$(sqlite3 ${PACKAGES_DB} "SELECT name FROM job_sources WHERE ( name = '${PKG}' AND job = 'random' )")
			if [ "$RESULT" = "" ] ; then
				sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO job_sources VALUES ('$PKG','random')"
			fi
		done
	else
		# this is kind of a hack: if $1 is 0, then schedule 33 failed packages which were nadomly picked and where a new version is available
		CSVFILE=$(mktemp)
		sqlite3 -csv -init $INIT ${PACKAGES_DB} "DELETE from sources"
		(xzcat $TMPFILE | egrep "(^Package:|^Version:)" | sed -s "s#^Version: ##g; s#Package: ##g; s#\n# #g"| while read PKG ; do read VERSION ; echo "$PKG,$VERSION" ; done) > $CSVFILE
		echo ".import $CSVFILE sources" | sqlite3 -csv -init $INIT ${PACKAGES_DB}
		rm $CSVFILE
		AMOUNT=33
		PACKAGES=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT DISTINCT source_packages.name FROM source_packages,sources,job_sources  WHERE (( source_packages.status = 'unreproducible' OR source_packages.status = 'FTBFS') AND source_packages.name = job_sources.name AND source_packages.name = sources.name AND job_sources.job = 'random' AND source_packages.version != sources.version) ORDER BY source_packages.build_date LIMIT $AMOUNT" | xargs -r echo)
		AMOUNT=0
		for PKG in $PACKAGES ; do
			let "AMOUNT=AMOUNT+1"
		done
	fi
	# update amount of available packages (for doing statistics later)
	P_IN_SOURCES=$(xzcat $TMPFILE | grep "^Package" | grep -v "^Package-List:" | cut -d " " -f2 | sort -u | wc -l)
	sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_stats VALUES (\"sid\", \"${P_IN_SOURCES}\")"
	rm $TMPFILE
else
	PACKAGES="$@"
	AMOUNT="${#@}"
	JOB=$(echo $JOB_NAME|cut -d "_" -f3-)
	for PKG in $PACKAGES ; do
		RESULT=$(sqlite3 ${PACKAGES_DB} "SELECT name FROM job_sources WHERE ( name = '${PKG}' AND job = '$JOB' )")
		if [ "$RESULT" = "" ] ; then
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO job_sources VALUES ('$PKG','$JOB')"
		fi
	done
fi
echo "============================================================================="
echo "The following source packages will be build: ${PACKAGES}"
echo "============================================================================="
echo

NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
COUNT_TOTAL=0
COUNT_GOOD=0
COUNT_BAD=0
COUNT_SKIPPED=0
GOOD=""
BAD=""
SOURCELESS=""
SKIPPED=""
for SRCPACKAGE in ${PACKAGES} ; do
	set +x
	echo "============================================================================="
	echo "Trying to build ${SRCPACKAGE} reproducibly now."
	echo "============================================================================="
	set -x
	let "COUNT_TOTAL=COUNT_TOTAL+1"
	rm b1 b2 -rf
	set +e
	DATE=$(date +'%Y-%m-%d %H:%M')
	VERSION=$(apt-cache showsrc ${SRCPACKAGE} | grep ^Version | cut -d " " -f2 | sort -r | head -1)
	# check if we tested this version already before...
	STATUS=$(sqlite3 ${PACKAGES_DB} "SELECT status FROM source_packages WHERE name = \"${SRCPACKAGE}\" AND version = \"${VERSION}\"")
	# if reproducible or ( unreproducible/FTBFS by 50% chance )
	if [ "$STATUS" = "reproducible" ] || (( [ "$STATUS" = "unreproducible" ] || [ "$STATUS" = "FTBFS" ] ) && [ $(( $RANDOM % 100 )) -gt 50 ] ) ; then
		echo "Package ${SRCPACKAGE} (${VERSION}) with status '$STATUS' skipped, no newer version available."
		let "COUNT_SKIPPED=COUNT_SKIPPED+1"
		SKIPPED="${SRCPACKAGE} ${SKIPPED}"
		continue
	fi
	rm -f ${SRCPACKAGE}_* > /dev/null 2>&1
	# host has only sid in deb-src in sources.list
	apt-get source --download-only --only-source ${SRCPACKAGE}
	RESULT=$?
	if [ $RESULT != 0 ] ; then
		SOURCELESS="${SOURCELESS} ${SRCPACKAGE}"
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"404\", \"$DATE\", \"\")"
		set +x
		echo "Warning: ${SRCPACKAGE} is not a source package, or was removed or renamed. Please investigate."
		continue
	else
		VERSION=$(grep "^Version: " ${SRCPACKAGE}_*.dsc| grep -v "GnuPG v" | sort -r | head -1 | cut -d ":" -f2-)
		ARCH=$(grep "^Architecture: " ${SRCPACKAGE}_*.dsc| sort -r | head -1 | cut -d ":" -f2)
		if [[ ! "$ARCH" =~ "amd64" ]] && [[ ! "$ARCH" =~ "all" ]] && [[ ! "$ARCH" =~ "any" ]] ; then
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"not for us\", \"$DATE\", \"\")"
			echo "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$ARCH\" and was thus skipped."
			let "COUNT_SKIPPED=COUNT_SKIPPED+1"
			SKIPPED="${SRCPACKAGE} ${SKIPPED}"
			continue
		fi
		# EPOCH_FREE_VERSION was too long
		EVERSION=$(echo $VERSION | cut -d ":" -f2)
		sudo DEB_BUILD_OPTIONS="parallel=$NUM_CPU" pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid ${SRCPACKAGE}_*.dsc | tee ${SRCPACKAGE}_${EVERSION}.pbuilder.log
		if [ -f /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes ] ; then
			mkdir b1 b2
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes b1
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes
			rm ${SRCPACKAGE}_*.pbuilder.log /var/lib/jenkins/userContent/pbuilder/${SRCPACKAGE}_*.pbuilder.log
			sudo DEB_BUILD_OPTIONS="parallel=$NUM_CPU" pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid ${SRCPACKAGE}_${EVERSION}.dsc
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes b2
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_${EVERSION}_amd64.changes
			set -e
			cat b1/${SRCPACKAGE}_${EVERSION}_amd64.changes
			LOGFILE=$(ls ${SRCPACKAGE}_${EVERSION}.dsc)
			LOGFILE=$(echo ${LOGFILE%.dsc}.diffp.html)
			./debbindiff.git/debbindiff.py --html ./results/${LOGFILE} b1/${SRCPACKAGE}_${EVERSION}_amd64.changes b2/${SRCPACKAGE}_${EVERSION}_amd64.changes
			if ! $(grep -qv '^\*\*\*\*\*' ./results/${LOGFILE}) ; then
				rm -f /var/lib/jenkins/userContent/diffp/${SRCPACKAGE}_*.diffp.log > /dev/null 2>&1 
				figlet ${SRCPACKAGE}
				echo
				echo "${SRCPACKAGE} built successfully and reproducibly."
				sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"reproducible\",  \"$DATE\", \"\")"
				let "COUNT_GOOD=COUNT_GOOD+1"
				GOOD="${SRCPACKAGE} ${GOOD}"
			else
				rm -f /var/lib/jenkins/userContent/diffp/${SRCPACKAGE}_*.diffp.log > /dev/null 2>&1 
				cp ./results/${LOGFILE} /var/lib/jenkins/userContent/diffp/
				sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"unreproducible\", \"$DATE\", \"\")"
				set +x
				echo "Warning: ${SRCPACKAGE} failed to build reproducibly."
				let "COUNT_BAD=COUNT_BAD+1"
				BAD="${SRCPACKAGE} ${BAD}"
			fi
			rm b1 b2 -rf
		else
			sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES (\"${SRCPACKAGE}\", \"${VERSION}\", \"FTBFS\", \"$DATE\", \"\")"
			mv ${SRCPACKAGE}_${EVERSION}.pbuilder.log /var/lib/jenkins/userContent/pbuilder/
			set +x
			echo "Warning: ${SRCPACKAGE} failed to build from source."
		fi
		dcmd rm ${SRCPACKAGE}_${EVERSION}.dsc
		rm -f ${SRCPACKAGE}_* > /dev/null 2>&1
	fi

	set +x
	echo "============================================================================="
	echo "$COUNT_TOTAL of $AMOUNT done. Previous package: ${SRCPACKAGE}"
	echo "============================================================================="
	set -x
done

set +x
echo
echo
echo "$COUNT_TOTAL packages attempted to build in total."
echo "$COUNT_GOOD packages successfully built reproducibly: ${GOOD}"
echo "$COUNT_SKIPPED packages skipped (either because they were successfully built reproducibly in the past or because they are not Architecture: 'any' nor 'all' nor 'amd64'): ${SKIPPED}"
echo "$COUNT_BAD packages failed to built reproducibly: ${BAD}"
echo "The following source packages doesn't exist in sid: $SOURCELESS"
