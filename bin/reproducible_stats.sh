#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set +x
PACKAGES_DB=/var/lib/jenkins/reproducible.db
if [ ! -f $PACKAGES_DB ] ; then
	echo "$PACKAGES_DB doesn't exist, no stats possible."
	exit 1
fi 

GOOD=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY name" | xargs echo)
COUNT_GOOD=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
BAD=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY build_date" | xargs echo)
COUNT_BAD=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"unreproducible\"")
UGLY=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY build_date" | xargs echo)
COUNT_UGLY=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"FTBFS\"")
SOURCELESS=$(sqlite3 $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY build_date" | xargs echo)
COUNT_SOURCELESS=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"404\"" | xargs echo)
COUNT_TOTAL=$(sqlite3 $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")

echo
echo "Simple statistics for reproducible builds as tested on jenkins.debian.net so far"
echo 
echo "$COUNT_TOTAL packages attempted to build in total."
echo
echo "$COUNT_GOOD packages successfully built reproducibly: ${GOOD}"
echo
echo "$COUNT_BAD packages failed to built reproducibly: ${BAD}"
echo
echo "$COUNT_UGLY packages failed to build from source: ${UGLY}"
echo "$COUNT_SOURCELESS packages doesn't exist in sid and need investigation: $SOURCELESS"

echo "<html><body><p>Hello World<ul>" > index.html
for PKG in $BAD ; do
	VERSION=$(sqlite3 $PACKAGES_DB "SELECT version FROM source_packages WHERE name = \"$PKG\"")
	echo "<li><a href=https://$JENKINS_URL/userContent/diffp/${PKG}_${VERSION}>diffp output for $PKG</a></li> " >> index.html
done
echo "</ul></p></body></html>" >> index.html


