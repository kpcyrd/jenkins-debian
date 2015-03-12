#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

#
# init some variables
#
ARCH="amd64"  # we only care about amd64 status here (for now)
# we only do stats up until yesterday... we also could do today too but not update the db yet...
DATE=$(date -d "1 day ago" '+%Y-%m-%d')
FORCE_DATE=$(date -d "2 day ago" '+%Y-%m-%d')
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
TABLE[4]=stats_notes
TABLE[5]=stats_issues
TABLE[6]=stats_meta_pkg_state
TABLE[7]=stats_bugs_state
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness buildinfo cpu signatures environment umask"
FIELDS[0]="datum, reproducible, unreproducible, FTBFS, other, untested"
FIELDS[1]="datum"
for i in reproducible unreproducible FTBFS other ; do
	for j in $SUITES ; do
		FIELDS[1]="${FIELDS[1]}, ${i}_${j}"
	done
done
FIELDS[2]="datum, oldest"
FIELDS[3]="datum "
for TAG in $USERTAGS ; do
	FIELDS[3]="${FIELDS[3]}, open_$TAG, done_$TAG"
done
FIELDS[4]="datum, packages_with_notes"
FIELDS[5]="datum, known_issues"
FIELDS[6]="datum, reproducible, unreproducible, FTBFS, other"
FIELDS[7]="datum, done_bugs, open_bugs"
SUM_DONE="(0"
SUM_OPEN="(0"
for TAG in $USERTAGS ; do
	SUM_DONE="$SUM_DONE+done_$TAG"
	SUM_OPEN="$SUM_OPEN+open_$TAG"
done
SUM_DONE="$SUM_DONE)"
SUM_OPEN="$SUM_OPEN)"
COLOR[0]=5
COLOR[1]=12
COLOR[2]=1
COLOR[3]=28
COLOR[4]=1
COLOR[5]=1
COLOR[6]=4
COLOR[7]=2
MAINLABEL[1]="Amount of packages built each day"
MAINLABEL[3]="Bugs with usertags for user reproducible-builds@lists.alioth.debian.org"
MAINLABEL[4]="Packages which have notes"
MAINLABEL[5]="Identified issues"
MAINLABEL[7]="Open and closed bugs"
YLABEL[0]="Amount (total)"
YLABEL[1]="Amount (per day)"
YLABEL[2]="Age in days"
YLABEL[3]="Amount of bugs"
YLABEL[4]="Amount of packages"
YLABEL[5]="Amount of issues"
YLABEL[7]="Amount of bugs open / closed"

#
# update package + build stats
#
update_suite_stats() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,suite from ${TABLE[0]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\"")
	if [ -z $RESULT ] ; then
		echo "Updating packages and builds stats for $SUITE on $DATE."
		ALL=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(name) FROM sources WHERE suite='${SUITE}'")
		GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE';")
		GOOAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'reproducible' AND date(r.build_date)='$DATE';")
		BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE';")
		BAAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND date(r.build_date)='$DATE';")
		UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE';")
		UGLDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND date(r.build_date)='$DATE';")
		REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND s.suite='$SUITE' AND date(r.build_date)<='$DATE';")
		RESDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND s.suite='$SUITE' AND date(r.build_date)='$DATE';")
		OLDESTG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.status = 'reproducible' AND s.suite='$SUITE' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		OLDESTB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		OLDESTU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		DIFFG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTG');")
		if [ -z $DIFFG ] ; then DIFFG=0 ; fi
		DIFFB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTB');")
		if [ -z $DIFFB ] ; then DIFFB=0 ; fi
		DIFFU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTU');")
		if [ -z $DIFFU ] ; then DIFFU=0 ; fi
		let "TOTAL=GOOD+BAD+UGLY+REST" || true # let FOO=0+0 returns error in bash...
		if [ "$ALL" != "$TOTAL" ] ; then
			let "UNTESTED=ALL-TOTAL"
		else
			UNTESTED=0
		fi
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[0]} VALUES (\"$DATE\", \"$SUITE\", $UNTESTED, $GOOD, $BAD, $UGLY, $REST)" 
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[1]} VALUES (\"$DATE\", \"$SUITE\", $GOOAY, $BAAY, $UGLDAY, $RESDAY)"
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[2]} VALUES (\"$DATE\", \"$SUITE\", \"$DIFFG\", \"$DIFFB\", \"$DIFFU\")"
		# we do 3 later and 6 is special anyway...
		for i in 0 1 2 4 5 ; do
			PREFIX=""
			if [ $i -eq 0 ] ; then
				PREFIX=$SUITE
			fi
			# force regeneration of the image if it exists
			if [ -f /var/lib/jenkins/userContent/$PREFIX/${TABLE[$i]}.png ] ; then
				echo "Touching $PREFIX/${TABLE[$i]}.png..."
				touch -d "$FORCE_DATE 00:00" /var/lib/jenkins/userContent/$PREFIX/${TABLE[$i]}.png
			fi
		done
	fi
}

