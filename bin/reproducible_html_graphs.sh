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
NOTES_GIT_PATH="/var/lib/jenkins/jobs/reproducible_html_notes/workspace"

# variables related to the stats we do
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
TABLE[4]=stats_notes
TABLE[5]=stats_issues
TABLE[6]=stats_meta_pkg_state
TABLE[7]=stats_bugs_state
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
MAINLABEL[3]="Usertags on bugs for user reproducible-builds@lists.alioth.debian.org"
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
			if [ -f $BASE/$PREFIX/${TABLE[$i]}.png ] ; then
				echo "Touching $PREFIX/${TABLE[$i]}.png..."
				touch -d "$FORCE_DATE 00:00" $BASE/$PREFIX/${TABLE[$i]}.png
			fi
		done
	fi
}

#
# update notes stats
#
update_notes_stats() {
	if [ ! -d ${NOTES_GIT_PATH} ] ; then
		echo "Warning: ${NOTES_GIT_PATH} does not exist, has the job been renamed???"
		echo "Please investigate and fix!"
		exit 1
	elif [ ! -f ${NOTES_GIT_PATH}/packages.yml ] || [ ! -f ${NOTES_GIT_PATH}/issues.yml ] ; then
		# retry. sometimes these files vanish for a moment, probably when jenkins automatically updates the clones or such.
		sleep 5
		if [ ! -f ${NOTES_GIT_PATH}/packages.yml ] || [ ! -f ${NOTES_GIT_PATH}/issues.yml ] ; then
			echo "Warning: ${NOTES_GIT_PATH}/packages.yml or issues.yml does not exist, something has changed in notes.git it seems."
			echo "Please investigate and fix!"
			exit 1
		fi
	fi
	NOTES=$(grep -c -v "^ " ${NOTES_GIT_PATH}/packages.yml)
	ISSUES=$(grep -c -v "^ " ${NOTES_GIT_PATH}/issues.yml)
	COUNT_ISSUES=$(grep "    -" ${NOTES_GIT_PATH}/packages.yml | egrep -v "    - [0-9]+"|wc -l)
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
	PKGSET_PATH=/srv/reproducible-results/meta_pkgsets-$SUITE/${META_PKGSET[$1]}.pkgset
	if [ -f $PKGSET_PATH ] ; then
		META_LIST=$(cat $PKGSET_PATH)
		if [ ! -z "$META_LIST" ] ; then
			META_WHERE=""
			# gather data about all packages we know about
			# as a result, unknown packages in the package set
			# are silently ignored
			set +x
			for PKG in $META_LIST ; do
				if [ -z "$META_WHERE" ] ; then
					META_WHERE="s.name in ('$PKG'"
				else
					META_WHERE="$META_WHERE, '$PKG'"
				fi
			done
			if "$DEBUG" ; then set -x ; fi
			META_WHERE="$META_WHERE)"
		else
			META_WHERE="name = 'meta-name-does-not-exist'"
		fi
		COUNT_META_GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		COUNT_META_BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		COUNT_META_UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		COUNT_META_REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		let META_ALL=COUNT_META_GOOD+COUNT_META_BAD+COUNT_META_UGLY+COUNT_META_REST || META_ALL=1
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
			touch -d "$FORCE_DATE 00:00" $BASE/$SUITE/$ARCH/${TABLE[6]}_${META_PKGSET[$i]}.png
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
		GOT_BTS_RESULTS=false
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
			elif [ ! "${DONE[$TAG]}" = "0" ] || [ ! "${OPEN[$TAG]}" = "0" ] ; then
				GOT_BTS_RESULTS=true
			fi
			SQL="$SQL, ${OPEN[$TAG]}, ${DONE[$TAG]}"
		done
		SQL="$SQL)"
		echo $SQL
		if $GOT_BTS_RESULTS ; then
			echo "Updating ${PACKAGES_DB} with bug stats for $DATE."
			sqlite3 -init ${INIT} ${PACKAGES_DB} "$SQL"
			# force regeneration of the image
			echo "Touching ${TABLE[3]}.png..."
			touch -d "$FORCE_DATE 00:00" $BASE/${TABLE[3]}.png
			echo "Touching ${TABLE[7]}.png..."
			touch -d "$FORCE_DATE 00:00" $BASE/${TABLE[7]}.png
		fi
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
		sqlite3 -init ${INIT} --nullvalue 0 -csv ${PACKAGES_DB} "SELECT s.datum,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e where s.datum=e.datum and suite='testing'),0) as 'reproducible_testing',
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e where s.datum=e.datum and suite='unstable'),0) as 'reproducible_unstable', 
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e where s.datum=e.datum and suite='experimental'),0) as 'reproducible_experimental',
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing') AS unreproducible_testing,
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable') AS unreproducible_unstable,
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental') AS unreproducible_experimental,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing') AS FTBFS_testing,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable') AS FTBFS_unstable,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental') AS FTBFS_experimental,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing') AS other_testing,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable') AS other_unstable,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental') AS other_experimental
			 FROM stats_builds_per_day AS s GROUP BY s.datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 2 ] ; then
		# just make a graph of the oldest reproducible build (ignore FTBFS and unreproducible)
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, oldest_reproducible FROM ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 7 ] ; then
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, $SUM_DONE, $SUM_OPEN from ${TABLE[3]} ORDER BY datum" >> ${TABLE[$1]}.csv
	else
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$1]} from ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	fi
	# this is a gross hack: normally we take the number of colors a table should have...
	#  for the builds_age table we only want one color, but different ones, so this hack:
	COLORS=${COLOR[$1]}
	if [ $1 -eq 2 ] ; then
		case "$SUITE" in
			testing)	COLORS=40 ;;
			unstable)	COLORS=41 ;;
			experimental)	COLORS=42 ;;
		esac
	fi
	# only generate graph if the query returned data
	if [ $(cat ${TABLE[$1]}.csv | wc -l) -gt 1 ] ; then
		echo "Updating $2..."
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Generating $2."
		/srv/jenkins/bin/make_graph.py ${TABLE[$1]}.csv $2 ${COLORS} "${MAINLABEL[$1]}" "${YLABEL[$1]}"
		mv $2 $BASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	# create empty dummy png if there havent been any results ever
	elif [ ! -f $BASE/$DIR/$(basename $2) ] ; then
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Creating $2 dummy."
		convert -size 1920x960 xc:#aaaaaa -depth 8 $2
		if [ "$3" != "" ] ; then
			local THUMB="${TABLE[1]}_${3}-thumbnail.png"
			convert $2 -adaptive-resize 160x80 ${THUMB}
			mv ${THUMB} $BASE/$DIR
		fi
		mv $2 $BASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	fi
	rm ${TABLE[$1]}.csv
}

