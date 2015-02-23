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
curl http://reproducible.alioth.debian.org/debian/Packages > $TMPFILE

write_page "<p>These source packages are different from sid in our toolchain. They are available in an apt repository on alioth which is accessable with these sources.lists entries:<pre>"
write_page "deb http://reproducible.alioth.debian.org/debian/ ./"
write_page "deb-src http://reproducible.alioth.debian.org/debian/ ./"
write_page "</pre></p>"
write_page "<p><table><tr><th>source package</th><th>version in our repo</th><th>version in sid</th><th>cruft in our repo (if any)</th></tr>"
SOURCES=$(grep-dctrl -n -s source -FArchitecture amd64 -o -FArchitecture all $TMPFILE | sort -u)
for PKG in $SOURCES ; do
	write_page "<tr><td>$PKG</td>"
	VERSIONS=$(grep-dctrl -n -s version -S $PKG $TMPFILE|sort -u)
	CRUFT=""
	WARN=false
	BET=""
	for VERSION in ${VERSIONS} ; do
		if [ "$BET" = "" ] ; then
			BET=${VERSION}
			continue
		elif dpkg --compare-versions "$BET" lt "${VERSION}"  ; then
			BET=${VERSION}
		fi
	done
	write_page "<td>$BET</td>"
	SID=$(rmadison -s sid $PKG | cut -d "|" -f2|xargs echo|sed 's# #<br />#g')
	write_page "<td>$SID</td>"
	for VERSION in ${VERSIONS} ; do
		if [ "${VERSION}" != "$BET" ] ; then
			WARN=true
			CRUFT="$CRUFT ${VERSION}"
		fi
	done
	if $WARN ; then
		echo "Warning: more than one version of $PKG available in our repo, please clean up."
		write_page "<td>$(echo $CRUFT|sed 's# #<br />#g')</td>"
	else
		write_page "<td>&nbsp;</td>"
	fi
	write_page "</tr>"
done
write_page "</table></p>"
rm $TMPFILE
write_page_footer
publish_page

