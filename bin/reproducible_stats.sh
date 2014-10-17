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
declare -A GOOD
declare -A BAD
declare -A UGLY
declare -A SOURCELESS
declare -A NOTFORUS
declare -A STAR
declare -A LINKTARGET
declare -A SPOKENTARGET
LAST24="AND build_date > datetime('now', '-24 hours') "
LAST48="AND build_date > datetime('now', '-48 hours') "
SUITE=sid
AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT count(name) FROM sources")
ALLSTATES="reproducible FTBR_with_buildinfo FTBR FTBFS 404 not_for_us blacklisted"
MAINVIEW="stats"
ALLVIEWS="last_24h last_48h all_abc"
GOOD["all"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY build_date DESC" | xargs echo)
GOOD["last_24h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" $LAST24 ORDER BY build_date DESC" | xargs echo)
GOOD["last_48h"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" $LAST48 ORDER BY build_date DESC" | xargs echo)
GOOD["all_abc"]=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY name" | xargs echo)
COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
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
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
GUESS_GOOD=$(echo "$PERCENT_GOOD*$AMOUNT/100" | bc)
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

#
# gather notes
#
WORKSPACE=$PWD
cd /var/lib/jenkins
if [ -d notes.git ] ; then
	cd notes.git
	git pull
else
	git clone git://git.debian.org/git/reproducible/notes.git notes.git
fi
cd $WORKSPACE
PACKAGES_YML=/var/lib/jenkins/notes.git/packages.yml
ISSUES_YML=/var/lib/jenkins/notes.git/issues.yml
NOTES_PATH=/var/lib/jenkins/userContent/notes
ISSUES_PATH=/var/lib/jenkins/userContent/issues
mkdir -p $NOTES_PATH $ISSUES_PATH

declare -A NOTES_VERSION
declare -A NOTES_ISSUES
declare -A NOTES_BUGS
declare -A NOTES_COMMENTS
declare -A ISSUES_DESCRIPTION
declare -A ISSUES_URL

show_multi_values() {
	TMPFILE=$(mktemp)
	echo "$@" > $TMPFILE
	while IFS= read -r p ; do
		if [ "$p" = "-" ] || [ "$p" = "" ] ; then
			continue
		elif [ "${p:0:2}" = "- " ] ; then
			p="${p:2}"
		fi
		echo "    $PROPERTY = $p"
	done < $TMPFILE
	unset IFS
	rm $TMPFILE
}

tag_property_loop() {
	BEFORE=$1
	shift
	AFTER=$1
	shift
	TMPFILE=$(mktemp)
	echo "$@" > $TMPFILE
	while IFS= read -r p ; do
		if [ "$p" = "-" ] || [ "$p" = "" ] ; then
			continue
		elif [ "${p:0:2}" = "- " ] ; then
			p="${p:2}"
		fi
		write_page "$BEFORE"
		if $BUG ; then
			# turn bugs into links
			p="<a href=\"https://bugs.debian.org/$p\">#$p</a>"
		else
			# turn URLs into links
			p="$(echo $p |sed  -e 's|http[s:]*//[^ ]*|<a href=\"\0\">\0</a>|g')"
		fi
		write_page "$p"
		write_page "$AFTER"
	done < $TMPFILE
	unset IFS
	rm $TMPFILE
}

issues_loop() {
	TTMPFILE=$(mktemp)
	echo "$@" > $TTMPFILE
	while IFS= read -r p ; do
		if [ "${p:0:2}" = "- " ] ; then
			p="${p:2}"
		fi
		write_page "<table class=\"body\"><tr><td>Identifier:</td><td><a href=\"$JENKINS_URL/userContent/issues/${p}_issue.html\" target=\"_parent\">$p</a></tr>"
		if [ "${ISSUES_URL[$p]}" != "" ] ; then
			write_page "<tr><td>URL</td><td><a href=\"${ISSUES_URL[$p]}\" target=\"_blank\">${ISSUES_URL[$p]}</a></td></tr>"
		fi
		if [ "${ISSUES_DESCRIPTION[$p]}" != "" ] ; then
			write_page "<tr><td>Description</td><td>"
			tag_property_loop "" "<br />" "${ISSUES_DESCRIPTION[$p]}"
			write_page "</td></tr>"
		fi
		write_page "</table>"
	done < $TTMPFILE
	unset IFS
	rm $TTMPFILE
}

create_pkg_note() {
	BUG=false
	rm -f $PAGE
	# write_page_header() is not used as it contains the <h2> tag...
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"$JENKINS_URL/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>Notes for $1</title></head>"
	write_page "<body><header>"
	write_page "<table class=\"body\">"

	write_page "<tr><td>Version annotated:</td><td colspan=\"2\">${NOTES_VERSION[$1]}</td></tr>"

	if [ "${NOTES_ISSUES[$1]}" != "" ] ; then
		write_page "<tr><td colspan=\"2\">Identified issues:</td><td>"
		issues_loop "${NOTES_ISSUES[$1]}"
		write_page "</td></tr>"
	fi

	BUG=true
	if [ "${NOTES_BUGS[$1]}" != "" ] ; then
		write_page "<tr><td>Bugs noted:</td>"
		write_page "<td colspan=\"2\">"
		tag_property_loop "" "<br />" "${NOTES_BUGS[$1]}"
		write_page "</tr>"
	fi
	BUG=false

	if [ "${NOTES_COMMENTS[$1]}" != "" ] ; then
		write_page "<tr><td>Comments:</td>"
		write_page "<td colspan=\"2\">"
		tag_property_loop "" "<br />" "${NOTES_COMMENTS[$1]}"
		write_page "</tr>"
	fi
	write_page "<tr><td colspan=\"3\">&nbsp;</td></tr>"
	write_page "<tr><td colspan=\"3\" style=\"text-align:right; font-size:0.9em;\">"
	write_page "Notes are stored in <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\">notes.git</a>."
	write_page "</td></tr></table>"
	write_page_footer
}

create_issue() {
	BUG=false
	write_page_header "" "Notes about issue '$1'"
	write_page "<table class=\"body\">"

	write_page "<tr><td>Identifier:</td><td colspan=\"2\">$1</td></tr>"

	if [ "${ISSUES_URL[$1]}" != "" ] ; then
		write_page "<tr><td>URL:</td><td colspan=\"2\"><a href=\"${ISSUES_URL[$1]}\">${ISSUES_URL[$1]}</a></td></tr>"
	fi
	if [ "${ISSUES_DESCRIPTION[$1]}" != "" ] ; then
		write_page "<tr><td>Description:</td>"
		write_page "<td colspan=\"2\">"
		tag_property_loop "" "<br />" "${ISSUES_DESCRIPTION[$1]}"
		write_page "</td></tr>"
	fi

	write_page "<tr><td colspan=\"2\">Packages known to be affected by this issue:</td><td>"
	BETA_SIGN=false
	for PKG in $PACKAGES_WITH_NOTES ; do
		if [ "${NOTES_ISSUES[$PKG]}" != "" ] ; then
			TTMPFILE=$(mktemp)
			echo "${NOTES_ISSUES[$PKG]}" > $TTMPFILE
			while IFS= read -r p ; do
				if [ "${p:0:2}" = "- " ] ; then
					p="${p:2}"
				fi
			if [ "$p" = "$1" ] ; then
				write_page " ${LINKTARGET[$PKG]} "
				if ! $BETA_SIGN && [ "${STAR[$PKG]}" != "" ] ; then
					BETA_SIGN=true
				fi
			fi
			done < $TTMPFILE
			unset IFS
			rm $TTMPFILE
		fi
	done
	write_page "</td></tr>"
	write_page "<tr><td colspan=\"3\">&nbsp;</td></tr>"
	write_page "<tr><td colspan=\"3\" style=\"text-align:right; font-size:0.9em;\">"
	write_page "Notes are stored in <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\">notes.git</a>."
	write_page "</td></tr></table>"
	write_page_meta_sign
	write_page_footer
}

write_issues() {
	touch $ISSUES_PATH/stamp
	for ISSUE in ${ISSUES} ; do
		PAGE=$ISSUES_PATH/${ISSUE}_issue.html
		create_issue $ISSUE
	done
	cd $ISSUES_PATH
	for FILE in *.html ; do
		# if issue is older than stamp file...
		if [ $FILE -ot stamp ] ; then
			rm $FILE
		fi
	done
	rm stamp
	cd - > /dev/null
}

parse_issues() {
	ISSUES=$(cat ${ISSUES_YML} | /srv/jenkins/bin/shyaml keys)
	for ISSUE in ${ISSUES} ; do
		echo " Issue = ${ISSUE}"
		for PROPERTY in url description ; do
			VALUE="$(cat ${ISSUES_YML} | /srv/jenkins/bin/shyaml get-value ${ISSUE}.${PROPERTY} )"
			if [ "$VALUE" != "" ] ; then
				case $PROPERTY in
					url)		ISSUES_URL[${ISSUE}]=$VALUE
							echo "    $PROPERTY = $VALUE"
							;;
					description)	ISSUES_DESCRIPTION[${ISSUE}]=$VALUE
							show_multi_values "$VALUE"
							;;
				esac
			fi
		done
	done
}

