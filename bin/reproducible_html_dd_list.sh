#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

SUITE="sid"
ARCH="amd64"
init_html

VIEW=dd-list
for $SUITE in $SUITES ; do
	PAGE=$SUITE/index_${VIEW}.html
	echo "$(date) - starting to write $PAGE page."
	write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
	TMPFILE=$(mktemp)
	SOURCES=$(mktemp)
	schroot --directory /tmp -c source:jenkins-reproducible-$SUITE cat /var/lib/apt/lists/*_source_Sources > $SOURCES || \
	    wget ${MIRROR}/dists/$SUITE/main/source/Sources.xz -O - | xzcat > $SOURCES
	BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE r.status="unreproducible" AND s.suite='$SUITE' ORDER BY r.build_date DESC" | xargs echo)
	echo "${BAD}" | dd-list --stdin --sources $SOURCES > $TMPFILE || true
	write_page "<p>The following maintainers and uploaders are listed for packages in $SUITE which have built unreproducibly:</p><p><pre>"
	while IFS= read -r LINE ; do
		if [ "${LINE:0:3}" = "   " ] ; then
			PACKAGE=$(echo "${LINE:3}" | cut -d " " -f1)
			UPLOADERS=$(echo "${LINE:3}" | cut -d " " -f2-)
			if [ "$UPLOADERS" = "$PACKAGE" ] ; then
				UPLOADERS=""
			fi
			write_page "   <a href=\"/rb-pkg/$SUITE/$ARCH/$PACKAGE.html\">$PACKAGE</a> $UPLOADERS"
		else
			LINE="$(echo $LINE | sed 's#&#\&amp;#g ; s#<#\&lt;#g ; s#>#\&gt;#g')"
			write_page "$LINE"
		fi
	done < $TMPFILE
	write_page "</pre></p>"
	rm $TMPFILE
	rm $SOURCES
	write_page_footer
	publish_page
	echo
done

