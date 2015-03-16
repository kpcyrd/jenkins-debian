#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

SUITE="unstable"	# for links in page
ARCH="amd64"		# same

VIEW=repo_stats
PAGE=index_${VIEW}.html
TMPFILE=$(mktemp)
TMP2FILE=$(mktemp)

echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Comparison between the reproducible builds apt repository and regular Debian suites"
write_page "<p>These source packages are different from unstable in our apt repository on alioth. They are available for <a href=\"https://wiki.debian.org/ReproducibleBuilds/ExperimentalToolchain#Usage_example\">testing using these sources.lists</a> entries:<pre>"
write_page "deb http://reproducible.alioth.debian.org/debian/ ./"
write_page "deb-src http://reproducible.alioth.debian.org/debian/ ./"
write_page "</pre></p>"
write_page "<p><table><tr><th>source package</th><th>old versions in our repo<br />(needed for reproducing old builds)</th><th>version in our repo</th><th>version in 'testing'</th><th>version in 'unstable'</th><th>version in 'experimental'</th></tr>"

curl http://reproducible.alioth.debian.org/debian/Sources > $TMPFILE
SOURCES=$(grep-dctrl -n -s Package -r -FPackage . $TMPFILE | sort -u)
for PKG in $SOURCES ; do
	echo "Processing $PKG..."
	if [ "${PKG:0:3}" = "lib" ] ; then
		PREFIX=${PKG:0:4}
	else
		PREFIX=${PKG:0:1}
	fi
	VERSIONS=$(grep-dctrl -n -s version -S $PKG $TMPFILE|sort -u)
	CRUFT=""
	BET=""
	OBSOLETE=false
	#
	# gather versions of a package
	#
	for VERSION in ${VERSIONS} ; do
		if [ "$BET" = "" ] ; then
			BET=${VERSION}
			continue
		elif dpkg --compare-versions "$BET" lt "${VERSION}"  ; then
			BET=${VERSION}
		fi
	done
	SID=$(rmadison -s unstable $PKG | cut -d "|" -f2|xargs echo)
	for VERSION in ${VERSIONS} ; do
		if [ "${VERSION}" != "$BET" ] ; then
			CRUFT="$CRUFT ${VERSION}"
		fi
	done
	TESTING=$(rmadison -s testing $PKG | cut -d "|" -f2|xargs echo)
	EXPERIMENTAL=$(rmadison -s experimental $PKG | cut -d "|" -f2|xargs echo)
	#
	# format output
	#
	CSID=""
	CTEST=""
	CEXP=""
	for i in $SID ; do
		if dpkg --compare-versions "$i" gt "$BET" ; then
			CSID="$CSID<a href=\"https://tracker.debian.org/media/packages/$PREFIX/$PKG/changelog-$i\">$i</a><br />"
			if [ ! -z "$BET" ] ; then
				CRUFT="$BET $CRUFT"
				BET=""
				OBSOLETE=true
			fi
		else
			CSID="$CSID$i<br />"
		fi
	done
	if [ ! -z "$TESTING" ] ; then
		for i in $TESTING ; do
			if dpkg --compare-versions "$i" gt "$BET" ; then
				CTEST="$CTEST<span class=\"green\">$i</span><br />"
			else
				CTEST="$CTEST$i<br />"
			fi
		done
	fi
	if [ ! -z "$EXPERIMENTAL" ] ; then
		for i in $EXPERIMENTAL ; do
			if dpkg --compare-versions "$i" gt "$BET" ; then
				CEXP="$CEXP<a href=\"https://tracker.debian.org/media/packages/$PREFIX/$PKG/changelog-$i\">$i</a><br />"
			else
				CEXP="$CEXP$i<br />"
			fi
		done
	fi
	if [ ! -z "$BET" ] ; then
		BET="<span class=\"green\">$BET</span>"
	else
		BET="&nbsp;"
	fi
	if [ ! -z "$CRUFT" ] ; then
		CRUFT="$(echo $CRUFT|sed 's# #<br />#g')"
	fi
	#
	# write output
	#
	write_page "<tr><td>"
	URL="http://anonscm.debian.org/cgit/reproducible/$PKG.git/?h=pu/reproducible_builds"
	curl $URL > $TMP2FILE
	if [ "$(grep "'error'>No repositories found" $TMP2FILE 2>/dev/null)" ] ; then
		write_page "$PKG<br /><span class=\"red\">(no git repository)</span>"
	elif [ "$(grep "'error'>Invalid branch" $TMP2FILE 2>/dev/null)" ] ; then
		URL="http://anonscm.debian.org/cgit/reproducible/$PKG.git/?h=merged/reproducible_builds"
		curl $URL > $TMP2FILE
		if [ "$(grep "'error'>Invalid branch" $TMP2FILE 2>/dev/null)" ] ; then
			write_page "<a href=\"$URL\" target=\"_blank\">$PKG</a><br /><span class=\"purple\">non-standard branch</span>"
			if $OBSOLETE ; then
				write_page " (probably ok)"
			fi
		else
			write_page "<a href=\"$URL\" target=\"_blank\">$PKG</a>"
			write_page "<br />(<span class=\"green\">merged</span> and at least available in unstable)"
		fi
	else
		write_page "<a href=\"$URL\" target=\"_blank\">$PKG</a>"
		if $OBSOLETE ; then
			write_page "<br />(unused?)"
		fi
	fi
	write_page " </td>"
	write_page " <td>$CRUFT</td>"
	write_page " <td>$BET</td>"
	write_page " <td>$CTEST</td>"
	write_page " <td>$CSID</td>"
	write_page " <td>$CEXP</td>"
	write_page "</tr>"
done
write_page "</table></p>"
rm $TMPFILE $TMP2FILE
write_page_footer
publish_page

