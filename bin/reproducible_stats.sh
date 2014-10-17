#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# FIXME: move to daily cleanup job
# cp db away for backup purposes
cp $PACKAGES_DB /var/lib/jenkins/userContent/reproducible.db

set +x
init_html

declare -A GOOD
declare -A BAD
declare -A UGLY
declare -A SOURCELESS
declare -A NOTFORUS
LAST24="AND build_date > datetime('now', '-24 hours') "
LAST48="AND build_date > datetime('now', '-48 hours') "
GOOD["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY build_date DESC" | xargs echo)
GOOD["last_24h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" $LAST24 ORDER BY build_date DESC" | xargs echo)
GOOD["last_48h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" $LAST48 ORDER BY build_date DESC" | xargs echo)
GOOD["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY name" | xargs echo)
BAD["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY build_date DESC" | xargs echo)
BAD["last_24h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" $LAST24 ORDER BY build_date DESC" | xargs echo)
BAD["last_48h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" $LAST48 ORDER BY build_date DESC" | xargs echo)
BAD["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY name" | xargs echo)
COUNT_BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"unreproducible\"")
UGLY["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY build_date DESC" | xargs echo)
UGLY["last_24h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" $LAST24 ORDER BY build_date DESC" | xargs echo)
UGLY["last_48h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" $LAST48 ORDER BY build_date DESC" | xargs echo)
UGLY["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY name" | xargs echo)
COUNT_UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"FTBFS\"")
SOURCELESS["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY build_date DESC" | xargs echo)
SOURCELESS["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY name" | xargs echo)
COUNT_SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"404\"" | xargs echo)
NOTFORUS["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"not for us\" ORDER BY build_date DESC" | xargs echo)
NOTFORUS["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"not for us\" ORDER BY name" | xargs echo)
COUNT_NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"not for us\"" | xargs echo)
BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"blacklisted\" ORDER BY name" | xargs echo)
COUNT_BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"blacklisted\"" | xargs echo)
PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)

#
# actually build the package pages
#
echo "$(date) - processing $COUNT_TOTAL packages... this will take a while."
process_packages ${BAD["all"]}
process_packages ${UGLY["all"]} ${GOOD["all"]} ${SOURCELESS["all"]} ${NOTFORUS["all"]} $BLACKLISTED

for VIEW in $ALLVIEWS ; do
	BUILDINFO_SIGNS=true
	PAGE=index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of reproducible builds of ${SPOKENTARGET[$VIEW]}"
	if [ "${VIEW:0:3}" = "all" ] ; then
		FINISH=":"
	else
		SHORTER_SPOKENTARGET=$(echo ${SPOKENTARGET[$VIEW]} | cut -d "(" -f1)
		FINISH=", from $SHORTER_SPOKENTARGET these were:"
	fi
	write_page "<p>"
	set_icon unreproducible with
	write_icon
	set_icon unreproducible
	write_icon
	write_page "$COUNT_BAD packages ($PERCENT_BAD% of $COUNT_TOTAL) failed to built reproducibly in total$FINISH <code>"
	link_packages ${BAD[$VIEW]}
	write_page "</code></p>"
	write_page
	write_page "<p>"
	set_icon FTBFS
	write_icon
	write_page "$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source in total$FINISH <code>"
	link_packages ${UGLY[$VIEW]}
	write_page "</code></p>"
	if [ "${VIEW:0:3}" = "all" ] && [ $COUNT_SOURCELESS -gt 0 ] ; then
		write_page "<p>For "
		set_icon 404
		write_icon
		write_page "$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) packages in total sources could not be downloaded: <code>"
		link_packages ${SOURCELESS[$VIEW]}
		write_page "</code></p>"
	fi
	if [ "${VIEW:0:3}" = "all" ] && [ $COUNT_NOTFORUS -gt 0 ] ; then
		write_page "<p>In total there were "
		set_icon not_for_us
		write_icon
		write_page "$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any', 'all', 'amd64', 'linux-any', 'linux-amd64' nor 'any-amd64': <code>"
		link_packages ${NOTFORUS[$VIEW]}
		write_page "</code></p>"
	fi
	if [ "${VIEW:0:3}" = "all" ] && [ $COUNT_BLACKLISTED -gt 0 ] ; then
		write_page "<p>"
		set_icon blacklisted
		write_icon
		write_page "$COUNT_BLACKLISTED packages are blacklisted and will never be tested here: <code>"
		link_packages $BLACKLISTED
		write_page "</code></p>"
	fi
	write_page "<p>"
	set_icon reproducible
	write_icon
	write_page "$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly$FINISH <code>"
	BUILDINFO_SIGNS=false
	link_packages ${GOOD[$VIEW]}
	write_page "</code></p>"
	write_page_meta_sign
	write_page_footer
	publish_page
