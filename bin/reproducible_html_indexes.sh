#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

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
UGLY["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY build_date DESC" | xargs echo)
UGLY["last_24h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" $LAST24 ORDER BY build_date DESC" | xargs echo)
UGLY["last_48h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" $LAST48 ORDER BY build_date DESC" | xargs echo)
UGLY["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY name" | xargs echo)
SOURCELESS["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY build_date DESC" | xargs echo)
SOURCELESS["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY name" | xargs echo)
NOTFORUS["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"not for us\" ORDER BY build_date DESC" | xargs echo)
NOTFORUS["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"not for us\" ORDER BY name" | xargs echo)
BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"blacklisted\" ORDER BY name" | xargs echo)
gather_stats

#
# actually build the package pages
#
echo "$(date) - processing $COUNT_TOTAL packages... this will take a while."
force_package_targets ${BAD["all"]}
force_package_targets ${UGLY["all"]} ${GOOD["all"]} ${SOURCELESS["all"]} ${NOTFORUS["all"]} $BLACKLISTED

for VIEW in last_24h last_48h all_abc ; do
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
	BUILDINFO_SIGNS=false
	PAGE=index_${STATE}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $STATE "Overview of ${SPOKENTARGET[$STATE]}"
	WITH=""
	case "$STATE" in
		reproducible)	PACKAGES=${GOOD["all"]}
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
		FTBR_with_buildinfo)
				BUILDINFO_SIGNS=true
				CANDIDATES=${BAD["all"]}
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
	if [ $COUNT -ne 0 ] ; then
		write_page_meta_sign
	fi
	write_page_footer
	publish_page
done

update_html_schedule
