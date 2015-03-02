#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

init_html
gather_stats

if [ -n "$1" ] ; then
	SUITE="$1"
else
	SUITE="sid"
fi
ARCH="amd64"  # we only care about amd64 status here (for now)

#
# create stats
#
# we only do stats up until yesterday... we also could do today too but not update the db yet...
DATE=$(date -d "1 day ago" '+%Y-%m-%d')
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
TABLE[4]=stats_notes
TABLE[5]=stats_issues
TABLE[6]=stats_meta_pkg_state

#
# gather package + build stats
#
RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,suite from ${TABLE[0]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\"")
if [ -z $RESULT ] ; then
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
	let "TOTAL=GOOD+BAD+UGLY+REST"
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
		# force regeneration of the image if it exists
		[ ! -f ${TABLE[$i]}.png ] || touch -d "$DATE 00:00" ${TABLE[$i]}.png
	done
fi

#
# gather notes stats
#
RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum from ${TABLE[4]} WHERE datum = \"$DATE\"")
if [ -z $RESULT ] ; then
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
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[4]} VALUES (\"$DATE\", \"$NOTES\")"
	ISSUES=$(grep -c -v "^ " ${NOTES_GIT_PATH}/issues.yml)
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[5]} VALUES (\"$DATE\", \"$ISSUES\")"
fi

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
		META_GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		META_BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		META_UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE' AND $META_WHERE;")
		META_REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT s.name AS NAME FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND date(r.build_date)<='$DATE' AND $META_WHERE;")
	else
		META_RESULT=false
	fi
}

for i in $(seq 1 ${#META_PKGSET[@]}) ; do
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,meta_pkg,suite from ${TABLE[6]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\" AND meta_pkg = \"${META_PKGSET[$i]}\"")
	if [ -z $RESULT ] ; then
		META_RESULT=true
		gather_meta_stats $i
		! $META_RESULT || sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[6]} VALUES (\"$DATE\", \"$SUITE\", \"${META_PKGSET[$i]}\", $COUNT_META_GOOD, $COUNT_META_BAD, $COUNT_META_UGLY, $COUNT_META_REST)"
		touch -d "$DATE 00:00" ${TABLE[6]}_${META_PKGSET[$i]}.png
	fi
done

#
# gather bugs stats
#
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness buildinfo cpu signatures environment umask"
RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
if [ -z $RESULT ] ; then
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
	touch -d "$DATE 00:00" ${TABLE[3]}.png
fi

# used for redo_png (but only needed to define once)
FIELDS[0]="datum, reproducible, unreproducible, FTBFS, other, untested"
FIELDS[1]="datum, reproducible, unreproducible, FTBFS, other"
FIELDS[2]="datum, oldest_reproducible, oldest_unreproducible, oldest_FTBFS"
FIELDS[3]="datum "
for TAG in $USERTAGS ; do
	FIELDS[3]="${FIELDS[3]}, open_$TAG, done_$TAG"
done
FIELDS[4]="datum, packages_with_notes"
FIELDS[5]="datum, known_issues"
FIELDS[6]="datum, reproducible, unreproducible, FTBFS, other"
COLOR[0]=5
COLOR[1]=4
COLOR[2]=3
COLOR[3]=28
COLOR[4]=1
COLOR[5]=1
COLOR[6]=4
MAINLABEL[0]="Reproducibility status for packages in '$SUITE'"
MAINLABEL[1]="Amount of packages build each day"
MAINLABEL[2]="Age in days of oldest kind of logfile"
MAINLABEL[3]="Bugs with usertags for user reproducible-builds@lists.alioth.debian.org"
MAINLABEL[4]="Packages which have notes"
MAINLABEL[5]="Identified issues"
YLABEL[0]="Amount (total)"
YLABEL[1]="Amount (per day)"
YLABEL[2]="Age in days"
YLABEL[3]="Amount of bugs"
YLABEL[4]="Amount of packages"
YLABEL[5]="Amount of issues"

redo_png() {
	# $1 = id of the stats table
	# $2 = image file name
	# $3 = meta package set, only sensible if $1=6
	echo "${FIELDS[$1]}" > ${TABLE[$1]}.csv
	# TABLE[3+4+5] don't have a suite column...
	# 6 is special anyway
	if [ $1 -eq 6 ] ; then
		WHERE_EXTRA="WHERE suite = '$SUITE' and meta_pkg = '$3'"
	elif [ $1 -ne 3 ] && [ $1 -ne 4 ] && [ $1 -ne 5 ] ; then
		WHERE_EXTRA="WHERE suite = '$SUITE'"
	else
		WHERE_EXTRA=""
	fi
	sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$1]} from ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	/srv/jenkins/bin/make_graph.py ${TABLE[$1]}.csv $2 ${COLOR[$1]} "${MAINLABEL[$1]}" "${YLABEL[$1]}"
	rm ${TABLE[$1]}.csv
	mv $2 /var/lib/jenkins/userContent/
}