write_notes() {
	touch $NOTES_PATH/stamp
	for PKG in $PACKAGES_WITH_NOTES ; do
		PAGE=$NOTES_PATH/${PKG}_note.html
		create_pkg_note $PKG
	done
	cd $NOTES_PATH
	for FILE in *.html ; do
		PKG_FILE=/var/lib/jenkins/userContent/rb-pkg/${FILE:0:-10}.html
		# if note was removed...
		if [ $FILE -ot stamp ] ; then
			# cleanup old notes
			rm $FILE
			# force re-creation of package file if there was a note
			rm ${PKG_FILE}
		else
			# ... else re-recreate ${PKG_FILE} if it does not contain a link to the note
			grep _note.html ${PKG_FILE} > /dev/null || rm ${PKG_FILE}
		fi
	done
	rm stamp
	cd - > /dev/null
}

parse_notes() {
	PACKAGES_WITH_NOTES=$(cat ${PACKAGES_YML} | /srv/jenkins/bin/shyaml keys)
	for PKG in $PACKAGES_WITH_NOTES ; do
		echo " Package = ${PKG}"
		for PROPERTY in version issues bugs comments ; do
			VALUE="$(cat ${PACKAGES_YML} | /srv/jenkins/bin/shyaml get-value ${PKG}.${PROPERTY} )"
			if [ "$VALUE" != "" ] ; then
				case $PROPERTY in
					version)	NOTES_VERSION[${PKG}]=$VALUE
							echo "    $PROPERTY = $VALUE"
							;;
					issues)		NOTES_ISSUES[${PKG}]=$VALUE
							show_multi_values "$VALUE"
							;;
					bugs)		NOTES_BUGS[${PKG}]=$VALUE
							show_multi_values "$VALUE"
							;;
					comments)	NOTES_COMMENTS[${PKG}]=$VALUE
							show_multi_values "$VALUE"
							;;
				esac
			fi
		done
	done
}

