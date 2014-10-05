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
	# update amount of available packages (for doing statistics later)
	P_IN_SOURCES=$(xzcat $TMPFILE | grep "^Package" | grep -v "^Package-List:" | cut -d " " -f2 | sort -u | wc -l)
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
	CANDIDATES=$(xzcat $TMPFILE | grep "^Package" | grep -v "^Package-List:" |  cut -d " " -f2 | egrep -v "^(linux|cups|zurl)$" | sort -R | head -$GUESSES | xargs echo)
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
	PACKAGES=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT DISTINCT source_packages.name FROM source_packages,sources WHERE sources.version IN (SELECT version FROM sources WHERE name=source_packages.name ORDER by sources.version DESC LIMIT 1) AND (( source_packages.status = 'unreproducible' OR source_packages.status = 'FTBFS') AND source_packages.name = sources.name AND source_packages.version < sources.version) ORDER BY source_packages.build_date LIMIT $AMOUNT" | xargs -r echo)
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
echo "The following $AMOUNT source packages will be scheduled: ${PACKAGES}"
echo "============================================================================="
echo
rm -f $TMPFILE