#
# update notes stats
#
update_notes_stats() {
	NOTES_GIT_PATH="/var/lib/jenkins/jobs/reproducible_html_notes/workspace"
	if [ ! -d ${NOTES_GIT_PATH} ] ; then
		echo "Warning: ${NOTES_GIT_PATH} does not exist, has the job been renamed???"
		echo "Please investigate and fix!"
		exit 1
	elif [ ! -f ${NOTES_GIT_PATH}/packages.yml ] || [ ! -f ${NOTES_GIT_PATH}/issues.yml ] ; then
		echo "Warning: ${NOTES_GIT_PATH}/packages.yml or issues.yml does not exist, something has changed in notes.git it seems."
		echo "Please investigate and fix!"
		exit 1
	fi
	NOTES=$(grep -c -v "^ " ${NOTES_GIT_PATH}/packages.yml)
	ISSUES=$(grep -c -v "^ " ${NOTES_GIT_PATH}/issues.yml)
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum from ${TABLE[4]} WHERE datum = \"$DATE\"")
	if [ -z $RESULT ] ; then
		echo "Updating notes stats for $DATE."
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[4]} VALUES (\"$DATE\", \"$NOTES\")"
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[5]} VALUES (\"$DATE\", \"$ISSUES\")"
	fi
}

#
# gather suite stats
#
gather_suite_stats() {
	AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT count(*) FROM sources WHERE suite=\"${SUITE}\"")
	COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite=\"${SUITE}\"")
	COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite=\"${SUITE}\" AND r.status=\"reproducible\"")
	COUNT_BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = \"unreproducible\"")
	COUNT_UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = \"FTBFS\"")
	COUNT_SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = \"404\"")
	COUNT_NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = \"not for us\"")
	COUNT_BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = \"blacklisted\"")
	COUNT_OTHER=$(( $COUNT_SOURCELESS+$COUNT_NOTFORUS+$COUNT_BLACKLISTED ))
	PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
	PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
	PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
	PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
	PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
	PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
	PERCENT_OTHER=$(echo "scale=1 ; ($COUNT_OTHER*100/$COUNT_TOTAL)" | bc)
}

#
# gather meta pkg stats
#
gather_meta_stats() {
	if [ -f /srv/reproducible-results/meta_pkgsets/${META_PKGSET[$1]}.pkgset ] ; then
		META_LIST=$(cat /srv/reproducible-results/meta_pkgsets/${META_PKGSET[$1]}.pkgset)
		if [ ! -z "$META_LIST" ] ; then
			META_WHERE=""
			for PKG in $META_LIST ; do
				if [ -z "$META_WHERE" ] ; then
					META_WHERE="s.name in ('$PKG'"
				else
					META_WHERE="$META_WHERE, '$PKG'"
				fi
			done
			META_WHERE="$META_WHERE)"
		else
			META_WHERE="name = 'meta-name-does-not-exist'"
		fi
		COUNT_META_GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		COUNT_META_BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		COUNT_META_UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		COUNT_META_REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		let META_ALL=COUNT_META_GOOD+COUNT_META_BAD+COUNT_META_UGLY+COUNT_META_REST
		PERCENT_META_GOOD=$(echo "scale=1 ; ($COUNT_META_GOOD*100/$META_ALL)" | bc)
		PERCENT_META_BAD=$(echo "scale=1 ; ($COUNT_META_BAD*100/$META_ALL)" | bc)
		PERCENT_META_UGLY=$(echo "scale=1 ; ($COUNT_META_UGLY*100/$META_ALL)" | bc)
		PERCENT_META_REST=$(echo "scale=1 ; ($COUNT_META_REST*100/$META_ALL)" | bc)
		# order reproducible packages by name, the rest by build_date
		META_GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE ORDER BY s.name;")
		META_BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE ORDER BY r.build_date;")
		META_UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE' AND $META_WHERE ORDER BY r.build_date;")
		META_REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name AS NAME FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND date(r.build_date)<='$DATE' AND $META_WHERE ORDER BY r.build_date;")
	else
		META_RESULT=false
	fi
}

