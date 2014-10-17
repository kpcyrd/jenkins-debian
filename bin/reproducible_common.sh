#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# included by all reproducible_*.sh scripts
#
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ -f $PACKAGES_DB ] && [ -f $INIT ] ; then
	if [ -f $PACKAGES_DB.lock ] ; then
		for i in $(seq 0 100) ; do
			sleep 15
			if [ ! -f $PACKAGES_DB.lock ] ; then
				break
			fi
		done
		echo "$PACKAGES_DB.lock still exist, exiting."
		exit 1
	fi
elif [ ! -f ${PACKAGES_DB} ] ; then
	echo "Warning: $PACKAGES_DB doesn't exist, creating it now."
	echo 
	# create sqlite db if needed
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE source_packages
		(name TEXT NOT NULL,
		version TEXT NOT NULL,
		status TEXT NOT NULL
		CHECK (status IN ("blacklisted", "FTBFS","reproducible","unreproducible","404", "not for us")),
		build_date TEXT NOT NULL,
		PRIMARY KEY (name))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE sources_scheduled
		(name TEXT NOT NULL,
		date_scheduled TEXT NOT NULL,
		date_build_started TEXT NOT NULL,
		PRIMARY KEY (name))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE sources
		(name TEXT NOT NULL,
		version TEXT NOT NULL)'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_pkg_state
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		untested INTEGER,
		reproducible INTEGER,
		unreproducible INTEGER,
		FTBFS INTEGER,
		other INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_builds_per_day
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		reproducible INTEGER,
		unreproducible INTEGER,
		FTBFS INTEGER,
		other INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_builds_age
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		oldest_reproducible REAL,
		oldest_unreproducible REAL,
		oldest_FTBFS REAL,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_bugs
		(datum TEXT NOT NULL,
		open_toolchain INTEGER,
		done_toolchain INTEGER,
		open_infrastructure INTEGER,
		done_infrastructure INTEGER,
		open_timestamps INTEGER,
		done_timestamps INTEGER,
		open_fileordering INTEGER,
		done_fileordering INTEGER,
		open_buildpath INTEGER,
		done_buildpath INTEGER,
		open_username INTEGER,
		done_username INTEGER,
		open_hostname INTEGER,
		done_hostname INTEGER,
		open_uname INTEGER,
		done_uname INTEGER,
		open_randomness INTEGER,
		done_randomness INTEGER,
		PRIMARY KEY (datum))'
	# 60 seconds timeout when trying to get a lock
	cat >/var/lib/jenkins/reproducible.init <<-EOF
.timeout 60000
EOF
fi

# shop trailing slash
JENKINS_URL=${JENKINS_URL:0:-1}

init_html() {
	SUITE=sid
	ALLSTATES="reproducible FTBR_with_buildinfo FTBR FTBFS 404 not_for_us blacklisted"
	MAINVIEW="stats"
	ALLVIEWS="last_24h last_48h all_abc"
	declare -A SPOKENTARGET
	SPOKENTARGET["last_24h"]="packages tested in the last 24h"
	SPOKENTARGET["last_48h"]="packages tested in the last 48h"
	SPOKENTARGET["all_abc"]="all tested packages (sorted alphabetically)"
	SPOKENTARGET["dd-list"]="maintainers of unreproducible packages"
	SPOKENTARGET["stats"]="various statistics about reproducible builds"
	SPOKENTARGET["notes"]="packages with notes"
	SPOKENTARGET["issues"]="known issues related to reproducible builds"
	SPOKENTARGET["reproducible"]="packages which built reproducibly"
	SPOKENTARGET["FTBR"]="packages which failed to build reproducibly and don't create a .buildinfo file"
	SPOKENTARGET["FTBR_with_buildinfo"]="packages which failed to build reproducibly and create a .buildinfo file"
	SPOKENTARGET["FTBFS"]="packages which failed to build from source"
	SPOKENTARGET["404"]="packages where the sources failed to downloaded"
	SPOKENTARGET["not_for_us"]="packages which should not be build on 'amd64'"
	SPOKENTARGET["blacklisted"]="packages which have been blacklisted"
	NOTES_PATH=/var/lib/jenkins/userContent/notes
	ISSUES_PATH=/var/lib/jenkins/userContent/issues
	mkdir -p $NOTES_PATH $ISSUES_PATH
	# FIXME RB_PATH would also be a good idea
	mkdir -p /var/lib/jenkins/userContent/rb-pkg/
	# query some data we need everywhere
	AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT count(name) FROM sources")
	COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
	COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
	PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
	PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
	GUESS_GOOD=$(echo "$PERCENT_GOOD*$AMOUNT/100" | bc)
}

write_page() {
	echo "$1" >> $PAGE
}

