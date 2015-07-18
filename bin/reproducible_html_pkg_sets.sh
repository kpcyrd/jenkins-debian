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

# variables related to the stats we do
TABLE[6]=stats_meta_pkg_state
FIELDS[6]="datum, reproducible, unreproducible, FTBFS, other"
COLOR[6]=4

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
# main
#
for SUITE in $SUITES ; do
	if [ "$SUITE" = "experimental" ] ; then
		# no pkg sets in experimental
		continue
	fi
	update_meta_pkg_stats
	create_pkg_sets_pages
done