validate_yaml() {
	VALID_YAML=true
	set +e
	cat $1 | /srv/jenkins/bin/shyaml keys > /dev/null 2>&1 || VALID_YAML=false
	cat $1 | /srv/jenkins/bin/shyaml get-values > /dev/null 2>&1 || VALID_YAML=false
	set -e
	echo "$1 is valid yaml: $VALID_YAML"
}

#
# end note parsing functions...
#

mkdir -p /var/lib/jenkins/userContent/rb-pkg/

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

init_pkg_page() {
	echo "<!DOCTYPE html><html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />" > ${PKG_FILE}
	echo "<link href=\"../static/style.css\" type=\"text/css\" rel=\"stylesheet\" />" >> ${PKG_FILE}
	echo "<title>$1 - reproducible builds results</title></head>" >> ${PKG_FILE}
	echo "<body><table class=\"head\"><tr><td><span style=\"font-size:1.2em;\">$1</span> $2" >> ${PKG_FILE}
	set_icon "$3" $5 # this sets $STATE_TARGET_NAME and $ICON
	echo "<a href=\"$JENKINS_URL/userContent/index_${STATE_TARGET_NAME}.html\" target=\"_parent\"><img src=\"$JENKINS_URL/userContent/static/$ICON\" alt=\"${STATE_TARGET_NAME} icon\" /></a>" >> ${PKG_FILE}
	echo "<span style=\"font-size:0.9em;\">at $4:</span> " >> ${PKG_FILE}
}

append2pkg_page() {
	echo "$1" >> ${PKG_FILE}
}

finish_pkg_page() {
	echo "</td><td style=\"text-align:right; font-size:0.9em;\"><a href=\"$JENKINS_URL/userContent/reproducible.html\" target=\"_parent\">reproducible builds</a></td></tr></table>" >> ${PKG_FILE}
	echo "<iframe name=\"main\" src=\"$1\" width=\"100%\" height=\"98%\" frameborder=\"0\">" >> ${PKG_FILE}
	echo "<p>Your browser does not support iframes. Use a different one or follow the links above.</p>" >> ${PKG_FILE}
	echo "</iframe>" >> ${PKG_FILE}
	echo "</body></html>" >> ${PKG_FILE}
}

set_package_class() {
	if [ -f ${NOTES_PATH}/${PKG}_note.html ] ; then
		CLASS="class=\"noted\""
	else
		CLASS="class=\"package\""
	fi
}