done

count_packages() {
	COUNT=${#@}
	PERCENT=$(echo "scale=1 ; ($COUNT*100/$COUNT_TOTAL)" | bc)
}

for STATE in $ALLSTATES ; do
	BUILDINFO_SIGNS=true
	PAGE=index_${STATE}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $STATE "Overview of ${SPOKENTARGET[$STATE]}"
	WITH=""
	case "$STATE" in
		reproducible)	BUILDINFO_SIGNS=false
				PACKAGES=${GOOD["all"]}
				;;
		FTBR)		CANDIDATES=${BAD["all"]}
				PACKAGES=""
				for PKG in $CANDIDATES ; do
					set_package_star
					if [ "$STAR" = "" ] ; then
						PACKAGES="$PACKAGES $PKG"
					fi
				done
				;;
		FTBR_with_buildinfo)	CANDIDATES=${BAD["all"]}
				PACKAGES=""
				for PKG in $CANDIDATES ; do
					set_package_star
					if [ "$STAR" != "" ] ; then
						PACKAGES="$PACKAGES $PKG"
					fi
				done
				WITH="YES"
				;;
		FTBFS)		PACKAGES=${UGLY["all"]}
				;;
		404)		PACKAGES=${SOURCELESS["all"]}
				;;
		not_for_us)	PACKAGES=${NOTFORUS["all"]}
				;;
		blacklisted)	PACKAGES=${BLACKLISTED}
				;;
	esac
	count_packages ${PACKAGES}
	write_page "<p>"
	set_icon $STATE	$WITH
	write_icon
	write_page "$COUNT ($PERCENT%) ${SPOKENTARGET[$STATE]}:<code>"
	link_packages ${PACKAGES}
	write_page "</code></p>"
	write_page
	write_page_meta_sign
	write_page_footer
	publish_page
done

