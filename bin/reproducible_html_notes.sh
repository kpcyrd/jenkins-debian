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

#
# this files are from the git repo cloned by the job-cfg
# on changes, this job is triggered
#
PACKAGES_YML=$PWD/packages.yml
ISSUES_YML=$PWD/issues.yml

#
# declare some variables
#
declare -A NOTES_VERSION
declare -A NOTES_ISSUES
declare -A NOTES_BUGS
declare -A NOTES_COMMENTS
declare -A ISSUES_DESCRIPTION
declare -A ISSUES_URL

#
# declare some functions only used for dealing with notes
#
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

write_meta_note() {
	write_page "<p>Notes are stored in <a href=\"https://anonscm.debian.org/cgit/reproducible/notes.git\">notes.git</a>.</p>"
}

create_pkg_note() {
	BUG=false
	rm -f $PAGE
	# write_page_header() is not used as it contains the <h2> tag...
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"$JENKINS_URL/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>Notes for $1</title></head>"
	write_page "<body></header>"
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
	write_meta_note
	write_page "</td></tr></table>"
	write_page_footer
}

create_issue() {
	BUG=false
	write_page_header "" "Notes about issue '$1'"
	write_page "<table class=\"body\">"

	write_page "<tr><td>Identifier:</td><th colspan=\"2\">$1</th></tr>"

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
			fi
			done < $TTMPFILE
			unset IFS
			rm $TTMPFILE
		fi
	done
	write_page "</td></tr>"
	write_page "<tr><td colspan=\"3\">&nbsp;</td></tr>"
	write_page "<tr><td colspan=\"3\" style=\"text-align:right; font-size:0.9em;\">"
	write_meta_note
	write_page "</td></tr></table>"
	write_page_meta_sign
	write_page_footer
}

write_issues() {
	touch $ISSUES_PATH/stamp
	for ISSUE in ${ISSUES} ; do
		PAGE=$ISSUES_PATH/${ISSUE}_issue.html
		echo "Updating ${ISSUE}_issue.html"
		create_issue $ISSUE
	done
	cd $ISSUES_PATH
	for FILE in *.html ; do
		# if issue is older than stamp file...
		if [ $FILE -ot stamp ] ; then
			rm $FILE
			echo "Deleting $FILE"
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
	# actually write notes
	for PKG in $PACKAGES_WITH_NOTES ; do
		PAGE=$NOTES_PATH/${PKG}_note.html
		create_pkg_note $PKG
	done
	echo
	# cleanup old notes and re-create package page if needed
	cd $NOTES_PATH
	for FILE in *.html ; do
		PKG_FILE=/var/lib/jenkins/userContent/rb-pkg/${FILE:0:-10}.html
		PKG=${FILE:0:-10}
		echo -n "Checking ${PKG_FILE} for ${PKG} - "
		# if note was removed...
		if [ $FILE -ot stamp ] ; then
			echo "old note found, removing and updating the package page."
			# cleanup old notes
			rm $FILE
			# force re-creation of package file if there was a note
			rm -f ${PKG_FILE}
			process_packages ${PKG}
		else
			# ... else re-recreate ${PKG_FILE} if it does not contain a link to the note already
			if ! grep _note.html ${PKG_FILE} > /dev/null 2>&1 ; then
				echo "note not mentioned in package page, updating it."
				rm -f ${PKG_FILE}
				process_packages ${PKG}
			else
				echo "ok."
			fi
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

#
# actually validate & parse the notes and then write pages for all notes and issues
#
validate_yaml ${ISSUES_YML}
validate_yaml ${PACKAGES_YML}
if $VALID_YAML ; then
	echo "$(date) - processing notes and issues"
	parse_issues
	parse_notes
	echo "$(date) - processing packages with notes"
	force_package_targets ${PACKAGES_WITH_NOTES}
	write_notes
	write_issues
else
	echo "Warning: ${ISSUES_YML} or ${PACKAGES_YML} contains invalid yaml, please fix."
fi

#
# write packages with notes page
#
VIEW=notes
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
if $VALID_YAML ; then
	write_page "<p>Packages which have notes: <code>"
	PACKAGES_WITH_NOTES=$(echo $PACKAGES_WITH_NOTES | sed -s "s# #\n#g" | sort | xargs echo)
	link_packages $PACKAGES_WITH_NOTES
	write_page "</code></p>"
else
	write_page "<p style=\"font-size:1.5em; color: red;\">Broken .yaml files in notes.git could not be parsed, please investigate and fix!</p>"
fi
write_meta_note
write_page_meta_sign
write_page_footer
publish_page

#
# write page with all issues
#
VIEW=issues
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
if $VALID_YAML ; then
	write_page "<table class=\"body\">"
	write_page "<tr><th>Identified issues</th></tr>"
	ISSUES=$(echo ${ISSUES} | sed -s "s# #\n#g" | sort | xargs echo)
	for ISSUE in ${ISSUES} ; do
		write_page "<tr><td><a href=\"$JENKINS_URL/userContent/issues/${ISSUE}_issue.html\">${ISSUE}</a></td></tr>"
	done
	write_page "</table>"
else
	write_page "<p style=\"font-size:1.5em; color: red;\">Broken .yaml files in notes.git could not be parsed, please investigate and fix!</p>"
fi
write_meta_note
write_page_footer
publish_page

