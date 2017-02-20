#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
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
# we only do stats up until yesterday... we also could do today too but not update the db yet...
DATE=$(date -u -d "1 day ago" '+%Y-%m-%d')
FORCE_DATE=$(date -u -d "3 days ago" '+%Y-%m-%d')
DUMMY_FILE=$(mktemp -t reproducible-dashboard-XXXXXXXX)
touch -d "$(date '+%Y-%m-%d') 00:00 UTC" $DUMMY_FILE
NOTES_GIT_PATH="/var/lib/jenkins/jobs/reproducible_html_notes/workspace"

# variables related to the stats we update
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
	# for this table (#3) bugs with ftbfs tags are ignored _now_…
	if [ "$TAG" = "ftbfs" ] ; then
		continue
	fi
	FIELDS[3]="${FIELDS[3]}, open_$TAG, done_$TAG"
done
# …and added at the end (so they are not ignored but rather sorted this way)
# Also note how FIELDS is only used for reading data, not writing.
FIELDS[3]="${FIELDS[3]}, open_ftbfs, done_ftbfs"
FIELDS[4]="datum, packages_with_notes"
FIELDS[5]="datum, known_issues"
FIELDS[7]="datum, done_bugs, open_bugs"
SUM_DONE="(0"
SUM_OPEN="(0"
for TAG in $USERTAGS ; do
	SUM_DONE="$SUM_DONE+done_$TAG"
	SUM_OPEN="$SUM_OPEN+open_$TAG"
done
SUM_DONE="$SUM_DONE)"
SUM_OPEN="$SUM_OPEN)"
FIELDS[8]="datum "
for STATE in open_ done_ ; do
	for TAG in $USERTAGS ; do
		if [ "$TAG" = "ftbfs" ] ; then
			continue
		fi
		FIELDS[8]="${FIELDS[8]}, ${STATE}$TAG"
	done
	# ftbfs bugs are excluded from 8+9
done
FIELDS[9]="datum, done_bugs, open_bugs"
REPRODUCIBLE_DONE="(0"
REPRODUCIBLE_OPEN="(0"
for TAG in $USERTAGS ; do
	# for this table (#9) bugs with ftbfs tags are ignored.
	if [ "$TAG" = "ftbfs" ] ; then
		continue
	fi
	REPRODUCIBLE_DONE="$REPRODUCIBLE_DONE+done_$TAG"
	REPRODUCIBLE_OPEN="$REPRODUCIBLE_OPEN+open_$TAG"
done
REPRODUCIBLE_DONE="$REPRODUCIBLE_DONE)"
REPRODUCIBLE_OPEN="$REPRODUCIBLE_OPEN)"
COLOR[0]=5
COLOR[1]=12
COLOR[2]=1
COLOR[3]=32
COLOR[4]=1
COLOR[5]=1
COLOR[7]=2
COLOR[8]=30
COLOR[9]=2
MAINLABEL[3]="Bugs (with all usertags) for user reproducible-builds@lists.alioth.debian.org"
MAINLABEL[4]="Packages which have notes"
MAINLABEL[5]="Identified issues"
MAINLABEL[7]="Open and closed bugs (with all usertags)"
MAINLABEL[8]="Bugs (with all usertags except 'ftbfs') for user reproducible-builds@lists.alioth.debian.org"
MAINLABEL[9]="Open and closed bugs (with all usertags except tagged 'ftbfs')"
YLABEL[0]="Amount (total)"
YLABEL[1]="Amount (per day)"
YLABEL[2]="Age in days"
YLABEL[3]="Amount of bugs"
YLABEL[4]="Amount of packages"
YLABEL[5]="Amount of issues"
YLABEL[7]="Amount of bugs open / closed"
YLABEL[8]="Amount of bugs"
YLABEL[9]="Amount of bugs open / closed"