#
# gather bugs stats and generate html table
#
write_usertag_table() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
	if [ ! -z "$RESULT" ] ; then
		COUNT=0
		TOPEN=0 ; TDONE=0 ; TTOTAL=0
		for FIELD in $(echo ${FIELDS[3]} | tr -d ,) ; do
			let "COUNT+=1"
			VALUE=$(echo $RESULT | cut -d "|" -f$COUNT)
			if [ $COUNT -eq 1 ] ; then
				write_page "<table class=\"main\" id=\"usertagged-bugs\"><tr><th>Usertagged bugs</th><th>Open</th><th>Done</th><th>Total</th></tr>"
			elif [ $((COUNT%2)) -eq 0 ] ; then
				write_page "<tr><td><a href=\"https://bugs.debian.org/cgi-bin/pkgreport.cgi?tag=${FIELD:5};users=reproducible-builds@lists.alioth.debian.org&amp;archive=both\">${FIELD:5}</a></td><td>$VALUE</td>"
				TOTAL=$VALUE
				let "TOPEN=TOPEN+VALUE" || TOPEN=0
			else
				write_page "<td>$VALUE</td>"
				let "TOTAL=TOTAL+VALUE" || true # let FOO=0+0 returns error in bash...
				let "TDONE=TDONE+VALUE"
				write_page "<td>$TOTAL</td></tr>"
				let "TTOTAL=TTOTAL+TOTAL"
			fi
		done
		write_page "<tr><td>Total number of usertags on $DATE<br />(this is not the number of bugs as bugs can have several tags)</td><td>$TOPEN</td><td>$TDONE</td><td>$TTOTAL</td></tr>"
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
	MAINLABEL[2]="Age in days of oldest reproducible build result in '$SUITE'"
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of reproducible builds for packages in $SUITE"
	if [ $(echo $PERCENT_TOTAL/1|bc) -lt 98 ] ; then
		write_page "<p>$COUNT_TOTAL packages have been attempted to be build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE.</p>"
	fi
	write_page "<p>"
	set_icon reproducible
	write_icon
	write_page "$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly in $SUITE/$ARCH."
	set_icon unreproducible
	write_icon
	write_page "$COUNT_BAD packages ($PERCENT_BAD%) failed to build reproducibly."
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
		if [ ! -f $BASE/$SUITE/${TABLE[$i]}.png ] || [ ! -z $(find $BASE/$SUITE -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
			create_png_from_table $i $SUITE/${TABLE[$i]}.png
		fi
	done
	write_page "</p>"
	write_page_footer
	publish_page $SUITE
}

#
# create pkg set navigation
#
create_pkg_sets_navigation() {
	local i
	write_page "<ul><li>Tracked package sets in $SUITE: </li>"
	for i in $(seq 1 ${#META_PKGSET[@]}) ; do
		if [ -f $BASE/$SUITE/$ARCH/${TABLE[6]}_${META_PKGSET[$i]}.png ] ; then
			THUMB="${TABLE[6]}_${META_PKGSET[$i]}-thumbnail.png"
			LABEL="Reproducibility status for packages in $SUITE/$ARCH from '${META_PKGSET[$i]}'"
			write_page "<a href=\"/$SUITE/$ARCH/pkg_set_${META_PKGSET[$i]}.html\"><img src=\"/userContent/$SUITE/$ARCH/$THUMB\" class=\"metaoverview\" alt=\"$LABEL\" title=\"${META_PKGSET[$i]}\" name=\"${META_PKGSET[$i]}\"></a>"
			write_page "<li>"
			write_page "<a href=\"/$SUITE/$ARCH/pkg_set_${META_PKGSET[$i]}.html\">${META_PKGSET[$i]}</a>"
			write_page "</li>"
		fi
	done
	write_page "</ul>"
}

#
# create pkg sets pages
#
create_pkg_sets_pages() {
	#
	# create index page
	#
	VIEW=pkg_sets
	PAGE=index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview about reproducible builds of specific package sets in $SUITE/$ARCH"
	create_pkg_sets_navigation
	write_page_footer
	publish_page $SUITE/$ARCH
	#
	# create individual pages for all the sets
	#
	local i
	for i in $(seq 1 ${#META_PKGSET[@]}) ; do
		PAGE="pkg_set_${META_PKGSET[$i]}.html"
		echo "$(date) - starting to write $PAGE page."
		write_page_header $VIEW "Overview about reproducible builds for the ${META_PKGSET[$i]} package set in $SUITE/$ARCH"
		create_pkg_sets_navigation
		write_page "<hr />"
		META_RESULT=true
		gather_meta_stats $i
		if $META_RESULT ; then
			MAINLABEL[6]="Reproducibility status for packages in $SUITE from '${META_PKGSET[$i]}'"
			YLABEL[6]="Amount (${META_PKGSET[$i]} packages)"
			PNG=${TABLE[6]}_${META_PKGSET[$i]}.png
			THUMB="${TABLE[6]}_${META_PKGSET[$i]}-thumbnail.png"
			# redo pngs once a day
			if [ ! -f $BASE/$SUITE/$ARCH/$PNG ] || [ ! -z $(find $BASE/$SUITE/$ARCH -maxdepth 1 -mtime +0 -name $PNG) ] ; then
				create_png_from_table 6 $SUITE/$ARCH/$PNG ${META_PKGSET[$i]}
				convert $BASE/$SUITE/$ARCH/$PNG -adaptive-resize 160x80 $BASE/$SUITE/$ARCH/$THUMB
			fi
			LABEL="package set '${META_PKGSET[$j]}' in $SUITE/$ARCH"
			write_page "<p><a href=\"/userContent/$SUITE/$ARCH/$PNG\"><img src=\"/userContent/$SUITE/$ARCH/$PNG\" class=\"overview\" alt=\"$LABEL\"></a>"
			write_page "<br />The package set '${META_PKGSET[$i]}' in $SUITE/$ARCH consists of: <br />&nbsp;<br />"
			set_icon unreproducible
			write_icon
			write_page "$COUNT_META_BAD ($PERCENT_META_BAD%) packages failed to build reproducibly:"
			link_packages $META_BAD
			write_page "<br />"
			if [ $COUNT_META_UGLY -gt 0 ] ; then
				set_icon FTBFS
				write_icon
				write_page "$COUNT_META_UGLY ($PERCENT_META_UGLY%) packages failed to build from source:"
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
				link_packages $META_REST
				write_page "<br />"
			fi
			write_page "&nbsp;<br />"
			set_icon reproducible
			write_icon
			write_page "$COUNT_META_GOOD packages ($PERCENT_META_GOOD%) successfully built reproducibly:"
			link_packages $META_GOOD
			write_page "<br />"
			write_page "</p>"
			write_page_meta_sign
		fi
		write_page_footer
		publish_page $SUITE/$ARCH
	done
}

#
# create main stats page
#
create_main_stats_page() {
	VIEW=stats
	PAGE=index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of various statistics about reproducible builds"
	# write suite table
	write_page "<p>"
	write_page "<table class=\"main\"><tr><th>suite</th><th>all sources packages</th><th>reproducible packages</th><th>unreproducible packages</th><th>packages failing to build</th><th>other packages</th></tr>"
	for SUITE in $SUITES ; do
		gather_suite_stats
		write_page "<tr><td>$SUITE</td><td>$AMOUNT"
		if [ $(echo $PERCENT_TOTAL/1|bc) -lt 98 ] ; then
			write_page "<span style=\"font-size:0.8em;\">($PERCENT_TOTAL% tested)</span>"
		fi
		write_page "</td><td>$COUNT_GOOD / $PERCENT_GOOD%</td><td>$COUNT_BAD / $PERCENT_BAD%</td><td>$COUNT_UGLY / $PERCENT_UGLY%</td><td>$COUNT_OTHER / $PERCENT_OTHER%</td></tr>"
	done
        write_page "</table>"
	# write suite graphs
	write_page "</p><p style=\"clear:both;\">"
	for SUITE in $SUITES ; do
		write_page " <a href=\"/$SUITE\"><img src=\"/userContent/$SUITE/${TABLE[0]}.png\" class=\"overview\" alt=\"$SUITE stats\"></a>"
	done
	write_page "</p><p><center>"
	# write meta pkg graphs per suite
	for SUITE in $SUITES ; do
		if [ "$SUITE" != "unstable" ] ; then
			# only show pkg sets from unstable
			continue
		fi
		for i in $(seq 1 ${#META_PKGSET[@]}) ; do
			THUMB=${TABLE[6]}_${META_PKGSET[$i]}-thumbnail.png
			LABEL="Reproducibility status for packages in $SUITE/$ARCH from '${META_PKGSET[$i]}'"
			write_page "<a href=\"/$SUITE/$ARCH/pkg_set_${META_PKGSET[$i]}.html\"><img src=\"/userContent/$SUITE/$ARCH/$THUMB\" class=\"metaoverview\" alt=\"$LABEL\"></a>"
		done
	done
	write_page "</center></p><p>"
	# write inventory table
	write_page "<table class=\"main\"><tr><th>&nbsp;</th><th>amount</th></tr>"
	write_page "<tr><td>identified <a href=\"/index_issues.html\">distinct issues</a></td><td>$ISSUES</td></tr>"
	write_page "<tr><td>total number of identified issues in packages</td><td>$COUNT_ISSUES</td></tr>"
	write_page "<tr><td>packages with notes about these issues</td><td>$NOTES</td></tr>"
	SUITE="unstable"
	gather_suite_stats
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status IN ('unreproducible', 'FTBFS', 'blacklisted') AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH')")
	write_page "<tr><td>packages in $SUITE with issues but <a href=\"/$SUITE/$ARCH/index_no_notes.html\">without identified ones</a></td><td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='unreproducible' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH')")
	write_page "<tr><td>&nbsp;&nbsp;- unreproducible ones</a></td><td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='FTBFS' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH')")
	write_page "<tr><td>&nbsp;&nbsp;- failing to build</a></td><td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td></tr>"
	write_page "<tr><td>packages in $SUITE which need to be fixed</td><td>$(echo $COUNT_BAD + $COUNT_UGLY |bc) / $(echo $PERCENT_BAD + $PERCENT_UGLY|bc)%</td></tr>"
	if [ -f ${NOTES_GIT_PATH}/packages.yml ] && [ -f ${NOTES_GIT_PATH}/issues.yml ] ; then
		write_page "<tr><td>committers to <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\" target=\"_parent\">notes.git</a> (in the last three months)</td><td>$(cd ${NOTES_GIT_PATH} ; git log --since="3 months ago"|grep Author|sort -u |wc -l)</td></tr>"
		write_page "<tr><td>committers to notes.git (in total)</td><td>$(cd ${NOTES_GIT_PATH} ; git log |grep Author|sort -u |wc -l)</td></tr>"
	fi
	RESULT=$(cat /srv/reproducible-results/modified_in_sid.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
	write_page "<tr><td>packages <a href=\"/index_repositories.html\">modified in our toolchain</a> (in unstable)</td><td>$(echo $RESULT)</td></tr>"
	write_page "</table>"
	# write bugs with usertags table
	write_usertag_table
	write_page "</p><p style=\"clear:both;\">"
	# do other global graphs
	for i in 3 7 4 5 ; do
		write_page " <a href=\"/userContent/${TABLE[$i]}.png\"><img src=\"/userContent/${TABLE[$i]}.png\" class="halfview" alt=\"${MAINLABEL[$i]}\"></a>"
		# redo pngs once a day
		if [ ! -f $BASE/${TABLE[$i]}.png ] || [ ! -z $(find $BASE -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
			create_png_from_table $i ${TABLE[$i]}.png
		fi
	done
	write_page "</p>"
	# explain setup
	write_explaination_table debian
	# write build per day graph
	write_page "<p style=\"clear:both;\">"
	write_page " <a href=\"/userContent/${TABLE[1]}.png\"><img src=\"/userContent/${TABLE[1]}.png\" alt=\"${MAINLABEL[$i]}\"></a>"
	# redo png once a day
	if [ ! -f $BASE/${TABLE[1]}.png ] || [ ! -z $(find $BASE -maxdepth 1 -mtime +0 -name ${TABLE[1]}.png) ] ; then
			create_png_from_table 1 ${TABLE[1]}.png
	fi
	# write suite builds age graphs
	write_page "</p><p style=\"clear:both;\">"
	for SUITE in $SUITES ; do
		write_page " <a href=\"/$SUITE\"><img src=\"/userContent/$SUITE/${TABLE[2]}.png\" class=\"overview\" alt=\"age of oldest reproducible build result in $SUITE\"></a>"
	done
	# write build performace stats
	write_page "<table class=\"main\"><tr><th>&nbsp;</th><th>amount</th></tr>"
	AGE_TESTING=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(max(oldest_reproducible, oldest_unreproducible, oldest_FTBFS) AS INTEGER) FROM ${TABLE[2]} WHERE suite='testing' AND datum='$DATE'")
	AGE_UNSTABLE=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(max(oldest_reproducible, oldest_unreproducible, oldest_FTBFS) AS INTEGER) FROM ${TABLE[2]} WHERE suite='unstable' AND datum='$DATE'")
	AGE_EXPERIMENTAL=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(max(oldest_reproducible, oldest_unreproducible, oldest_FTBFS) AS INTEGER) FROM ${TABLE[2]} WHERE suite='experimental' AND datum='$DATE'")
	write_page "<tr><td>oldest build result in testing / unstable / experimental</td><td>$AGE_TESTING / $AGE_UNSTABLE / $AGE_EXPERIMENTAL days</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(AVG(r.build_duration) AS INTEGER) FROM results AS r WHERE r.build_duration!='' AND r.build_duration!='0' AND r.build_date LIKE '%$DATE%'")
	MIN=$(echo $RESULT/60|bc)
	SEC=$(echo "$RESULT-($MIN*60)"|bc)
	write_page "<tr><td>average test duration (on $DATE)</td><td>$MIN minutes, $SEC seconds</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(AVG(r.build_duration) AS INTEGER) FROM results AS r WHERE r.build_duration!='' AND r.build_duration!='0' AND r.build_date > datetime('$DATE', '-28 days')")
	MIN=$(echo $RESULT/60|bc)
	SEC=$(echo "$RESULT-($MIN*60)"|bc)
	write_page "<tr><td>average test duration (in the last 4 weeks)</td><td>$MIN minutes, $SEC seconds</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(r.build_date) FROM results AS r WHERE r.build_date LIKE '%$DATE%'")
	write_page "<tr><td>packages tested on $DATE</td><td>$RESULT</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(r.build_date) FROM results AS r WHERE r.build_date > datetime('$DATE', '-28 days')")
	RESULT="$(echo $RESULT/28|bc)"
	write_page "<tr><td>packages tested on average per day in the last 4 weeks</td><td>$RESULT</td></tr>"
	write_page "</table>"
	# link to index_breakages
	write_page "</p><p style=\"clear:both;\">"
	write_page "<br />There are <a href=\"$BASEURL/index_breakages.html\">some problems in this setup</a> too. And there is <a href=\"https://jenkins.debian.net/userContent/about.html#_reproducible_builds_jobs\">documentation</a> too, in case you missed the link at the top. More feedback is always welcome!</p>"
	# the end
	write_page_footer
	cp $PAGE $BASE/reproducible.html
	publish_page
}

#
# main
#
SUITE="unstable"
update_bug_stats
update_notes_stats
for SUITE in $SUITES ; do
	update_suite_stats
	gather_suite_stats
	create_suite_stats_page
	if [ "$SUITE" = "experimental" ] ; then
		# no pkg sets in experimental
		continue
	fi
	update_meta_pkg_stats
	create_pkg_sets_pages
done
SUITE="unstable"
create_main_stats_page

