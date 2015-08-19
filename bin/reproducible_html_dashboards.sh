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
# we only do stats up until yesterday... we also could do today too but not update the db yet...
DATE=$(date -d "1 day ago" '+%Y-%m-%d')
FORCE_DATE=$(date -d "2 day ago" '+%Y-%m-%d')
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
	FIELDS[3]="${FIELDS[3]}, open_$TAG, done_$TAG"
done
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
COLOR[0]=5
COLOR[1]=12
COLOR[2]=1
COLOR[3]=32
COLOR[4]=1
COLOR[5]=1
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
update_suite_arch_stats() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,suite from ${TABLE[0]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\"")
	if [ -z $RESULT ] ; then
		echo "Updating packages and builds stats for $SUITE/$ARCH in $DATE."
		ALL=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(name) FROM sources WHERE suite='${SUITE}' AND architecture='$ARCH'")
		GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'reproducible' AND date(r.build_date)<='$DATE';")
		GOOAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'reproducible' AND date(r.build_date)='$DATE';")
		BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible' AND date(r.build_date)<='$DATE';")
		BAAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible' AND date(r.build_date)='$DATE';")
		UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS' AND date(r.build_date)<='$DATE';")
		UGLDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id  WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS' AND date(r.build_date)='$DATE';")
		REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND s.suite='$SUITE' AND s.architecture='$ARCH' AND date(r.build_date)<='$DATE';")
		RESDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(r.status) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE (r.status != 'FTBFS' AND r.status != 'unreproducible' AND r.status != 'reproducible') AND s.suite='$SUITE' AND s.architecture='$ARCH' AND date(r.build_date)='$DATE';")
		OLDESTG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.status = 'reproducible' AND s.suite='$SUITE' AND s.architecture='$ARCH' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		OLDESTB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'unreproducible' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
		OLDESTU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT r.build_date FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND r.status = 'FTBFS' AND NOT date(r.build_date)>='$DATE' ORDER BY r.build_date LIMIT 1;")
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
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[0]} VALUES (\"$DATE\", \"$SUITE\", \"$ARCH\", $UNTESTED, $GOOD, $BAD, $UGLY, $REST)" 
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[1]} VALUES (\"$DATE\", \"$SUITE\", \"$ARCH\", $GOOAY, $BAAY, $UGLDAY, $RESDAY)"
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[2]} VALUES (\"$DATE\", \"$SUITE\", \"$ARCH\", \"$DIFFG\", \"$DIFFB\", \"$DIFFU\")"
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
	NOTES=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(package_id) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\"")
	ISSUES=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(name) FROM issues")
	# the following is a hack to workaround the bad sql db design which is the issue_s_ column in the notes table...
	# it assumes we don't have packages with more than 7 issues. (we have one with 6...)
	COUNT_ISSUES=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues = \"[]\") \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues != \"[]\" AND n.issues NOT LIKE \"%,%\") \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues LIKE \"%,%\") \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues LIKE \"%,%,%\") \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues LIKE \"%,%,%,%\") \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues LIKE \"%,%,%,%,%\") \
		+ \
		(SELECT COUNT(issues) FROM notes AS n JOIN sources AS s ON n.package_id=s.id WHERE s.suite=\"unstable\" AND n.issues LIKE \"%,%,%,%,%,%\") \
		")
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum from ${TABLE[4]} WHERE datum = \"$DATE\"")
	if [ -z $RESULT ] ; then
		echo "Updating notes stats for $DATE."
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[4]} VALUES (\"$DATE\", \"$NOTES\")"
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[5]} VALUES (\"$DATE\", \"$ISSUES\")"
	fi
	echo "Adhoc-Debug: $NOTES $ISSUES $COUNT_ISSUES"
}