#
# update meta pkg stats
#
update_meta_pkg_stats() {
	for i in $(seq 1 ${#META_PKGSET[@]}) ; do
		RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,meta_pkg,suite from ${TABLE[6]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\" AND meta_pkg = \"${META_PKGSET[$i]}\"")
		if [ -z $RESULT ] ; then
			META_RESULT=true
			gather_meta_stats $i
			if $META_RESULT ; then
				 sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[6]} VALUES (\"$DATE\", \"$SUITE\", \"${META_PKGSET[$i]}\", $COUNT_META_GOOD, $COUNT_META_BAD, $COUNT_META_UGLY, $COUNT_META_REST)"
				echo "Updating meta pkg set stats for ${META_PKGSET[$1]} in $SUITE on $DATE."
			fi
			echo "Touching $SUITE/$ARCH/${TABLE[6]}_${META_PKGSET[$i]}.png..."
			touch -d "$FORCE_DATE 00:00" /var/lib/jenkins/userContent/$SUITE/$ARCH/${TABLE[6]}_${META_PKGSET[$i]}.png
		fi
	done
}

#
# update bug stats
#
update_bug_stats() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
	if [ -z $RESULT ] ; then
		echo "Updating bug stats for $DATE."
		declare -a DONE
		declare -a OPEN
		SQL="INSERT INTO ${TABLE[3]} VALUES (\"$DATE\" "
		for TAG in $USERTAGS ; do
			OPEN[$TAG]=$(bts select usertag:$TAG users:reproducible-builds@lists.alioth.debian.org status:open status:forwarded 2>/dev/null|wc -l)
			DONE[$TAG]=$(bts select usertag:$TAG users:reproducible-builds@lists.alioth.debian.org status:done archive:both 2>/dev/null|wc -l)
			# test if both values are integers
			if ! ( [[ ${DONE[$TAG]} =~ ^-?[0-9]+$ ]] && [[ ${OPEN[$TAG]} =~ ^-?[0-9]+$ ]] ) ; then
				echo "Non-integers value detected, exiting."
				echo "Usertag: $TAG"
				echo "Open: ${OPEN[$TAG]}"
				echo "Done: ${DONE[$TAG]}"
				exit 1
			fi
			SQL="$SQL, ${OPEN[$TAG]}, ${DONE[$TAG]}"
		done
		SQL="$SQL)"
		echo $SQL
		sqlite3 -init ${INIT} ${PACKAGES_DB} "$SQL"
		# force regeneration of the image
		echo "Touching ${TABLE[3]}.png..."
		touch -d "$FORCE_DATE 00:00" /var/lib/jenkins/userContent/${TABLE[3]}.png
		echo "Touching ${TABLE[7]}.png..."
		touch -d "$FORCE_DATE 00:00" /var/lib/jenkins/userContent/${TABLE[7]}.png
	fi
}

#
# create the png (and query the db to populate a csv file...)
#
create_png_from_table() {
	echo "Checking whether to update $2..."
	# $1 = id of the stats table
	# $2 = image file name
	# $3 = meta package set, only sensible if $1=6
	echo "${FIELDS[$1]}" > ${TABLE[$1]}.csv
	# prepare query
	WHERE_EXTRA="WHERE suite = '$SUITE'"
	if [ $1 -eq 3 ] || [ $1 -eq 4 ] || [ $1 -eq 5 ] ; then
		# TABLE[3+4+5] don't have a suite column:
		WHERE_EXTRA=""
	elif [ $1 -eq 6 ] ; then
		# 6 is special too:
		WHERE_EXTRA="WHERE suite = '$SUITE' and meta_pkg = '$3'"
	fi
	# run query
	if [ $1 -eq 1 ] ; then
		# not sure if it's worth to generate the following query...
		sqlite3 -init ${INIT} --nullvalue 0 -csv ${PACKAGES_DB} "select s.datum,
			 s.reproducible as 'reproducible_sid',
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e where s.datum=e.datum and suite='experimental'),0) as 'reproducible_experimental', 
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e where s.datum=e.datum and suite='testing'),0) as 'reproducible_testing',
			 s.unreproducible as 'unreproducible_sid',
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental') AS unreproducible_experimental,
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing') AS unreproducible_testing,
			 s.FTBFS as 'FTBFS_sid',
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental') AS FTBFS_experimental,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing') AS FTBFS_testing,
			 s.other as 'other_sid',
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental') AS other_experimental,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing') AS other_testing
			 FROM stats_builds_per_day AS s WHERE s.suite='sid' GROUP BY s.datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 2 ] ; then
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, ((oldest_reproducible + oldest_unreproducible + oldest_FTBFS)/3) FROM ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 7 ] ; then
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, $SUM_DONE, $SUM_OPEN from ${TABLE[3]} ORDER BY datum" >> ${TABLE[$1]}.csv
	else
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$1]} from ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	fi
	# only generate graph if the query returned data
	if [ $(cat ${TABLE[$1]}.csv | wc -l) -gt 1 ] ; then
		echo "Updating $2..."
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Generating $2."
		/srv/jenkins/bin/make_graph.py ${TABLE[$1]}.csv $2 ${COLOR[$1]} "${MAINLABEL[$1]}" "${YLABEL[$1]}"
		mv $2 /var/lib/jenkins/userContent/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	fi
	rm ${TABLE[$1]}.csv
}