process_packages() {
	for PKG in $@ ; do
		RESULT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT build_date,version,status FROM source_packages WHERE name = \"$PKG\"")
		BUILD_DATE=$(echo $RESULT|cut -d "|" -f1)
		# version with epoch removed
		EVERSION=$(echo $RESULT | cut -d "|" -f2 | cut -d ":" -f2)
		if $BUILDINFO_SIGNS && [ -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo" ] ; then
			STAR[$PKG]="<span class=\"beta\">&beta;</span>" # used to be a star...
		fi
		# only build $PKG pages if they don't exist or are older than $BUILD_DATE or have a note
		PKG_FILE="/var/lib/jenkins/userContent/rb-pkg/${PKG}.html"
		OLD_FILE=$(find $(dirname ${PKG_FILE}) -name $(basename ${PKG_FILE}) ! -newermt "$BUILD_DATE" 2>/dev/null || true)
		# if no package file exists, or is older than last build_date
		if [ ! -f ${PKG_FILE} ] || [ "$OLD_FILE" != "" ] ; then
			VERSION=$(echo $RESULT | cut -d "|" -f2)
			STATUS=$(echo $RESULT | cut -d "|" -f3)
			MAINLINK=""
			NOTES_LINK=""
			if [ -f ${NOTES_PATH}/${PKG}_note.html ] ; then
				NOTES_LINK=" <a href=\"$JENKINS_URL/userContent/notes/${PKG}_note.html\" target=\"main\">notes</a> "
			fi
			init_pkg_page "$PKG" "$VERSION" "$STATUS" "$BUILD_DATE" "${STAR[$PKG]}"
			append2pkg_page "${NOTES_LINK}"
			if [ -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo" ] ; then
				append2pkg_page " <a href=\"$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo\" target=\"main\">buildinfo</a> "
				MAINLINK="$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo"
			fi
			if [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html" ] ; then
				append2pkg_page " <a href=\"$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html\" target=\"main\">debbindiff</a> "
				MAINLINK="$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html"
			fi
			RBUILD_LOG="rbuild/${PKG}_${EVERSION}.rbuild.log"
			if [ -f "/var/lib/jenkins/userContent/${RBUILD_LOG}" ] ; then
				SIZE=$(du -sh "/var/lib/jenkins/userContent/${RBUILD_LOG}" |cut -f1)
				append2pkg_page " <a href=\"$JENKINS_URL/userContent/${RBUILD_LOG}\" target=\"main\">rbuild ($SIZE)</a> "
				if [ "$MAINLINK" = "" ] ; then
					MAINLINK="$JENKINS_URL/userContent/${RBUILD_LOG}"
				fi
			fi
			append2pkg_page " <a href=\"https://packages.qa.debian.org/${PKG}\" target=\"main\">PTS</a> "
			append2pkg_page " <a href=\"https://bugs.debian.org/src:${PKG}\" target=\"main\">BTS</a> "
			append2pkg_page " <a href=\"https://sources.debian.net/src/${PKG}/\" target=\"main\">sources</a> "
			append2pkg_page " <a href=\"https://sources.debian.net/src/${PKG}/${VERSION}/debian/rules\" target=\"main\">debian/rules</a> "

			if [ ! -z "${NOTES_LINK}" ] ; then
				MAINLINK="$JENKINS_URL/userContent/notes/${PKG}_note.html"
			fi
			finish_pkg_page "$MAINLINK"
		fi
		if [ -f "/var/lib/jenkins/userContent/rbuild/${PKG}_${EVERSION}.rbuild.log" ] ; then
			set_package_class
			LINKTARGET[$PKG]="<a href=\"$JENKINS_URL/userContent/rb-pkg/$PKG.html\" $CLASS>$PKG</a>${STAR[$PKG]}"
		else
			LINKTARGET[$PKG]="$PKG"
		fi
	done
}

force_package_targets() {
	for PKG in $@ ; do
		set_package_class
		LINKTARGET[$PKG]="<a href=\"$JENKINS_URL/userContent/rb-pkg/$PKG.html\" $CLASS>$PKG</a>${STAR[$PKG]}"
	done
}

link_packages() {
	for PKG in $@ ; do
		write_page " ${LINKTARGET[$PKG]} "
		if ! $BETA_SIGN && [ "${STAR[$PKG]}" != "" ] ; then
			BETA_SIGN=true
		fi
	done
}

write_page_header() {
	rm -f $PAGE
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"$JENKINS_URL/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	write_page "<body><header><h2>$2</h2>"
	if [ "$1" = "$MAINVIEW" ] || ; then
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

#
# actually parse the notes
#
validate_yaml ${ISSUES_YML}
validate_yaml ${PACKAGES_YML}
if $VALID_YAML ; then
	echo "$(date) - processing notes and issues"
	parse_issues
	parse_notes
	echo "$(date) - processing packages with notes"
	process_packages ${PACKAGES_WITH_NOTES}
	force_package_targets ${PACKAGES_WITH_NOTES}
	write_issues
	write_notes
else
	echo "Warning: ${ISSUES_YML} or ${PACKAGES_YML} contains invalid yaml, please fix."
fi

#
# actually build the package pages
#
echo "$(date) - processing $COUNT_TOTAL packages... this will take a while."
BUILDINFO_SIGNS=true
process_packages ${BAD["all"]}
BUILDINFO_SIGNS=false
process_packages ${UGLY["all"]} ${GOOD["all"]} ${SOURCELESS["all"]} ${NOTFORUS["all"]} $BLACKLISTED

for VIEW in $ALLVIEWS ; do
	BETA_SIGN=false
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
	link_packages ${GOOD[$VIEW]}
	write_page "</code></p>"
	write_page_meta_sign
	write_page_footer
	publish_page
done

VIEW=notes
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
if $VALID_YAML ; then
	BETA_SIGN=false
	write_page "<p>Packages which have notes: <code>"
	force_package_targets ${PACKAGES_WITH_NOTES}
	PACKAGES_WITH_NOTES=$(echo $PACKAGES_WITH_NOTES | sed -s "s# #\n#g" | sort | xargs echo)
	link_packages $PACKAGES_WITH_NOTES
	write_page "</code></p>"
else
	write_page "<p style=\"font-size:1.5em; color: red;\">Broken .yaml files in notes.git could not be parsed, please investigate and fix!</p>"
fi
write_page "<p style=\"font-size:0.9em;\">Notes are stored in <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\">notes.git</a>.</p>"
write_page_meta_sign
write_page_footer
publish_page

VIEW=issues
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
if $VALID_YAML ; then
	write_page "<table class=\"body\">"
	ISSUES=$(echo ${ISSUES} | sed -s "s# #\n#g" | sort | xargs echo)
	for ISSUE in ${ISSUES} ; do
		write_page "<tr><td><a href=\"$JENKINS_URL/userContent/issues/${ISSUE}_issue.html\">${ISSUE}</a></td></tr>"
	done
	write_page "</table>"
else
	write_page "<p style=\"font-size:1.5em; color: red;\">Broken .yaml files in notes.git could not be parsed, please investigate and fix!</p>"
fi
write_page "<p style=\"font-size:0.9em;\">Notes are stored in <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\">notes.git</a>.</p>"
write_page_footer
publish_page

count_packages() {
	COUNT=${#@}
	PERCENT=$(echo "scale=1 ; ($COUNT*100/$COUNT_TOTAL)" | bc)
}

for STATE in $ALLSTATES ; do
	BETA_SIGN=false
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
					if [ "${STAR[$PKG]}" = "" ] ; then
						PACKAGES="$PACKAGES $PKG"
					fi
				done
				;;
		FTBR_with_buildinfo)	CANDIDATES=${BAD["all"]}
				PACKAGES=""
				for PKG in $CANDIDATES ; do
					if [ "${STAR[$PKG]}" != "" ] ; then
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

VIEW=dd-list
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
TMPFILE=$(mktemp)
echo "${BAD["all"]}" | dd-list -i > $TMPFILE || true
write_page "<p>The following maintainers and uploaders are listed for packages which have built unreproducibly:</p><p><pre>"
while IFS= read -r LINE ; do
	if [ "${LINE:0:3}" = "   " ] ; then
		PACKAGE=$(echo "${LINE:3}" | cut -d " " -f1)
		UPLOADERS=$(echo "${LINE:3}" | cut -d " " -f2-)
		if [ "$UPLOADERS" = "$PACKAGE" ] ; then
			UPLOADERS=""
		fi
		write_page "   <a href=\"$JENKINS_URL/userContent/rb-pkg/$PACKAGE.html\">$PACKAGE</a> $UPLOADERS"
	else
		LINE="$(echo $LINE | sed 's#&#\&amp;#g ; s#<#\&lt;#g ; s#>#\&gt;#g')"
		write_page "$LINE"
	fi
done < $TMPFILE
write_page "</pre></p>"
rm $TMPFILE
write_page_footer
publish_page

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

echo "Enjoy $JENKINS_URL/userContent/reproducible.html"