#
# gather suite/arch stats
#
gather_suite_arch_stats() {
	AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT count(*) FROM sources WHERE suite=\"${SUITE}\" AND architecture=\"$ARCH\"")
	COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite=\"${SUITE}\" AND s.architecture=\"$ARCH\"")
	COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite=\"${SUITE}\" AND s.architecture=\"$ARCH\" AND r.status=\"reproducible\"")
	COUNT_BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture=\"$ARCH\" AND r.status = \"unreproducible\"")
	COUNT_UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture=\"$ARCH\" AND r.status = \"FTBFS\"")
	COUNT_SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture=\"$ARCH\" AND r.status = \"404\"")
	COUNT_NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture=\"$ARCH\" AND r.status = \"not for us\"")
	COUNT_BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture=\"$ARCH\" AND r.status = \"blacklisted\"")
	COUNT_DEPWAIT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(s.name) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite='$SUITE' AND s.architecture=\"$ARCH\" AND r.status = \"depwait\"")
	COUNT_OTHER=$(( $COUNT_SOURCELESS+$COUNT_NOTFORUS+$COUNT_BLACKLISTED+$COUNT_DEPWAIT ))
	PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
	PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
	PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
	PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
	PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
	PERCENT_DEPWAIT=$(echo "scale=1 ; ($COUNT_DEPWAIT*100/$COUNT_TOTAL)" | bc)
	PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
	PERCENT_OTHER=$(echo "scale=1 ; ($COUNT_OTHER*100/$COUNT_TOTAL)" | bc)
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
		write_page "<tr><td>Total number of <a href=\"https://wiki.debian.org/ReproducibleBuilds/Contribute#How_to_report_bugs\">usertags related to reproducible builds</a> on $DATE<br />(this is not the number of bugs as bugs can have several tags)</td><td>$TOPEN</td><td>$TDONE</td><td>$TTOTAL</td></tr>"
		write_page "</table>"
	fi
}

