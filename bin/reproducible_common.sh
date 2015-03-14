#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#              © 2015 Mattia Rizzolo <mattia@mapreri.org>
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
		/srv/jenkins/bin/reproducible_db_maintenance.py
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

# tested suites
SUITES="testing sid experimental"
# tested arches
ARCHES="amd64"

# we only need them for html creation but we cannot declare them in a function
declare -A SPOKENTARGET
declare -A LINKTARGET

NOTES_PATH=/var/lib/jenkins/userContent/notes
ISSUES_PATH=/var/lib/jenkins/userContent/issues
RB_PATH=/var/lib/jenkins/userContent/rb-pkg/
mkdir -p $NOTES_PATH $ISSUES_PATH $RB_PATH

# create subdirs for suites
for i in $SUITES ; do
	mkdir -p /var/lib/jenkins/userContent/$i
done

# known package sets
META_PKGSET[1]="essential"
META_PKGSET[2]="required"
META_PKGSET[3]="build-essential"
META_PKGSET[4]="popcon_top1337-installed-sources"
META_PKGSET[5]="installed_on_debian.org"
META_PKGSET[6]="had_a_DSA"
META_PKGSET[7]="gnome"
META_PKGSET[8]="gnome_build-depends"
META_PKGSET[9]="tails"
META_PKGSET[10]="tails_build-depends"
META_PKGSET[11]="grml"
META_PKGSET[12]="grml_build-depends"
META_PKGSET[13]="maint_pkg-perl-maintainers"

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
		unreproducible|FTBR)	ICON=weather-showers-scattered.png
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
	write_page "<a href=\"/$SUITE/$ARCH/index_${STATE_TARGET_NAME}.html\" target=\"_parent\"><img src=\"/userContent/static/$ICON\" alt=\"${STATE_TARGET_NAME} icon\" /></a>"
}

write_page_header() {
	rm -f $PAGE
	MAINVIEW="stats"
	ALLSTATES="reproducible FTBR FTBFS 404 not_for_us blacklisted"
	ALLVIEWS="issues notes no_notes scheduled last_24h last_48h all_abc dd-list pkg_sets suite_stats repo_stats stats"
	GLOBALVIEWS="issues notes no_notes scheduled repo_stats stats"
	SUITEVIEWS="dd-list suite_stats"
	SPOKENTARGET["issues"]="issues"
	SPOKENTARGET["notes"]="packages with notes"
	SPOKENTARGET["no_notes"]="packages without notes"
	SPOKENTARGET["scheduled"]="currently scheduled"
	SPOKENTARGET["last_24h"]="packages tested in the last 24h"
	SPOKENTARGET["last_48h"]="packages tested in the last 48h"
	SPOKENTARGET["all_abc"]="all tested packages (sorted alphabetically)"
	SPOKENTARGET["dd-list"]="maintainers of unreproducible packages"
	SPOKENTARGET["pkg_sets"]="package sets stats"
	SPOKENTARGET["suite_stats"]="suite: $SUITE"
	SPOKENTARGET["repo_stats"]="repositories overview"
	SPOKENTARGET["stats"]="reproducible stats"
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	write_page "<body><header><h2>$2</h2>"
	if [ "$1" = "$MAINVIEW" ] ; then
		write_page "<p>These pages are showing the prospects of <a href=\"https://wiki.debian.org/ReproducibleBuilds\" target=\"_blank\">reproducible builds of Debian packages</a>. The results shown were obtained from <a href=\"$JENKINS_URL/view/reproducible\">several jobs running on jenkins.debian.net</a>. Thanks to <a href=\"https://www.profitbricks.com\">Profitbricks</a> for donating the virtual machine this is running on!</p>"
	fi
	if [ "$1" = "dd-list" ] || [ "$1" = "stats" ] ; then
		write_page "<p>Join <code>#debian-reproducible</code> on OFTC"
		write_page "   or <a href="mailto:reproducible-builds@lists.alioth.debian.org">send us an email</a>"
		write_page "   to get support for making sure your packages build reproducibly too!"
		write_page "</p>"
	fi
	write_page "<ul><li>Have a look at:</li>"
	for MY_STATE in $ALLSTATES ; do
		set_icon $MY_STATE
		write_page "<li>"
		write_icon
		write_page "</li>"
	done
	for TARGET in $ALLVIEWS ; do
		if [ "$TARGET" = "pkg_sets" ] && [ "$SUITE" = "experimental" ] ; then
			# no pkg_sets are tested in experimental
			continue
		fi
		SPOKEN_TARGET=${SPOKENTARGET[$TARGET]}
		BASEURL="/$SUITE/$ARCH"
		for i in $GLOBALVIEWS ; do
			if [ "$TARGET" = "$i" ] ; then
				BASEURL=""
			fi
		done
		for i in ${SUITEVIEWS} ; do
			if [ "$TARGET" = "$i" ] ; then
				BASEURL="/$SUITE"
			fi
		done
		write_page "<li><a href=\"$BASEURL/index_${TARGET}.html\">${SPOKEN_TARGET}</a></li>"
		if [ "$TARGET" = "suite_stats" ] ; then
			for i in $SUITES ; do
				if [ "$i" != "$SUITE" ] ; then
					write_page "<li><a href=\"/$i\">suite: $i</a></li>"
				fi
			done
		fi
	done
	write_page "<li><a href=\"https://wiki.debian.org/ReproducibleBuilds\" target=\"_blank\">wiki</a></li>"
	write_page "</ul>"
	write_page "</header>"
}