set_icon() {
	# icons taken from tango-icon-theme (0.8.90-5)
	# licenced under http://creativecommons.org/licenses/publicdomain/
	STATE_TARGET_NAME="$1"
	case "$1" in
		reproducible)		ICON=weather-clear.png
					;;
		unreproducible|FTBR*)	if [ "$2" != "" ] ; then
						ICON=weather-showers-scattered.png
						STATE_TARGET_NAME=FTBR_with_buildinfo
					else
						ICON=weather-showers.png
						STATE_TARGET_NAME=FTBR
					fi
					;;
		FTBFS)			ICON=weather-storm.png
					;;
		404)			ICON=weather-severe-alert.png
					;;
		not_for_us|"not for us")	ICON=weather-few-clouds-night.png
					STATE_TARGET_NAME="not_for_us"
					;;
		blacklisted)		ICON=error.png
					;;
		*)			ICON=""
	esac
}

write_icon() {
	# ICON and STATE_TARGET_NAME are set by set_icon()
	write_page "<a href=\"$JENKINS_URL/userContent/index_${STATE_TARGET_NAME}.html\" target=\"_parent\"><img src=\"$JENKINS_URL/userContent/static/$ICON\" alt=\"${STATE_TARGET_NAME} icon\" /></a>"
}

write_page_header() {
	rm -f $PAGE
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"$JENKINS_URL/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	write_page "<body><header><h2>$2</h2>"
	if [ "$1" = "$MAINVIEW" ] ; then
		write_page "<p>These pages are updated every six hours. Results are obtained from <a href=\"$JENKINS_URL/view/reproducible\">several jobs running on jenkins.debian.net</a>. Thanks to <a href=\"https://www.profitbricks.com\">Profitbricks</a> for donating the virtual machine it's running on!</p>"
	fi
	write_page "<p>$COUNT_TOTAL packages have been attempted to be build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently. Out of these, $PERCENT_GOOD% were successful, so quite wildly guessing this roughy means about $GUESS_GOOD <a href=\"https://wiki.debian.org/ReproducibleBuilds\">packages should be reproducibly buildable!</a>"
	if [ "${1:0:3}" = "all" ] || [ "$1" = "dd-list" ] || [ "$1" = "stats" ] ; then
		write_page " Join <code>#debian-reproducible</code> on OFTC to get support for making sure your packages build reproducibly too!"
	fi
	write_page "</p>"
	write_page "<ul><li>Have a look at:</li>"
	for MY_STATE in $ALLSTATES ; do
		WITH=""
		if [ "$MY_STATE" = "FTBR_with_buildinfo" ] ; then
			WITH="YES"
		fi
		set_icon $MY_STATE $WITH
		write_page "<li>"
		write_icon
		write_page "</li>"
	done
	for TARGET in issues notes $ALLVIEWS dd-list stats ; do
		if [ "$TARGET" = "issues" ] || [ "$TARGET" = "stats" ]; then
			SPOKEN_TARGET=$TARGET
		else
			SPOKEN_TARGET=${SPOKENTARGET[$TARGET]}
		fi
		write_page "<li><a href=\"$JENKINS_URL/userContent/index_${TARGET}.html\">${SPOKEN_TARGET}</a></li>"
	done
	write_page "</ul>"
	write_page "</header>"
}

write_page_footer() {
	write_page "<hr/><p style=\"font-size:0.9em;\">There is more information <a href=\"$JENKINS_URL/userContent/about.html\">about jenkins.debian.net</a> and about <a href=\"https://wiki.debian.org/ReproducibleBuilds\"> reproducible builds of Debian</a> available elsewhere. Last update: $(date +'%Y-%m-%d %H:%M %Z'). Copyright 2014 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a>, GPL-2 licensed. The weather icons are public domain and have been taken from the <a href="http://tango.freedesktop.org/Tango_Icon_Library" target="_blank">Tango Icon Library</a>.</p>"
	write_page "</body></html>"
}

write_page_meta_sign() {
	write_page "<p style=\"font-size:0.9em;\">An underlined package is an indication that this package has a note. Visited packages are linked in green, those which have not been visited are linked in blue."
	if $BETA_SIGN ; then
		write_page "A &beta; sign after a package which is unreproducible indicates that a .buildinfo file was generated."
		write_page "And that means the <a href=\"https://wiki.debian.org/ReproducibleBuilds#The_basics_for_making_packages_build_reproducible\">basics for building packages reproducibly are covered</a>."
	fi
	write_page "</p>"
}

publish_page() {
	cp $PAGE /var/lib/jenkins/userContent/
	if [ "$VIEW" = "$MAINVIEW" ] ; then
		cp $PAGE /var/lib/jenkins/userContent/reproducible.html
	fi
	rm $PAGE
}