#
# update package + build stats
#
update_suite_arch_stats() {
	RESULT=$(query_db "SELECT datum,suite from ${TABLE[0]} WHERE datum = '$DATE' AND suite = '$SUITE' AND architecture = '$ARCH'")
	if [ -z $RESULT ] ; then
		echo "Updating packages and builds stats for $SUITE/$ARCH in $DATE."
		ALL=$(query_db "SELECT count(name) FROM sources WHERE suite='${SUITE}' AND architecture='$ARCH'")
		GOOD=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE';")
		GOOAY=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'reproducible' AND date(r.build_date)='$DATE';")
		BAD=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE';")
		BAAY=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible' AND date(r.build_date)='$DATE';")
		UGLY=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE';")
		UGLDAY=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS' AND date(r.build_date)='$DATE';")
		REST=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND s.suite='$SUITE' AND s.architecture='$ARCH' AND date(r.build_date)<='$DATE';")
		RESDAY=$(query_db "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND s.suite='$SUITE' AND s.architecture='$ARCH' AND date(r.build_date)='$DATE';")
		OLDESTG=$(query_db "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.status = 'reproducible' AND s.suite='$SUITE' AND s.architecture='$ARCH' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		OLDESTB=$(query_db "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		OLDESTU=$(query_db "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		# only if we have results…
		if [ -n "$OLDESTG" ] ; then
			DIFFG=$(query_db "SELECT (date '$DATE' - date '$OLDESTG');")
			if [ -z $DIFFG ] ; then DIFFG=0 ; fi
			DIFFB=$(query_db "SELECT (date '$DATE' - date '$OLDESTB');")
			if [ -z $DIFFB ] ; then DIFFB=0 ; fi
			DIFFU=$(query_db "SELECT (date '$DATE' - date '$OLDESTU');")
			if [ -z $DIFFU ] ; then DIFFU=0 ; fi
		fi
		let "TOTAL=GOOD+BAD+UGLY+REST" || true # let FOO=0+0 returns error in bash...
		if [ "$ALL" != "$TOTAL" ] ; then
			let "UNTESTED=ALL-TOTAL"
		else
			UNTESTED=0
		fi
		if [ -n "$OLDESTG" ] ; then
			query_db "INSERT INTO ${TABLE[0]} VALUES ('$DATE', '$SUITE', '$ARCH', $UNTESTED, $GOOD, $BAD, $UGLY, $REST)"
			query_db "INSERT INTO ${TABLE[1]} VALUES ('$DATE', '$SUITE', '$ARCH', $GOOAY, $BAAY, $UGLDAY, $RESDAY)"
			query_db "INSERT INTO ${TABLE[2]} VALUES ('$DATE', '$SUITE', '$ARCH', '$DIFFG', '$DIFFB', '$DIFFU')"
		fi
		# we do 3 later and 6 is special anyway...
		for i in 0 1 2 4 5 ; do
			PREFIX=""
			if [ $i -eq 0 ] || [ $i -eq 2 ] ; then
				PREFIX=$SUITE/$ARCH
			fi
			# force regeneration of the image if it exists
			if [ -f $DEBIAN_BASE/$PREFIX/${TABLE[$i]}.png ] ; then
				echo "Touching $PREFIX/${TABLE[$i]}.png..."
				touch -d "$FORCE_DATE 00:00 UTC" $DEBIAN_BASE/$PREFIX/${TABLE[$i]}.png
			fi
		done
	fi
}

#
# update notes stats
#
update_notes_stats() {
	NOTES=$(query_db "SELECT COUNT(package_id) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64'")
	ISSUES=$(query_db "SELECT COUNT(name) FROM issues")
	# the following is a hack to workaround the bad sql db design which is the issue_s_ column in the notes table...
	# it assumes we don't have packages with more than 7 issues. (we have one with 6...)
	COUNT_ISSUES=$(query_db "SELECT \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues = '[]') \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues != '[]' AND n.issues NOT LIKE '%,%') \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues LIKE '%,%') \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues LIKE '%,%,%') \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues LIKE '%,%,%,%') \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues LIKE '%,%,%,%,%') \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite='unstable' AND s.architecture='amd64' AND n.issues LIKE '%,%,%,%,%,%') \
		")
	RESULT=$(query_db "SELECT datum from ${TABLE[4]} WHERE datum = '$DATE'")
	if [ -z $RESULT ] ; then
		echo "Updating notes stats for $DATE."
		query_db "INSERT INTO ${TABLE[4]} VALUES ('$DATE', '$NOTES')"
		query_db "INSERT INTO ${TABLE[5]} VALUES ('$DATE', '$ISSUES')"
	fi
}

#
# gather suite/arch stats
#
gather_suite_arch_stats() {
	AMOUNT=$(query_db "SELECT count(*) FROM sources WHERE suite='${SUITE}' AND architecture='$ARCH'")
	COUNT_TOTAL=$(query_db "SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH'")
	COUNT_GOOD=$(query_db "SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status='reproducible'")
	COUNT_BAD=$(query_db "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible'")
	COUNT_UGLY=$(query_db "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS'")
	COUNT_SOURCELESS=$(query_db "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = '404'")
	COUNT_NOTFORUS=$(query_db "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'not for us'")
	COUNT_BLACKLISTED=$(query_db "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'blacklisted'")
	COUNT_DEPWAIT=$(query_db "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'depwait'")
	COUNT_OTHER=$(( $COUNT_SOURCELESS+$COUNT_NOTFORUS+$COUNT_BLACKLISTED+$COUNT_DEPWAIT ))
	PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
	PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_DEPWAIT=$(echo "scale=1 ; ($COUNT_DEPWAIT*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_BLACKLISTED=$(echo "scale=1 ; ($COUNT_BLACKLISTED*100/$COUNT_TOTAL)" | bc || echo 0)
	PERCENT_OTHER=$(echo "scale=1 ; ($COUNT_OTHER*100/$COUNT_TOTAL)" | bc || echo 0)
}

#
# update bug stats
#
update_bug_stats() {
	RESULT=$(query_db "SELECT * from ${TABLE[3]} WHERE datum = '$DATE'")
	if [ -z $RESULT ] ; then
		echo "Updating bug stats for $DATE."
		declare -a DONE
		declare -a OPEN
		GOT_BTS_RESULTS=false
		SQL="INSERT INTO ${TABLE[3]} VALUES ('$DATE' "
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
			echo "Updating database with bug stats for $DATE."
			query_db "$SQL"
			# force regeneration of the image
			local i=0
			for i in 3 7 8 9 ; do
				echo "Touching ${TABLE[$i]}.png..."
				touch -d "$FORCE_DATE 00:00 UTC" $DEBIAN_BASE/${TABLE[$i]}.png
			done
		fi
	fi
}

#
# gather bugs stats and generate html table
#
write_usertag_table() {
	RESULT=$(query_db "SELECT ${FIELDS[3]} from ${TABLE[3]} WHERE datum = '$DATE'")
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
		# now subtract the ftbfs bugs again (=the last fields from the result)
		# as those others are the ones we really care about
		let "CCOUNT=COUNT-1"
		let "REPRODUCIBLE_TOPEN=TOPEN-$(echo $RESULT | cut -d "|" -f$CCOUNT)"
		let "REPRODUCIBLE_TDONE=TDONE-$(echo $RESULT | cut -d "|" -f$COUNT)"
		let "REPRODUCIBLE_TTOTAL=REPRODUCIBLE_TOPEN+REPRODUCIBLE_TDONE"
		write_page "<tr><td>Sum of <a href=\"https://wiki.debian.org/ReproducibleBuilds/Contribute#How_to_report_bugs\">bugs with usertags related to reproducible builds</a>, excluding those tagged 'ftbfs'</td><td>$REPRODUCIBLE_TOPEN</td><td>$REPRODUCIBLE_TDONE</td><td>$REPRODUCIBLE_TTOTAL</td></tr>"
		write_page "<tr><td>Sum of all bugs with usertags related to reproducible builds</td><td>$TOPEN</td><td>$TDONE</td><td>$TTOTAL</td></tr>"
		write_page "<tr><td colspan=\"4\" class=\"left\">Stats are from $DATE.<br />The sums of usertags shown are not equivalent to the sum of bugs as a single bug can have several tags.</td></tr>"
		write_page "</table>"
	fi
}

#
# write build performance stats
#
_average_builds_per_day() {
	local TIMESPAN_RAW="$1"
	local TIMESPAN_VERBOSE="$2"
	local MIN_DAYS="${3-0}"
	write_page "<tr><td class=\"left\">packages tested on average per day in the last $TIMESPAN_VERBOSE</td>"
	for ARCH in ${ARCHS} ; do
		local OLDEST_BUILD="$(query_db "SELECT build_date FROM stats_build WHERE architecture='$ARCH' ORDER BY build_date ASC LIMIT 1")"
		local DAY_DIFFS="$(( ($(date -d "$DATE" +%s) - $(date -d "$OLDEST_BUILD" +%s)) / (60*60*24) ))"
		local DISCLAIMER=""
		local TIMESPAN="$TIMESPAN_RAW"
		if [ $DAY_DIFFS -ge $MIN_DAYS ]; then
			if [ $DAY_DIFFS -lt $TIMESPAN ]; then
				# this is a new architecture, there are fewer days to compare to.
				DISCLAIMER=" <span style=\"font-size: 0.8em;\">(in the last $DAY_DIFFS days)</span>"
				TIMESPAN=$DAY_DIFFS
			fi
			# find stats for since the day before $TIMESPAN_RAW days ago,
			# since no stats exist for today yet.
			local TIMESPAN="$(echo $TIMESPAN-1|bc)"
			local TIMESPAN_DATE=$(date '+%Y-%m-%d %H:%M' -d "- $TIMESPAN days")

			RESULT=$(query_db "SELECT COUNT(r.build_date) FROM stats_build AS r WHERE r.build_date > '$TIMESPAN_DATE' AND r.architecture='$ARCH'")
			RESULT="$(echo $RESULT/$TIMESPAN|bc)"
		else
			# very new arch with too few results to care about stats
			RESULT="&nbsp;"
		fi
		write_page "<td>${RESULT}${DISCLAIMER}</td>"
	done
	write_page "</tr>"
}
write_build_performance_stats() {
	local ARCH
	write_page "<table class=\"main\"><tr><th>Architecture build statistics</th>"
	for ARCH in ${ARCHS} ; do
		write_page " <th>$ARCH</th>"
	done
	write_page "</tr><tr><td class=\"left\">oldest build result in testing / unstable / experimental</td>"
	for ARCH in ${ARCHS} ; do
		AGE_UNSTABLE=$(query_db "SELECT CAST(greatest(max(oldest_reproducible), max(oldest_unreproducible), max(oldest_FTBFS)) AS INTEGER) FROM ${TABLE[2]} WHERE suite='unstable' AND architecture='$ARCH' AND datum='$DATE'")
		AGE_EXPERIMENTAL=$(query_db "SELECT CAST(greatest(max(oldest_reproducible), max(oldest_unreproducible), max(oldest_FTBFS)) AS INTEGER) FROM ${TABLE[2]} WHERE suite='experimental' AND architecture='$ARCH' AND datum='$DATE'")
		AGE_TESTING=$(query_db "SELECT CAST(greatest(max(oldest_reproducible), max(oldest_unreproducible), max(oldest_FTBFS)) AS INTEGER) FROM ${TABLE[2]} WHERE suite='testing' AND architecture='$ARCH' AND datum='$DATE'")
		write_page "<td>$AGE_TESTING / $AGE_UNSTABLE / $AGE_EXPERIMENTAL days</td>"
	done
	write_page "</tr><tr><td class=\"left\">average test duration (on $DATE)</td>"
	for ARCH in ${ARCHS} ; do
		RESULT=$(query_db "SELECT COALESCE(CAST(AVG(r.build_duration) AS INTEGER), 0) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.build_duration!='0' AND r.build_date LIKE '%$DATE%' AND s.architecture='$ARCH'")
		MIN=$(echo $RESULT/60|bc)
		SEC=$(echo "$RESULT-($MIN*60)"|bc)
		write_page "<td>$MIN minutes, $SEC seconds</td>"
	done

	local TIMESPAN_VERBOSE="4 weeks"
	local TIMESPAN_RAW="28"
	# Find stats for 28 days since yesterday, no stats exist for today

	local TIMESPAN="$(echo $TIMESPAN_RAW-1|bc)"
	local TIMESPAN_DATE=$(date '+%Y-%m-%d %H:%M' -d "- $TIMESPAN days")

	write_page "</tr><tr><td class=\"left\">average test duration (in the last $TIMESPAN_VERBOSE)</td>"
	for ARCH in ${ARCHS} ; do
		RESULT=$(query_db "SELECT COALESCE(CAST(AVG(r.build_duration) AS INTEGER), 0) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.build_duration!='0' AND r.build_date > '$TIMESPAN_DATE' AND s.architecture='$ARCH'")
		MIN=$(echo $RESULT/60|bc)
		SEC=$(echo "$RESULT-($MIN*60)"|bc)
		write_page "<td>$MIN minutes, $SEC seconds</td>"
	done

	write_page "</tr><tr><td class=\"left\">packages tested on $DATE</td>"
	for ARCH in ${ARCHS} ; do
		RESULT=$(query_db "SELECT COUNT(r.build_date) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.build_date LIKE '%$DATE%' AND s.architecture='$ARCH'")
		write_page "<td>$RESULT</td>"
	done
	write_page "</tr><tr><td class=\"left\">packages tested in the last 24h</td>"
	for ARCH in ${ARCHS} ; do
		RESULT=$(query_db "SELECT COUNT(r.build_date) FROM stats_build AS r WHERE r.build_date > '$(date '+%Y-%m-%d %H:%M' -d '-1 days')' AND r.architecture='$ARCH'")
		write_page "<td>$RESULT</td>"
	done
	write_page "</tr>"

	_average_builds_per_day "$TIMESPAN_RAW" "$TIMESPAN_VERBOSE"
	_average_builds_per_day "91" "3 months" "30"

	write_page "</table>"
}

#
# write suite/arch table
#
write_suite_arch_table() {
	local SUITE=""
	local ARCH=""
	write_page "<p>"
	write_page "<table class=\"main\"><tr><th class=\"left\">suite</th><th class=\"center\">all source packages</th><th class=\"center\">"
	set_icon reproducible
	write_icon
	write_page "reproducible packages</th><th class=\"center\">"
	set_icon unreproducible
	write_icon
	write_page "unreproducible packages</th><th class=\"center\">"
	set_icon FTBFS
	write_icon
	write_page "packages failing to build</th><th class=\"center\">"
	set_icon depwait
	write_icon
	write_page "packages in depwait state</th><th class=\"center\">"
	set_icon not_for_us
	write_icon
	write_page "not for this architecture</th><th class=\"center\">"
	set_icon blacklisted
	write_icon
	write_page "blacklisted</th></tr>"
	for SUITE in $SUITES ; do
		for ARCH in ${ARCHS} ; do
			gather_suite_arch_stats
			write_page "<tr><td class=\"left\"><a href=\"/debian/$SUITE/$ARCH\">$SUITE/$ARCH</a></td><td>$AMOUNT"
			if [ $(echo $PERCENT_TOTAL/1|bc) -lt 99 ] ; then
				write_page "<span style=\"font-size:0.8em;\">($PERCENT_TOTAL% tested)</span>"
			fi
			write_page "</td><td>$COUNT_GOOD / $PERCENT_GOOD%</td><td>$COUNT_BAD / $PERCENT_BAD%</td><td>$COUNT_UGLY / $PERCENT_UGLY%</td><td>$COUNT_DEPWAIT / $PERCENT_DEPWAIT%</td><td>$COUNT_NOTFORUS / $PERCENT_NOTFORUS%</td><td>$COUNT_BLACKLISTED / $PERCENT_BLACKLISTED%</td></tr>"
		done
	done
        write_page "</table>"
	write_page "</p><p style=\"clear:both;\">"
}

#
# create suite stats page
#
create_suite_arch_stats_page() {
	VIEW=suite_arch_stats
	PAGE=index_suite_${ARCH}_stats.html
	MAINLABEL[0]="Reproducibility status for packages in '$SUITE' for '$ARCH'"
	MAINLABEL[2]="Age in days of oldest reproducible build result in '$SUITE' for '$ARCH'"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of reproducible builds for packages in $SUITE for $ARCH"
	if [ $(echo $PERCENT_TOTAL/1|bc) -lt 100 ] ; then
		write_page "<p>$COUNT_TOTAL packages have been attempted to be build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE/$ARCH.</p>"
	fi
	write_page "<p>"
	set_icon reproducible
	write_icon
	write_page "$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly in $SUITE/$ARCH.<br />"
	set_icon unreproducible
	write_icon
	write_page "$COUNT_BAD packages ($PERCENT_BAD%) failed to build reproducibly.<br />"
	set_icon FTBFS
	write_icon
	write_page "$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source.<br /></p>"
	if [ $COUNT_DEPWAIT -gt 0 ] ; then
		write_page "For "
		set_icon depwait
		write_icon
		write_page "$COUNT_DEPWAIT ($PERCENT_DEPWAIT%) source packages the build-depends cannot be satisfied.<br />"
	fi
	if [ $COUNT_SOURCELESS -gt 0 ] ; then
		write_page "For "
		set_icon 404
		write_icon
		write_page "$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) source packages could not be downloaded.<br />"
	fi
	set_icon not_for_us
	write_icon
	if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
		ARMSPECIALARCH=" 'any-arm',"
	fi
	write_page "$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any', 'all', '$ARCH', 'linux-any', 'linux-$ARCH'$ARMSPECIALARCH nor 'any-$ARCH' will not be build here.<br />"
	write_page "and those "
	set_icon blacklisted
	write_icon
	write_page "$COUNT_BLACKLISTED ($PERCENT_BLACKLISTED%) packages have been blacklisted on $SUITE/$ARCH.<br />"
	write_page "</p><p>"
	write_page " <a href=\"/debian/$SUITE/$ARCH/${TABLE[0]}.png\"><img src=\"/debian/$SUITE/$ARCH/${TABLE[0]}.png\" alt=\"${MAINLABEL[0]}\"></a>"
	for i in 0 2 ; do
		# recreate png once a day
		if [ ! -f $DEBIAN_BASE/$SUITE/$ARCH/${TABLE[$i]}.png ] || [ $DUMMY_FILE -nt $DEBIAN_BASE/$SUITE/$ARCH/${TABLE[$i]}.png ] ; then
			create_png_from_table $i $SUITE/$ARCH/${TABLE[$i]}.png
		fi
	done
	write_page "</p>"
	if [ "$SUITE" != "experimental" ] ; then
		write_meta_pkg_graphs_links
	fi
	write_page_footer
	publish_page debian/$SUITE
}

write_meta_pkg_graphs_links () {
	write_page "<p style=\"clear:both;\"><center>"
	for i in $(seq 1 ${#META_PKGSET[@]}) ; do
		THUMB=${TABLE[6]}_${META_PKGSET[$i]}-thumbnail.png
		LABEL="Reproducibility status for packages in $SUITE/$ARCH from '${META_PKGSET[$i]}'"
		write_page "<a href=\"/debian/$SUITE/$ARCH/pkg_set_${META_PKGSET[$i]}.html\"  title=\"$LABEL\"><img src=\"/debian/$SUITE/$ARCH/$THUMB\" class=\"metaoverview\" alt=\"$LABEL\"></a>"
	done
	write_page "</center></p>"
}

write_global_graph() {
	write_page " <a href=\"/debian/${TABLE[$i]}.png\"><img src=\"/debian/${TABLE[$i]}.png\" class="halfview" alt=\"${MAINLABEL[$i]}\"></a>"
	# redo pngs once a day
	if [ ! -f $DEBIAN_BASE/${TABLE[$i]}.png ] || [ $DUMMY_FILE -nt $DEBIAN_BASE/${TABLE[$i]}.png ] ; then
		create_png_from_table $i ${TABLE[$i]}.png
	fi
}

#
# create dashboard page
#
create_dashboard_page() {
	VIEW=dashboard
	PAGE=index_${VIEW}.html
	SUITE="unstable"
	ARCH="amd64"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of various statistics about reproducible builds"
	write_suite_arch_table
	# write suite graphs
	for ARCH in ${ARCHS} ; do
		for SUITE in $SUITES ; do
			write_page " <a href=\"/debian/$SUITE/$ARCH\"><img src=\"/debian/$SUITE/$ARCH/${TABLE[0]}.png\" class=\"overview\" alt=\"$SUITE/$ARCH stats\"></a>"
		done
		SUITE="unstable"
		if [ "$ARCH" = "amd64" ] ; then
			write_meta_pkg_graphs_links
		fi
	done
	write_page "</p>"
	# write inventory table
	write_page "<p><table class=\"main\"><tr><th class=\"left\">Various reproducibility statistics</th><th class=\"center\">source based</th>"
	AC=0
	for ARCH in ${ARCHS} ; do
		write_page "<th class=\"center\">$ARCH</th>"
		let AC+=1
	done
	write_page "</tr>"
	ARCH="amd64"
	write_page "<tr><td class=\"left\">identified <a href=\"/debian/index_issues.html\">distinct and categorized issues</a></td><td>$ISSUES</td><td colspan=\"$AC\"></td></tr>"
	write_page "<tr><td class=\"left\">total number of identified issues in packages</td><td>$COUNT_ISSUES</td><td colspan=\"$AC\"></td></tr>"
	write_page "<tr><td class=\"left\">packages with notes about these issues</td><td>$NOTES</td><td colspan=\"$AC\"></td></tr>"

	local TD_PKG_SID_NOISSUES="<tr><td class=\"left\">packages in unstable with issues but without identified ones</td><td></td>"
	local TD_PKG_SID_FTBR="<tr><td class=\"left\">&nbsp;&nbsp;- unreproducible ones</a></td><td></td>"
	local TD_PKG_SID_FTBFS="<tr><td class=\"left\">&nbsp;&nbsp;- failing to build</a></td><td></td>"
	local TD_PKG_SID_ISSUES="<tr><td class=\"left\">packages in unstable which need to be fixed</td><td></td>"
	local TD_PKG_TESTING_NOISSUES="<tr><td class=\"left\">packages in testing with issues but without identified ones</td><td></td>"
	local TD_PKG_TESTING_FTBR="<tr><td class=\"left\">&nbsp;&nbsp;- unreproducible ones</a></td><td></td>"
	local TD_PKG_TESTING_FTBFS="<tr><td class=\"left\">&nbsp;&nbsp;- failing to build</a></td><td></td>"
	local TD_PKG_TESTING_ISSUES="<tr><td class=\"left\">packages in testing which need to be fixed</td><td></td>"
	for ARCH in ${ARCHS} ; do
		SUITE="unstable"
		gather_suite_arch_stats
		TD_PKG_SID_ISSUES="$TD_PKG_SID_ISSUES<td>$(echo $COUNT_BAD + $COUNT_UGLY |bc) / $(echo $PERCENT_BAD + $PERCENT_UGLY|bc)%</td>"

		RESULT=$(query_db "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status IN ('unreproducible', 'FTBFS', 'blacklisted') AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH') tmp")
		TD_PKG_SID_NOISSUES="$TD_PKG_SID_NOISSUES<td><a href=\"/debian/$SUITE/$ARCH/index_no_notes.html\">$RESULT</a> / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td>"
		RESULT=$(query_db "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='unreproducible' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH') tmp")
		TD_PKG_SID_FTBR="$TD_PKG_SID_FTBR<td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td>"
		RESULT=$(query_db "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='FTBFS' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH') tmp")
		TD_PKG_SID_FTBFS="$TD_PKG_SID_FTBFS<td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td>"

		SUITE="testing"
		gather_suite_arch_stats
		TD_PKG_TESTING_ISSUES="$TD_PKG_TESTING_ISSUES<td>$(echo $COUNT_BAD + $COUNT_UGLY |bc) / $(echo $PERCENT_BAD + $PERCENT_UGLY|bc)%</td>"
		RESULT=$(query_db "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status IN ('unreproducible', 'FTBFS', 'blacklisted') AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH') tmp")
		TD_PKG_TESTING_NOISSUES="$TD_PKG_TESTING_NOISSUES<td><a href=\"/debian/$SUITE/$ARCH/index_no_notes.html\">$RESULT</a> / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td>"
		RESULT=$(query_db "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='unreproducible' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH') tmp")
		TD_PKG_TESTING_FTBR="$TD_PKG_TESTING_FTBR<td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td>"
		RESULT=$(query_db "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='FTBFS' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH') tmp")
		TD_PKG_TESTING_FTBFS="$TD_PKG_TESTING_FTBFS<td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td>"
	done
	write_page "$TD_PKG_SID_NOISSUES</tr>"
	write_page "$TD_PKG_SID_FTBR</tr>"
	write_page "$TD_PKG_SID_FTBFS</tr>"
	write_page "$TD_PKG_SID_ISSUES</tr>"
	write_page "$TD_PKG_TESTING_NOISSUES</tr>"
	write_page "$TD_PKG_TESTING_FTBR</tr>"
	write_page "$TD_PKG_TESTING_FTBFS</tr>"
	write_page "$TD_PKG_TESTING_ISSUES</tr>"
	ARCH="amd64"
	SUITE="unstable"

	# in the following two write_page() calls we use the same
	# insane grep to filter people who committed with several
	# usernames…
	if [ -f ${NOTES_GIT_PATH}/packages.yml ] && [ -f ${NOTES_GIT_PATH}/issues.yml ] ; then
		write_page "<tr><td class=\"left\">committers to <a href=\"https://anonscm.debian.org/git/reproducible/notes.git\" target=\"_parent\">notes.git</a> (in the last three months)</td><td>$(cd ${NOTES_GIT_PATH} ; git log --since="3 months ago"|grep Author|sort -u | \
				grep -v alexis@passoire.fr | grep -v christoph.berg@credativ.de | grep -v d.s@daniel.shahaf.name | grep -v dhole@openmailbox.com | grep -v jelmer@jelmer.uk | grep -v mattia@mapreri.org | grep -v micha@lenk.info | grep -v mail@sandroknauss.de | grep -v sanvila@unex.es | \
				wc -l)</td><td colspan=\"$AC\"></td></tr>"
		write_page "<tr><td class=\"left\">committers to notes.git (in total)</td><td>$(cd ${NOTES_GIT_PATH} ; git log |grep Author|sort -u | \
				grep -v alexis@passoire.fr | grep -v christoph.berg@credativ.de | grep -v d.s@daniel.shahaf.name | grep -v dhole@openmailbox.com | grep -v jelmer@jelmer.uk | grep -v mattia@mapreri.org | grep -v micha@lenk.info | grep -v mail@sandroknauss.de | grep -v sanvila@unex.es | \
				wc -l)</td><td colspan=\"$AC\"></td></tr>"
	fi
	RESULT=$(cat /srv/reproducible-results/modified_in_sid.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
	write_page "<tr><td class=\"left\">packages <a href=\"/debian/index_repositories.html\">modified in our toolchain</a> (in unstable)</td><td>$(echo $RESULT)</td><td colspan=\"$AC\"></td></tr>"
	if ! diff /srv/reproducible-results/modified_in_sid.txt /srv/reproducible-results/modified_in_exp.txt ; then
		RESULT=$(cat /srv/reproducible-results/modified_in_exp.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
		write_page "<tr><td class=\"left\">&nbsp;&nbsp;- (in experimental)</td><td>$(echo $RESULT)</td><td colspan=\"$AC\"></td></tr>"
	fi
	RESULT=$(cat /srv/reproducible-results/binnmus_needed.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
	if [ "$RESULT" != "0" ] ; then
		write_page "<tr><td class=\"left\">&nbsp;&nbsp;- which need to be build on some archs</td><td>$(echo $RESULT)</td><td colspan=\"$AC\"></td></tr>"
	fi
	write_page "</table>"
	write_page "<p style=\"clear:both;\">"
	# show issue graphs
	for i in 4 5 ; do
		write_global_graph
	done
	write_page "</p>"
	# the end
	write_page_footer
	cp $PAGE $DEBIAN_BASE/reproducible.html
	publish_page debian
}

#
# create bugs page
#
create_bugs_page() {
	VIEW=bugs
	PAGE=index_${VIEW}.html
	ARCH="amd64"
	SUITE="unstable"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Bugs filed"
	# write bugs with usertags table
	write_usertag_table
	write_page "<p style=\"clear:both;\">"
	# show bug graphs
	for i in 8 9 3 7 ; do
		write_global_graph
	done
	write_page "</p>"
	write_page_footer
	publish_page debian
}

#
# create performance page
#
create_performance_page() {
	VIEW=performance
	PAGE=index_${VIEW}.html
	ARCH="amd64"
	SUITE="unstable"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Build node performance stats"
	# arch performance stats
	write_page "<p style=\"clear:both;\">"
	for ARCH in ${ARCHS} ; do
		MAINLABEL[1]="Amount of packages built each day on '$ARCH'"
		write_page " <a href=\"/debian/${TABLE[1]}_$ARCH.png\"><img src=\"/debian/${TABLE[1]}_$ARCH.png\" class=\"overview\" alt=\"${MAINLABEL[1]}\"></a>"
		if [ ! -f $DEBIAN_BASE/${TABLE[1]}_$ARCH.png ] || [ $DUMMY_FILE -nt $DEBIAN_BASE/${TABLE[1]}_$ARCH.png ] ; then
				create_png_from_table 1 ${TABLE[1]}_$ARCH.png
		fi
	done
	write_page "<p style=\"clear:both;\">"
	write_build_performance_stats
	# write suite builds age graphs
	write_page "</p><p style=\"clear:both;\">"
	for ARCH in ${ARCHS} ; do
		for SUITE in $SUITES ; do
			write_page " <a href=\"/debian/$SUITE/$ARCH/${TABLE[2]}.png\"><img src=\"/debian/$SUITE/$ARCH/${TABLE[2]}.png\" class=\"overview\" alt=\"age of oldest reproducible build result in $SUITE/$ARCH\"></a>"
		done
		write_page "</p><p style=\"clear:both;\">"
	done
	# the end
	write_page "Daily <a href=\"https://jenkins.debian.net/view/reproducible/job/reproducible_nodes_info/lastBuild/console\">individual build node performance stats</a> are available as well as oldest results for"
	for ARCH in ${ARCHS} ; do
		write_page " <a href=\"/debian/index_${ARCH}_oldies.html\">$ARCH</a>"
	done
	write_page ".</p>"
	write_page_footer
	publish_page debian
}

#
# create variations page
#
create_variations_page() {
	VIEW=variations
	PAGE=index_${VIEW}.html
	ARCH="amd64"
	SUITE="unstable"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Variations introduced when testing Debian packages"
	# explain setup
	write_variation_table debian
	write_page "<p style=\"clear:both;\">"
	write_page "</p>"
	write_page_footer
	publish_page debian
}

#
# main
#
SUITE="unstable"
update_bug_stats
update_notes_stats
for ARCH in ${ARCHS} ; do
	for SUITE in $SUITES ; do
		update_suite_arch_stats
		gather_suite_arch_stats
		create_suite_arch_stats_page
	done
done
create_performance_page
create_variations_page
create_bugs_page
create_dashboard_page
rm -f $DUMMY_FILE >/dev/null
