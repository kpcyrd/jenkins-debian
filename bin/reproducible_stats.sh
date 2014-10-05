#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set +x
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ ! -f $PACKAGES_DB ] ; then
	echo "$PACKAGES_DB doesn't exist, no stats possible."
	exit 1
fi 

SUITE=sid
AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT amount FROM source_stats WHERE suite = \"$SUITE\"" | xargs echo)
GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY name" | xargs echo)
COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY build_date DESC" | xargs echo)
COUNT_BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"unreproducible\"")
UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY build_date DESC" | xargs echo)
COUNT_UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"FTBFS\"")
SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY build_date DESC" | xargs echo)
COUNT_SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"404\"" | xargs echo)
NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"not for us\" ORDER BY build_date DESC" | xargs echo)
COUNT_NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"not for us\"" | xargs echo)
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
GUESS_GOOD=$(echo "$PERCENT_GOOD*$AMOUNT/100" | bc)

htmlecho() {
	echo "$1" >> index.html
}

link_packages() {
	for PKG in $@ ; do
		VERSION=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT version FROM source_packages WHERE name = \"$PKG\"")
		# remove epoch
		EVERSION=$(echo $VERSION | cut -d ":" -f2)
		htmlecho $PKG
		if [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html" ] || [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.diffp.log" ] || [ -f "/var/lib/jenkins/userContent/pbuilder/${PKG}_${EVERSION}.pbuilder.log" ] || [ -f "/var/lib/jenkins/userContent/pbuilder/${PKG}_${EVERSION}.buildinfo" ] ; then
			htmlecho "<font size='-1'> ("
			if [ -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}.buildinfo.log" ] ; then
				htmlecho " <a href=\"$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}.buildinfo.log\"> buildinfo </a> "
			fi
			if [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html" ] ; then
				htmlecho " <a href=\"$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html\"> dbd </a> "
			elif [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.diffp.log" ] ; then
				htmlecho " <a href=\"$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.diffp.log\"> diffp </a> "
			fi
			if [ -f "/var/lib/jenkins/userContent/pbuilder/${PKG}_${EVERSION}.pbuilder.log" ] ; then
				htmlecho " <a href=\"$JENKINS_URL/userContent/pbuilder/${PKG}_${EVERSION}.pbuilder.log\"> pbuilder </a> "
			fi
			htmlecho ")</font> "
		fi
	done
}

htmlecho "<html><body>" > index.html
htmlecho "<h2>Statistics for reproducible builds</h2>"
htmlecho "<p>Results were obtained by <a href=\"$JENKINS_URL/view/reproducible\">several jobs running on jenkins.debian.net</a>. This page is updated after each job run.</p>"
htmlecho "<p>$COUNT_TOTAL packages attempted to build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently. Out of these, $PERCENT_GOOD% were successful, so quite wildly guessing this roughy means about $GUESS_GOOD packages should be reproducibly buildable!</p>"
htmlecho "<p>$COUNT_BAD packages ($PERCENT_BAD% of $COUNT_TOTAL) failed to built reproducibly: <code>"
link_packages $BAD
htmlecho "</code></p>"
htmlecho
htmlecho "<p>$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source: <code>"
link_packages $UGLY
htmlecho "</code></p>"
if [ $COUNT_SOURCELESS -gt 0 ] ; then
	htmlecho "<p>$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) packages where the source could not be downloaded. <code>$SOURCELESS</code></p>"
fi
if [ $COUNT_NOTFORUS -gt 0 ] ; then
	htmlecho "<p>$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any' nor 'all' nor 'amd64' nor 'linux-amd64': <code>$NOTFORUS</code></p>"
fi
htmlecho "<p>$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly: <code>"
link_packages $GOOD
htmlecho "</code></p>"
htmlecho "<hr><p>Packages which failed to build reproducibly, sorted by Maintainers: and Uploaders: fields."
htmlecho "<pre>$(echo $BAD | dd-list -i) </pre></p>"
htmlecho "<hr><p><font size='-1'><a href=\"$JENKINS_URL/userContent/reproducible.html\">Static URL for this page.</a> Last modified: $(date)</font>"
htmlecho "</p></body></html>"

# job output
html2text index.html
cp index.html /var/lib/jenkins/userContent/reproducible.html