write_page_footer() {
	write_page "<hr/><p style=\"font-size:0.9em;\">There is more information <a href=\"$JENKINS_URL/userContent/about.html\">about jenkins.debian.net</a> and about <a href=\"https://wiki.debian.org/ReproducibleBuilds\"> reproducible builds of Debian</a> available elsewhere. Last update: $(date +'%Y-%m-%d %H:%M %Z'). Copyright 2014-2015 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a> and others, GPL2 licensed. The weather icons are public domain and have been taken from the <a href="http://tango.freedesktop.org/Tango_Icon_Library" target="_blank">Tango Icon Library</a>.</p>"
	write_page "</body></html>"
}

write_page_meta_sign() {
	write_page "<p style=\"font-size:0.9em;\">A package name displayed with a bold font is an indication that this package has a note. Visited packages are linked in green, those which have not been visited are linked in blue.</p>"
}

publish_page() {
	if [ "$1" = "" ] ; then
		if [ "$VIEW" = "$MAINVIEW" ] ; then
			cp $PAGE /var/lib/jenkins/userContent/reproducible.html
		fi
		TARGET=$PAGE
	else
		TARGET=$1/$PAGE
	fi
	cp $PAGE /var/lib/jenkins/userContent/$TARGET
	rm $PAGE
	echo "Enjoy $REPRODUCIBLE_URL/$TARGET"
}

set_package_class() {
	if [ -f ${NOTES_PATH}/${PKG}_note.html ] ; then
		CLASS="class=\"noted\""
	else
		CLASS="class=\"package\""
	fi
}

set_linktarget() {
	for PKG in $@ ; do
		if [ -f $RB_PATH/$SUITE/$ARCH/$PKG.html ] ; then
			set_package_class
			LINKTARGET[$PKG]="<a href=\"/userContent/rb-pkg/$SUITE/$ARCH/$PKG.html\" $CLASS>$PKG</a>"
		else
			LINKTARGET[$PKG]="$PKG"
		fi
	done
}

link_packages() {
	for PKG in $@ ; do
		write_page " ${LINKTARGET[$PKG]}"
	done
}

gen_packages_html() {
	local suite="$1"
	shift
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
		python3 -c "from reproducible_html_packages import gen_packages_html; gen_packages_html(${string}, suite=\"${suite}\", no_clean=True)" || echo "Warning: cannot update html pages for ${string} in ${suite}"
	done
	cd "$CWD"
}