#
# gather bugs stats and generate html table
#
write_usertag_table() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
	if [ -z "$RESULTS" ] ; then
		COUNT=0
		TOPEN=0 ; TDONE=0 ; TTOTAL=0
		for FIELD in $(echo ${FIELDS[3]} | tr -d ,) ; do
			let "COUNT+=1"
			VALUE=$(echo $RESULT | cut -d "|" -f$COUNT)
			if [ $COUNT -eq 1 ] ; then
				write_page "<table class=\"main\"><tr><th>Bugs per usertag on $VALUE</th><th>Open</th><th>Done</th><th>Total</th></tr>"
			elif [ $((COUNT%2)) -eq 0 ] ; then
				write_page "<tr><td><a href=\"https://bugs.debian.org/cgi-bin/pkgreport.cgi?tag=${FIELD:5};users=reproducible-builds@lists.alioth.debian.org&archive=both\">${FIELD:5}</a></td><td>$VALUE</td>"
				TOTAL=$VALUE
				let "TOPEN=TOPEN+VALUE"
			else
				write_page "<td>$VALUE</td>"
				let "TOTAL=TOTAL+VALUE" || true # let FOO=0+0 returns error in bash...
				let "TDONE=TDONE+VALUE"
				write_page "<td>$TOTAL</td></tr>"
				let "TTOTAL=TTOTAL+TOTAL"
			fi
		done
		write_page "<tr><td>All usertagged bugs for reproducible-builds@lists.alioth.debian.org</td><td>$TOPEN</td><td>$TDONE</td><td>$TTOTAL</td></tr>"
		write_page "</table>"
	fi
}

