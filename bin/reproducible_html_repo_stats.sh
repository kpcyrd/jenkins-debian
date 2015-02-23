#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set +x
init_html

VIEW=repo_stats
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
TMPFILE=$(mktemp)
TMPSCRIPT=$(mktemp)
echo "cat /var/lib/apt/lists/reproducible.alioth.debian.org_debian_._Packages" > $TMPSCRIPT
sudo pbuilder --execute --basetgz /var/cache/pbuilder/base-reproducible.tgz $TMPSCRIPT > $TMPFILE
grep -v ^I:\  $TMPFILE > $TMPSCRIPT
mv $TMPSCRIPT $TMPFILE

write_page "<p>The source packages are different from sid in our toolchain. They are available in an apt repository on alioth which is accessable with these sources.lists entries:<pre>"
write_page "deb http://reproducible.alioth.debian.org/debian/ ./"
write_page "deb-src http://reproducible.alioth.debian.org/debian/ ./"
write_page "</pre></p>"
write_page "<p><table><tr><th>source package</th><th>version(s)</th></tr>"
SOURCES=$(grep-dctrl -n -s source -FArchitecture amd64 -o -FArchitecture all $TMPFILE | sort -u)
for PKG in $SOURCES ; do
	write_page "<tr><td>$PKG</td><td>"
	VERSIONS=$(grep-dctrl -n -s version -S $PKG $TMPFILE|sort -u)
	BET=""
	for VERSION in ${VERSIONS} ; do
		if [ "$BET" = "" ] ; then
			BET=${VERSION}
			continue
		elif dpkg --compare-versions "$BET" lt "${VERSION}"  ; then
			BET=${VERSION}
		fi
	done
	write_page "<em>$BET</em>"
	CRUFT=""
	WARN=false
	for VERSION in ${VERSIONS} ; do
		if [ "${VERSION}" != "$BET" ] ; then
			if [ ! -z "$CRUFT" ] ; then
				WARN=true
			fi
			$CRUFT="$CRUFT ${VERSION}"
		fi
	done
	if $WARN ; then
		echo "Warning: more than one version of $PKG available in our repo, please clean up."
		write_page "<br />cruft: $CRUFT"
	fi
	write_page "</td></tr>"
done
write_page "</table></p>"
rm $TMPFILE
write_page_footer
publish_page