#
# create suite stats page
#
create_suite_arch_stats_page() {
	VIEW=suite_${ARCH}_stats
	PAGE=index_${VIEW}.html
	MAINLABEL[0]="Reproducibility status for packages in '$SUITE' for '$ARCH'"
	MAINLABEL[2]="Age in days of oldest reproducible build result in '$SUITE' for '$ARCH'"
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of reproducible builds for packages in $SUITE for $ARCH"
	if [ $(echo $PERCENT_TOTAL/1|bc) -lt 98 ] ; then
		write_page "<p>$COUNT_TOTAL packages have been attempted to be build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE/$ARCH.</p>"
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
	if [ $COUNT_DEPWAIT -gt 0 ] ; then
		write_page "For "
		set_icon depwait
		write_icon
		write_page "$COUNT_DEPWAIT ($PERCENT_DEPWAIT%) source packages the build-depends cannot be satisfied."
	fi
	if [ $COUNT_SOURCELESS -gt 0 ] ; then
		write_page "For "
		set_icon 404
		write_icon
		write_page "$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) source packages could not be downloaded,"
	fi
	set_icon not_for_us
	write_icon
	write_page "$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any', 'all', '$ARCH', 'linux-any', 'linux-$ARCH' nor 'any-$ARCH' will not be build here"
	write_page "and those "
	set_icon blacklisted
	write_icon
	write_page "$COUNT_BLACKLISTED blacklisted packages neither.</p>"
	write_page "<p>"
	write_page " <a href=\"/userContent/$SUITE/$ARCH/${TABLE[0]}.png\"><img src=\"/userContent/$SUITE/$ARCH/${TABLE[0]}.png\" alt=\"${MAINLABEL[0]}\"></a>"
	for i in 0 2 ; do
		# recreate png once a day
		if [ ! -f $BASE/$SUITE/$ARCH/${TABLE[$i]}.png ] || [ ! -z $(find $BASE/$SUITE/$ARCH -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
			create_png_from_table $i $SUITE/$ARCH/${TABLE[$i]}.png
		fi
	done
	write_page "</p>"
	write_page_footer
	publish_page $SUITE
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
	write_page "<table class=\"main\"><tr><th>suite</th><th>all sources packages</th><th>reproducible packages</th><th>unreproducible packages</th><th>packages failing to build</th><th>other packages</th><th>&nbsp;</th></tr>"
	for SUITE in $SUITES ; do
		gather_suite_arch_stats
		write_page "<tr><td>$SUITE</td><td>$AMOUNT"
		if [ $(echo $PERCENT_TOTAL/1|bc) -lt 98 ] ; then
			write_page "<span style=\"font-size:0.8em;\">($PERCENT_TOTAL% tested)</span>"
		fi
		if [ "$SUITE" = "unstable" ] ; then
			FINALLY_SID_AGAIN="Debian <em>unstable</em> is currently experiencing <a href=\"https://release.debian.org/transitions/html/libstdc++6.html\">a massive transition</a> and thus is currently quite broken, which is also shown by our current tests."
		else
			FINALLY_SID_AGAIN=""
		fi
		write_page "</td><td>$COUNT_GOOD / $PERCENT_GOOD%</td><td>$COUNT_BAD / $PERCENT_BAD%</td><td>$COUNT_UGLY / $PERCENT_UGLY%</td><td>$COUNT_OTHER / $PERCENT_OTHER%</td><td>$FINALLY_SID_AGAIN</td></tr>"
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
	write_page "<table class=\"main\"><tr><th colspan=\"2\">Various reproducibility statistics</th></tr>"
	write_page "<tr><td>identified <a href=\"/index_issues.html\">distinct and categorized issues</a></td><td>$ISSUES</td></tr>"
	write_page "<tr><td>total number of identified issues in packages</td><td>$COUNT_ISSUES</td></tr>"
	write_page "<tr><td>packages with notes about these issues</td><td>$NOTES</td></tr>"
	SUITE="unstable"
	gather_suite_arch_stats
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status IN ('unreproducible', 'FTBFS', 'blacklisted') AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH')")
	write_page "<tr><td>packages in $SUITE with issues but <a href=\"/$SUITE/$ARCH/index_no_notes.html\">without identified ones</a></td><td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='unreproducible' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH')")
	write_page "<tr><td>&nbsp;&nbsp;- unreproducible ones</a></td><td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td></tr>"
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status='FTBFS' AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='$SUITE' AND s.architecture='$ARCH')")
	write_page "<tr><td>&nbsp;&nbsp;- failing to build</a></td><td>$RESULT / $(echo "scale=1 ; ($RESULT*100/$COUNT_TOTAL)" | bc)%</td></tr>"
	write_page "<tr><td>packages in $SUITE which need to be fixed</td><td>$(echo $COUNT_BAD + $COUNT_UGLY |bc) / $(echo $PERCENT_BAD + $PERCENT_UGLY|bc)%</td></tr>"
	SUITE="testing"
	gather_suite_arch_stats
	write_page "<tr><td>&nbsp;&nbsp;- in $SUITE</td><td>$(echo $COUNT_BAD + $COUNT_UGLY |bc) / $(echo $PERCENT_BAD + $PERCENT_UGLY|bc)%</td></tr>"
	SUITE="unstable"
	if [ -f ${NOTES_GIT_PATH}/packages.yml ] && [ -f ${NOTES_GIT_PATH}/issues.yml ] ; then
		write_page "<tr><td>committers to <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\" target=\"_parent\">notes.git</a> (in the last three months)</td><td>$(cd ${NOTES_GIT_PATH} ; git log --since="3 months ago"|grep Author|sort -u |wc -l)</td></tr>"
		write_page "<tr><td>committers to notes.git (in total)</td><td>$(cd ${NOTES_GIT_PATH} ; git log |grep Author|sort -u |wc -l)</td></tr>"
	fi
	RESULT=$(cat /srv/reproducible-results/modified_in_sid.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
	write_page "<tr><td>packages <a href=\"/index_repositories.html\">modified in our toolchain</a> (in unstable)</td><td>$(echo $RESULT)</td></tr>"
	RESULT=$(cat /srv/reproducible-results/modified_in_exp.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
	write_page "<tr><td>&nbsp;&nbsp;- (in experimental)</td><td>$(echo $RESULT)</td></tr>"
	RESULT=$(cat /srv/reproducible-results/binnmus_needed.txt || echo "unknown")	# written by reproducible_html_repository_comparison.sh
	if [ "$RESULT" != "0" ] ; then
		write_page "<tr><td>&nbsp;&nbsp;- which need to be build on some archs</td><td>$(echo $RESULT)</td></tr>"
	fi
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
	write_page "<table class=\"main\"><tr><th colspan=\"2\">Build statistics</th></tr>"
	AGE_TESTING=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(max(oldest_reproducible, oldest_unreproducible, oldest_FTBFS) AS INTEGER) FROM ${TABLE[2]} WHERE suite='testing' AND architecture='$ARCH' AND datum='$DATE'")
	AGE_UNSTABLE=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(max(oldest_reproducible, oldest_unreproducible, oldest_FTBFS) AS INTEGER) FROM ${TABLE[2]} WHERE suite='unstable' AND architecture='$ARCH' AND datum='$DATE'")
	AGE_EXPERIMENTAL=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT CAST(max(oldest_reproducible, oldest_unreproducible, oldest_FTBFS) AS INTEGER) FROM ${TABLE[2]} WHERE suite='experimental' AND architecture='$ARCH' AND datum='$DATE'")
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
for ARCH in ${ARCHS} ; do
	for SUITE in $SUITES ; do
		update_suite_arch_stats
		gather_suite_arch_stats
		create_suite_arch_stats_page
	done
done
ARCH="amd64"
SUITE="unstable"
create_main_stats_page