#
# create suite stats page
#
create_suite_stats_page() {
	VIEW=suite_stats
	PAGE=index_${VIEW}.html
	MAINLABEL[0]="Reproducibility status for packages in '$SUITE'"
	MAINLABEL[2]="Age in days of oldest build in '$SUITE'"
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of reproducible builds for packages in $SUITE"
	if [ $(echo $PERCENT_TOTAL/1|bc) -lt 98 ] ; then
		write_page "<p>$COUNT_TOTAL packages have been attempted to be build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently.</p>"
	fi
	write_page "<p>"
	set_icon reproducible
	write_icon
	write_page "$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly in $SUITE/$ARCH."
	set_icon unreproducible
	write_icon
	write_page "$COUNT_BAD packages ($PERCENT_BAD%) failed to built reproducibly."
	set_icon FTBFS
	write_icon
	write_page "$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source.</p>"
	write_page "<p>"
	if [ $COUNT_SOURCELESS -gt 0 ] ; then
		write_page "For "
		set_icon 404
		write_icon
		write_page "$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) packages sources could not be downloaded,"
	fi
	set_icon not_for_us
	write_icon
	write_page "$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any', 'all', 'amd64', 'linux-any', 'linux-amd64' nor 'any-amd64' will not be build here"
	write_page "and those "
	set_icon blacklisted
	write_icon
	write_page "$COUNT_BLACKLISTED blacklisted packages neither.</p>"
	write_page "<p>"
	write_page " <a href=\"/userContent/$SUITE/${TABLE[0]}.png\"><img src=\"/userContent/$SUITE/${TABLE[0]}.png\" alt=\"${MAINLABEL[0]}\"></a>"
	for i in 0 2 ; do
		# recreate png once a day
		if [ ! -f /var/lib/jenkins/userContent/$SUITE/${TABLE[$i]}.png ] || [ ! -z $(find /var/lib/jenkins/userContent/$SUITE -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
			create_png_from_table $i $SUITE/${TABLE[$i]}.png
		fi
	done
	write_page "</p>"
	write_page_footer
	publish_page $SUITE
}

#
# create pkg sets page
#
create_pkg_sets_page() {
	VIEW=pkg_sets
	PAGE=index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview about reproducible builds of specific package sets in $SUITE/$ARCH"
	write_page "<ul><li>Tracked package sets in $SUITE: </li>"
	for i in $(seq 1 ${#META_PKGSET[@]}) ; do
		if [ -f /var/lib/jenkins/userContent/$SUITE/$ARCH/${TABLE[6]}_${META_PKGSET[$i]}.png ] ; then
			write_page "<li><a href=\"#${META_PKGSET[$i]}\">${META_PKGSET[$i]}</a></li>"
		fi
	done
	write_page "</ul>"
	for i in $(seq 1 ${#META_PKGSET[@]}) ; do
		write_page "<hr /><a name=\"${META_PKGSET[$i]}\"></a>"
		META_RESULT=true
		gather_meta_stats $i	# FIXME: this ignores unknown packages...
		if $META_RESULT ; then
			MAINLABEL[6]="Reproducibility status for packages in $SUITE from '${META_PKGSET[$i]}'"
			YLABEL[6]="Amount (${META_PKGSET[$i]} packages)"
			PNG=${TABLE[6]}_${META_PKGSET[$i]}.png
			# redo pngs once a day
			if [ ! -f /var/lib/jenkins/userContent/$SUITE/$ARCH/$PNG ] || [ ! -z $(find /var/lib/jenkins/userContent/$SUITE/$ARCH -maxdepth 1 -mtime +0 -name $PNG) ] ; then
				create_png_from_table 6 $SUITE/$ARCH/$PNG ${META_PKGSET[$i]}
			fi
			write_page "<p><a href=\"/userContent/$SUITE/$ARCH/$PNG\"><img src=\"/userContent/$SUITE/$ARCH/$PNG\" alt=\"${MAINLABEL[6]}\"></a>"
			write_page "<br />The package set '${META_PKGSET[$i]}' in $SUITE/$ARCH consists of: <br />"
			set_icon reproducible
			write_icon
			write_page "$COUNT_META_GOOD packages ($PERCENT_META_GOOD%) successfully built reproducibly:"
			set_linktarget $META_GOOD
			link_packages $META_GOOD
			write_page "<br />"
			set_icon unreproducible
			write_icon
			write_page "$COUNT_META_BAD ($PERCENT_META_BAD%) packages failed to built reproducibly:"
			set_linktarget $META_BAD
			link_packages $META_BAD
			write_page "<br />"
			if [ $COUNT_META_UGLY -gt 0 ] ; then
				set_icon FTBFS
				write_icon
				write_page "$COUNT_META_UGLY ($PERCENT_META_UGLY%) packages failed to build from source:"
				set_linktarget $META_UGLY
				link_packages $META_UGLY
				write_page "<br />"
			fi
			if [ $COUNT_META_REST -gt 0 ] ; then
				set_icon not_for_us
				write_icon
				set_icon blacklisted
				write_icon
				set_icon 404
				write_icon
				write_page "$COUNT_META_REST ($PERCENT_META_REST%) packages are either blacklisted, not for us or cannot be downloaded:"
				set_linktarget $META_REST
				link_packages $META_REST
				write_page "<br />"
			fi
			write_page "</p>"
		fi
		write_page_meta_sign
	done
	write_page_footer
	publish_page $SUITE/$ARCH
}

#
# create main stats page
#
create_main_stats_page() {
	VIEW=stats
	PAGE=index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of various statistics about reproducible builds"
	# write suite graphs
	write_page "<p>"
	for SUITE in $SUITES ; do
		write_page " <a href=\"/$SUITE\"><img src=\"/userContent/$SUITE/${TABLE[0]}.png\" class=\"overview\" alt=\"$SUITE stats\"></a>"
	done
	write_page "</p><p>"
	# write meta pkg graphs per suite
	for SUITE in $SUITES ; do
		if [ "$SUITE" != "sid" ] ; then
			# FIXME: no pkg sets in experimental
			continue
		fi
		for i in $(seq 1 ${#META_PKGSET[@]}) ; do
			PNG=${TABLE[6]}_${META_PKGSET[$i]}.png
			LABEL="Reproducibility status for packages in $SUITE/$ARCH from '${META_PKGSET[$i]}'"
			write_page "<a href=\"/$SUITE/$ARCH/index_pkg_sets.html#${META_PKGSET[$i]}\"><img src=\"/userContent/$SUITE/$ARCH/$PNG\" class=\"metaoverview\" alt=\"$LABEL\"></a>"
		done
	done
	write_page "</p><p>"
	# write suite table
	write_page "<table class=\"main\"><tr><th>suite</th><th>sources in total on $DATE</th><th>reproducible packages</th><th>unreproducible packages</th><th>packages failing to build</th><th>other packages</th></tr>"
	for SUITE in $SUITES ; do
		gather_suite_stats
		write_page "<tr><td>$SUITE</td><td>$AMOUNT</td><td>$COUNT_GOOD / $PERCENT_GOOD%</td><td>$COUNT_BAD / $PERCENT_BAD%</td><td>$COUNT_UGLY / $PERCENT_UGLY%</td><td>$COUNT_OTHER / $PERCENT_OTHER%</td></tr>"
	done
        write_page "</table>"
	# write inventory table
	write_page "<table class=\"main\"><tr><th>inventory type</th><th>amount on $DATE</th></tr>"
	write_page "<tr><td>packages with notes</td><td>$NOTES</td></tr>"
	write_page "<tr><td>issues categorized</td><td>$ISSUES</td></tr>"
	write_page "</table>"
	# other graphs
	# FIXME: we don't do 2 / stats_builds_age.png yet :/ (and 6 and 0 are done already)
	for i in 3 7 4 5 1 ; do
		write_page " <a href=\"/userContent/${TABLE[$i]}.png\"><img src=\"/userContent/${TABLE[$i]}.png\" alt=\"${MAINLABEL[$i]}\"></a>"
		# redo pngs once a day
		if [ ! -f /var/lib/jenkins/userContent/${TABLE[$i]}.png ] || [ ! -z $(find /var/lib/jenkins/userContent -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
			create_png_from_table $i ${TABLE[$i]}.png
		fi
		if [ "$i" = "3" ] ; then
			write_usertag_table
		fi
	done
	write_page "</p>"
	# write suite builds age graphs
	write_page "<p>"
	for SUITE in $SUITES ; do
		write_page " <a href=\"/$SUITE\"><img src=\"/userContent/$SUITE/${TABLE[2]}.png\" class=\"overview\" alt=\"$SUITE builds age\"></a>"
	done
	write_page "</p><p>"
	# the end
	write_page_footer
	publish_page
}

#
# main
#
SUITE="sid"
update_bug_stats
update_notes_stats
create_main_stats_page
for SUITE in $SUITES ; do
	update_suite_stats
	gather_suite_stats
	create_suite_stats_page
	if [ "$SUITE" != "sid" ] ; then
		# FIXME: should be: no pkg sets in experimental
		continue
	fi
	update_meta_pkg_stats
	create_pkg_sets_page
done