write_usertag_table() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
	if [ -z "$RESULTS" ] ; then
		COUNT=0
		TOPEN=0 ; TDONE=0 ; TTOTAL=0
		for FIELD in $(echo ${FIELDS[3]} | tr -d ,) ; do
			let "COUNT+=1"
			VALUE=$(echo $RESULT | cut -d "|" -f$COUNT)
			if [ $COUNT -eq 1 ] ; then
				write_page "<table class=\"body\"><tr><th>Bugs per usertag on $VALUE</th><th>Open</th><th>Done</th><th>Total</th></tr>"
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

VIEW=stats
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
write_page "<p>"
set_icon reproducible
write_icon
write_page "$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly."
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
# FIXME: we don't do 2 / stats_builds_age.png yet :/ (and 6 is special anyway)
for i in 0 3 4 5 1 ; do
	if [ "$i" = "3" ] ; then
		write_usertag_table
	fi
	write_page " <a href=\"/userContent/${TABLE[$i]}.png\"><img src=\"/userContent/${TABLE[$i]}.png\" class=\"graph\" alt=\"${MAINLABEL[$i]}\"></a>"
	# redo pngs once a day
	if [ ! -f /var/lib/jenkins/userContent/${TABLE[$i]}.png ] || [ -z $(find /var/lib/jenkins/userContent -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
		redo_png $i ${TABLE[$i]}.png
	fi
done
write_page "</p>"
write_page_footer
publish_page $SUITE

if [ "$SUITE" = "experimental" ] ; then
	# no package sets page for experimental
	exit 0
fi
VIEW=pkg_sets
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
write_page "<ul><li>Tracked package sets: </li>"
for i in $(seq 1 ${#META_PKGSET[@]}) ; do
	if [ -f /var/lib/jenkins/userContent/${TABLE[6]}_${META_PKGSET[$i]}.png ] ; then
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
		if [ ! -f /var/lib/jenkins/userContent/$PNG ] || [ -z $(find /var/lib/jenkins/userContent -maxdepth 1 -mtime +0 -name $PNG) ] ; then
			redo_png 6 $PNG ${META_PKGSET[$i]}
		fi
		write_page "<p><a href=\"/userContent/$PNG\"><img src=\"/userContent/$PNG\" class=\"graph\" alt=\"${MAINLABEL[6]}\"></a>"
		write_page "<br />The package set '${META_PKGSET[$i]}' consists of: <br />"
		set_icon reproducible
		write_icon
		write_page "$COUNT_META_GOOD packages ($PERCENT_META_GOOD%) successfully built reproducibly:"
		set_linktarget $SUITE $ARCH $META_GOOD
		link_packages $META_GOOD
		write_page "<br />"
		set_icon unreproducible
		write_icon
		write_page "$COUNT_META_BAD ($PERCENT_META_BAD%) packages failed to built reproducibly:"
		set_linktarget $SUITE $ARCH $META_BAD
		link_packages $META_BAD
		write_page "<br />"
		if [ $COUNT_META_UGLY -gt 0 ] ; then
			set_icon FTBFS
			write_icon
			write_page "$COUNT_META_UGLY ($PERCENT_META_UGLY%) packages failed to build from source:"
			set_linktarget $SUITE $ARCH $META_UGLY
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
			set_linktarget $SUITE $ARCH $META_REST
			link_packages $META_REST
			write_page "<br />"
		fi
		write_page "</p>"
	fi
	write_page_meta_sign
done
write_page_footer
publish_page

