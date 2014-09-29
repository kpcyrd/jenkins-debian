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
# 30 seconds timeout when trying to get a lock
INIT=/var/lib/jenkins/reproducible.init
cat >/var/lib/jenkins/reproducible.init <<-EOF
.timeout 30000
EOF

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
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
GUESS_GOOD=$(echo "$PERCENT_GOOD*$AMOUNT/100" | bc)

htmlecho() {
	echo "$1" >> index.html
}
rm index.html

htmlecho "<html><body>" > index.html
htmlecho "<h2>Statistics for reproducible builds</h2>"
htmlecho "<p>Results were obtaining by <a href=\"$JENKINS_URL/view/reproducible\">several jobs running on jenkins.debian.net</a>. This page is updated after each job run.</p>"
htmlecho "<p>$COUNT_TOTAL packages attempted to build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently. Out of these, $PERCENT_GOOD% were successful, so quite wildly guessing this roughy means about $GUESS_GOOD packages should be build reproducibly! Yay! :-)</p>"
htmlecho "<p>$COUNT_BAD packages ($PERCENT_BAD% of $COUNT_TOTAL) failed to built reproducibly: <code>"
for PKG in $BAD ; do
	VERSION=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT version FROM source_packages WHERE name = \"$PKG\"")
	# remove epoch
	VERSION=$(echo $VERSION | cut -d ":" -f2)
	htmlecho "<a href=\"$JENKINS_URL/userContent/diffp/${PKG}_${VERSION}.diffp.log\">$PKG </a> "
done
htmlecho "</code></p>"
htmlecho
htmlecho "<p>$COUNT_UGLY packages failed to build from source: <code>${UGLY}</code></p>"
if [ $COUNT_SOURCELESS -gt 0 ] ; then
	htmlecho "<p>$COUNT_SOURCELESS packages which don't exist in sid and need investigation: <code>$SOURCELESS</code></p>"
fi
htmlecho "<p>$COUNT_GOOD packages ($PERCENT_GOOD% of $COUNT_TOTAL) successfully built reproducibly: <code>${GOOD}</code></p>"
htmlecho "<hr><p>Packages which failed to build reproducibly, sorted by Maintainers: and Uploaders: fields."
htmlecho "<pre>$(echo $BAD | dd-list -i) </pre></p>"
htmlecho "<hr><p><font size='-1'><a href=\"$JENKINS_URL/userContent/diffp.html\">Static URL for this page.</a> Last modified: $(date)</font>"
htmlecho "</p></body></html>"

# job output
html2text index.html
cp index.html /var/lib/jenkins/userContent/diffp.html
