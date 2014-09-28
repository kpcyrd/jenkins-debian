#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set +x
PACKAGES_DB=/var/lib/jenkins/reproducible.db
if [ ! -f $PACKAGES_DB ] ; then
	echo "$PACKAGES_DB doesn't exist, no stats possible."
	exit 1
fi 

GOOD=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY name" | xargs echo)
COUNT_GOOD=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
BAD=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY build_date DESC" | xargs echo)
COUNT_BAD=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"unreproducible\"")
UGLY=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY build_date DESC" | xargs echo)
COUNT_UGLY=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"FTBFS\"")
SOURCELESS=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY build_date DESC" | xargs echo)
COUNT_SOURCELESS=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"404\"" | xargs echo)
COUNT_TOTAL=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")

htmlecho() {
	echo "$1" >> index.html
}
rm index.html

htmlecho "<html><body>" > index.html
htmlecho "<h2>Simple statistics for reproducible builds</h2>"
htmlecho "<p>Results were obtaining by <a href=\"$JENKINS_URL/view/reproducible\">several jobs running on jenkins.debian.net</a>.</p>"
htmlecho "<p>$COUNT_TOTAL packages attempted to build in total.</p>"
htmlecho "<p>$COUNT_GOOD packages successfully built reproducibly: <code>${GOOD}</code></p>"
htmlecho "$COUNT_BAD packages failed to built reproducibly: <code>"
for PKG in $BAD ; do
	VERSION=$(sqlite3 $PACKAGES_DB "SELECT version FROM source_packages WHERE name = \"$PKG\"")
	htmlecho "<a href=\"$JENKINS_URL/userContent/diffp/${PKG}_${VERSION}.diffp\">$PKG </a> "
done
htmlecho "</code></p>"
htmlecho
htmlecho "$COUNT_UGLY packages failed to build from source: <code>${UGLY}</code></p>"
htmlecho "$COUNT_SOURCELESS packages which don't exist in sid and need investigation: <code>$SOURCELESS<code></p>"
htmlecho "<hr><font size='-1'><a href=\"$JENKINS_URL/userContent/diffp.html\">Static URL for this page.</a> Last modified: $(date)</font>"
htmlecho "</ul></p></body></html>"

# job output
html2text index.html
cp index.html /var/lib/jenkins/userContent/diffp.html