#
# create stats
#
# FIXME: we only do stats up until yesterday... we also could do today too but not update the db yet...
DATE=$(date -d "1 day ago" '+%Y-%m-%d')
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,suite from ${TABLE[0]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\"")
if [ -z $RESULT ] ; then
	ALL=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(name) from sources")
	GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'reproducible' AND date(build_date)<='$DATE';")
	GOOAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'reproducible' AND date(build_date)='$DATE';")
	BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'unreproducible' AND date(build_date)<='$DATE';")
	BAAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'unreproducible' AND date(build_date)='$DATE';")
	UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'FTBFS' AND date(build_date)<='$DATE';")
	UGLDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'FTBFS' AND date(build_date)='$DATE';")
	REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE (status != 'FTBFS' AND status != 'FTBFS' AND status != 'unreproducible' AND status != 'reproducible') AND date(build_date)<='$DATE';")
	RESDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE (status != 'FTBFS' AND status != 'FTBFS' AND status != 'unreproducible' AND status != 'reproducible') AND date(build_date)='$DATE';")
	OLDESTG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT build_date FROM source_packages WHERE status = 'reproducible' AND NOT date(build_date)>='$DATE' ORDER BY build_date LIMIT 1;")
	OLDESTB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT build_date FROM source_packages WHERE status = 'unreproducible' AND NOT date(build_date)>='$DATE' ORDER BY build_date LIMIT 1;")
	OLDESTU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT build_date FROM source_packages WHERE status = 'FTBFS' AND NOT date(build_date)>='$DATE' ORDER BY build_date LIMIT 1;")
	DIFFG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTG');")
	if [ -z $DIFFG ] ; then DIFFG=0 ; fi
	DIFFB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTB');")
	if [ -z $DIFFB ] ; then DIFFB=0 ; fi
	DIFFU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTU');")
	if [ -z $DIFFU ] ; then DIFFU=0 ; fi
	let "TOTAL=GOOD+BAD+UGLY+REST"
	let "UNTESTED=ALL-TOTAL"
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[0]} VALUES (\"$DATE\", \"$SUITE\", $UNTESTED, $GOOD, $BAD, $UGLY, $REST)" 
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[1]} VALUES (\"$DATE\", \"$SUITE\", $GOOAY, $BAAY, $UGLDAY, $RESDAY)"
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[2]} VALUES (\"$DATE\", \"$SUITE\", \"$DIFFG\", \"$DIFFB\", \"$DIFFU\")"
	# FIXME: we don't do 2 / stats_builds_age.png yet :/ (also see below)
	for i in 0 1 ; do
		# force regeneration of the image
		touch -d "$DATE 00:00" ${TABLE[$i]}.png
	done
fi

# query bts
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness"
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
COLOR[0]=5
COLOR[1]=4
COLOR[2]=3
COLOR[3]=18
MAINLABEL[0]="Package reproducibility status"
MAINLABEL[1]="Amout of packages build each day"
MAINLABEL[2]="Age in days of oldest kind of logfile"
MAINLABEL[3]="Bugs with usertags for user reproducible-builds@lists.alioth.debian.org"
YLABEL[0]="Amount (total)"
YLABEL[1]="Amount (per day)"
YLABEL[2]="Age in days"
YLABEL[3]="Amount of bugs"
redo_png() {
	echo "${FIELDS[$i]}" > ${TABLE[$i]}.csv
	# TABLE[3] doesn't have a suite column...
	if [ $i -ne 3 ] ; then
		WHERE_SUITE="WHERE suite = '$SUITE'"
	else
		WHERE_SUITE=""
	fi
	sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$i]} from ${TABLE[$i]} ${WHERE_SUITE} ORDER BY datum" >> ${TABLE[$i]}.csv
	/srv/jenkins/bin/make_graph.py ${TABLE[$i]}.csv ${TABLE[$i]}.png ${COLOR[$i]} "${MAINLABEL[$i]}" "${YLABEL[$i]}"
	rm ${TABLE[$i]}.csv
	mv ${TABLE[$i]}.png /var/lib/jenkins/userContent/
}

write_usertag_table() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
	if [ -z "$RESULTS" ] ; then
		COUNT=0
		for FIELD in $(echo ${FIELDS[3]} | tr -d ,) ; do
			let "COUNT+=1"
			VALUE=$(echo $RESULT | cut -d "|" -f$COUNT)
			if [ $COUNT -eq 1 ] ; then
				write_page "<table class=\"body\"><tr><td colspan=\"4\"><em>Bugs with usertags for reproducible-builds@lists.alioth.debian.org on $VALUE</em></td></tr>"
			elif [ $((COUNT%2)) -eq 0 ] ; then
				write_page "<tr><td>&nbsp;</td><td><a href=\"https://bugs.debian.org/cgi-bin/pkgreport.cgi?tag=${FIELD:5};users=reproducible-builds@lists.alioth.debian.org&archive=both\">${FIELD:5}</a></td><td>Open: $VALUE</td>"
			else
				write_page "<td>Done: $VALUE</td></tr>"
			fi
		done
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
set_icon unreproducible with
write_icon
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
write_page "$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any', 'all', 'amd64', 'linux-any', 'linux-amd64' nor 'any-amd64' will never be build here"
write_page "and those "
set_icon blacklisted
write_icon
write_page "$COUNT_BLACKLISTED blacklisted packages neither.</p>"
write_page "<p>"
# FIXME: we don't do 2 / stats_builds_age.png yet :/ (also see above)
for i in 0 1 3 ; do
	if [ "$i" = "3" ] ; then
		write_usertag_table
	fi
	write_page " <a href=\"$JENKINS_URL/userContent/${TABLE[$i]}.png\"><img src=\"$JENKINS_URL/userContent/${TABLE[$i]}.png\" class=\"graph\" alt=\"${MAINLABEL[$i]}\"></a>"
	# redo pngs once a day
	if [ ! -f /var/lib/jenkins/userContent/${TABLE[$i]}.png ] || [ -z $(find /var/lib/jenkins/userContent -maxdepth 1 -mtime -1 -name ${TABLE[$i]}.png) ] ; then
		redo_png
	fi
done
write_page "</p>"
write_page_footer
publish_page

