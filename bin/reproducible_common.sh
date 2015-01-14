#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# included by all reproducible_*.sh scripts
#
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ -f $PACKAGES_DB ] && [ -f $INIT ] ; then
	if [ -f ${PACKAGES_DB}.lock ] ; then
		for i in $(seq 0 100) ; do
			sleep 15
			echo "sleeping 15s, $PACKAGES_DB is locked."
			if [ ! -f ${PACKAGES_DB}.lock ] ; then
				break
			fi
		done
		if [ -f ${PACKAGES_DB}.lock ] ; then
			echo "${PACKAGES_DB}.lock still exist, exiting."
			exit 1
		fi
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
		open_buildinfo INTEGER,
		done_buildinfo INTEGER,
		open_cpu INTEGER,
		done_cpu INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_notes
		(datum TEXT NOT NULL,
		packages_with_notes INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_issues
		(datum TEXT NOT NULL,
		known_issues INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_meta_pkg_state
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		meta_pkg TEXT NOT NULL,
		reproducible INTEGER,
		unreproducible INTEGER,
		FTBFS INTEGER,
		other INTEGER,
		PRIMARY KEY (datum, suite, meta_pkg))'
	# 60 seconds timeout when trying to get a lock
	cat > $INIT <<-EOF
.timeout 60000
EOF
fi

# common variables
REPRODUCIBLE_URL=https://reproducible.debian.net
DBDCHROOT_READLOCK=/var/lib/jenkins/reproducible-dbdchroot.readlock
DBDCHROOT_WRITELOCK=/var/lib/jenkins/reproducible-dbdchroot.writelock
# shop trailing slash
JENKINS_URL=${JENKINS_URL:0:-1}

# we only need them for html creation but we cannot declare them in a function
declare -A SPOKENTARGET
declare -A LINKTARGET
NOTES_PATH=/var/lib/jenkins/userContent/notes
ISSUES_PATH=/var/lib/jenkins/userContent/issues
mkdir -p $NOTES_PATH $ISSUES_PATH
# FIXME RB_PATH would also be a good idea
mkdir -p /var/lib/jenkins/userContent/rb-pkg/

# known package sets
META_PKGSET[1]="essential"
META_PKGSET[2]="required"
META_PKGSET[3]="build-essential"
META_PKGSET[4]="gnome"
META_PKGSET[5]="gnome_build-depends"
META_PKGSET[6]="tails"
META_PKGSET[7]="tails_build-depends"
META_PKGSET[8]="maint_pkg-perl-maintainers"
META_PKGSET[9]="popcon_top1337-installed-sources"
META_PKGSET[10]="installed_on_debian.org"
META_PKGSET[11]="had_a_DSA"
META_PKGSET[12]="grml"
META_PKGSET[13]="grml_build-depends"

init_html() {
	SUITE=sid
	MAINVIEW="stats"
	ALLSTATES="reproducible FTBR_with_buildinfo FTBR FTBFS 404 not_for_us blacklisted"
	ALLVIEWS="issues notes scheduled last_24h last_48h all_abc dd-list stats pkg_sets"
	SPOKENTARGET["reproducible"]="packages which built reproducibly"
	SPOKENTARGET["FTBR"]="packages which failed to build reproducibly and do not create a .buildinfo file"
	SPOKENTARGET["FTBR_with_buildinfo"]="packages which failed to build reproducibly and create a .buildinfo file"
	SPOKENTARGET["FTBFS"]="packages which failed to build from source"
	SPOKENTARGET["404"]="packages where the sources failed to download"
	SPOKENTARGET["not_for_us"]="packages which should not be build on 'amd64'"
	SPOKENTARGET["blacklisted"]="packages which have been blacklisted"
	SPOKENTARGET["issues"]="known issues related to reproducible builds"
	SPOKENTARGET["notes"]="packages with notes"
	SPOKENTARGET["scheduled"]="packages currently scheduled for testing for build reproducibility"
	SPOKENTARGET["last_24h"]="packages tested in the last 24h"
	SPOKENTARGET["last_48h"]="packages tested in the last 48h"
	SPOKENTARGET["all_abc"]="all tested packages (sorted alphabetically)"
	SPOKENTARGET["dd-list"]="maintainers of unreproducible packages"
	SPOKENTARGET["stats"]="various statistics about reproducible builds"
	SPOKENTARGET["pkg_sets"]="statistics about reproducible builds of specific package sets"
	# query some data we need everywhere
	AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT count(name) FROM sources")
	COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
	COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
	PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
	PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
	BUILDINFO_SIGNS=true
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
	write_page "<a href=\"/index_${STATE_TARGET_NAME}.html\" target=\"_parent\"><img src=\"/userContent/static/$ICON\" alt=\"${STATE_TARGET_NAME} icon\" /></a>"
}

write_page_header() {
	rm -f $PAGE
	BUILDINFO_ON_PAGE=false
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	write_page "<body><header><h2>$2</h2>"
	if [ "$1" = "$MAINVIEW" ] ; then
		write_page "<p>These pages contain results obtained from <a href=\"$JENKINS_URL/view/reproducible\">several jobs running on jenkins.debian.net</a>. Thanks to <a href=\"https://www.profitbricks.com\">Profitbricks</a> for donating the virtual machine it's running on!</p>"
	fi
	write_page "<p>$COUNT_TOTAL packages have been attempted to be build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently. Out of these, $COUNT_GOOD packages ($PERCENT_GOOD%) <a href=\"https://wiki.debian.org/ReproducibleBuilds\">could be built reproducible!</a>"
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
	for TARGET in $ALLVIEWS ; do
		if [ "$TARGET" = "issues" ] || [ "$TARGET" = "stats" ] ; then
			SPOKEN_TARGET=$TARGET
		elif [ "$TARGET" = "scheduled" ] ; then
			SPOKEN_TARGET="currently scheduled"
		elif [ "$TARGET" = "pkg_sets" ] ; then
			SPOKEN_TARGET="package sets stats"
		else
			SPOKEN_TARGET=${SPOKENTARGET[$TARGET]}
		fi
		write_page "<li><a href=\"/index_${TARGET}.html\">${SPOKEN_TARGET}</a></li>"
	done
	write_page "</ul>"
	write_page "</header>"
}

write_page_footer() {
	write_page "<hr/><p style=\"font-size:0.9em;\">There is more information <a href=\"$JENKINS_URL/userContent/about.html\">about jenkins.debian.net</a> and about <a href=\"https://wiki.debian.org/ReproducibleBuilds\"> reproducible builds of Debian</a> available elsewhere. Last update: $(date +'%Y-%m-%d %H:%M %Z'). Copyright 2014-2015 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a>, GPL-2 licensed. The weather icons are public domain and have been taken from the <a href="http://tango.freedesktop.org/Tango_Icon_Library" target="_blank">Tango Icon Library</a>.</p>"
	write_page "</body></html>"
}

write_page_meta_sign() {
	write_page "<p style=\"font-size:0.9em;\">A package name displayed with a bold font is an indication that this package has a note. Visited packages are linked in green, those which have not been visited are linked in blue."
	if $BUILDINFO_ON_PAGE ; then
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
	echo "Enjoy $REPRODUCIBLE_URL/$PAGE"
}

set_package_star() {
	if [ -f /var/lib/jenkins/userContent/buildinfo/${PKG}_.buildinfo ] ; then
		STAR="<span class=\"beta\">&beta;</span>" # used to be a star...
	else
		STAR=""
	fi
}

set_package_class() {
	if [ -f ${NOTES_PATH}/${PKG}_note.html ] ; then
		CLASS="class=\"noted\""
	else
		CLASS="class=\"package\""
	fi
}

force_package_targets() {
	for PKG in $@ ; do
		if [ -f /var/lib/jenkins/userContent/rb-pkg/$PKG.html ] ; then
			set_package_class
			LINKTARGET[$PKG]="<a href=\"/userContent/rb-pkg/$PKG.html\" $CLASS>$PKG</a>"
		else
			LINKTARGET[$PKG]="$PKG"
		fi
	done
}

link_packages() {
	STAR=""
	for PKG in $@ ; do
		if $BUILDINFO_SIGNS ; then
			set_package_star
			if ! $BUILDINFO_ON_PAGE && [ ! -z "$STAR" ] ; then
				BUILDINFO_ON_PAGE=true
			fi

		fi
		write_page " ${LINKTARGET[$PKG]}$STAR"
	done
}

process_packages() {
	CWD=$(pwd)
	cd /srv/jenkins/bin
	for (( i=1; i<$#+1; i=i+100 )) ; do
		string='['
		delimiter=''
		for (( j=0; j<100; j++)) ; do
			item=$(( $j+$i ))
			if (( $item < $#+1 )) ; then
				string+="${delimiter}\"${!item}\""
				delimiter=','
			fi
		done
		string+=']'
		python3 -c "from reproducible_html_packages import process_packages; process_packages(${string}, no_clean=True)"
	done
	python3 -c "from reproducible_html_packages import purge_old_pages; purge_old_pages()"
	cd "$CWD"
}

gather_schedule_stats() {
	SCHEDULED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM sources_scheduled ORDER BY date_scheduled" | xargs echo)
	COUNT_SCHEDULED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT count(name) FROM sources_scheduled" | xargs echo)
	QUERY="	SELECT count(sources.name) FROM sources,source_packages
			WHERE sources.name NOT IN
			(SELECT sources.name FROM sources,sources_scheduled
				WHERE sources.name=sources_scheduled.name)
			AND sources.name IN
			(SELECT sources.name FROM sources,source_packages
				WHERE sources.name=source_packages.name
				AND sources.version!=source_packages.version
				AND source_packages.status!='blacklisted')
			AND sources.name=source_packages.name"
	COUNT_NEW_VERSIONS=$(sqlite3 -init $INIT $PACKAGES_DB "$QUERY")
}

gather_stats() {
	COUNT_BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"unreproducible\"")
	COUNT_UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"FTBFS\"")
	COUNT_SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"404\"")
	COUNT_NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"not for us\"")
	COUNT_BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"blacklisted\"")
	PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
	PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
	PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
	PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
}

update_html_schedule() {
	VIEW=scheduled
	BUILDINFO_SIGNS=true
	PAGE=index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
	gather_schedule_stats
	if [ ${COUNT_NEW_VERSIONS} -ne 0 ] ; then
		write_page "<p>For ${COUNT_NEW_VERSIONS} packages newer versions are available which have not been tested yet.</p>"
	fi
	write_page "<p>${COUNT_SCHEDULED} packages are currently scheduled for testing: <code>"
	force_package_targets $SCHEDULED
	link_packages $SCHEDULED
	write_page "</code></p>"
	write_page_meta_sign
	write_page_footer
	publish_page
}
