#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh
 
# overwrite defaults as we need this order here
ARCHS="amd64 armhf"

VIEW=repositories
PAGE=index_${VIEW}.html
SOURCES=$(mktemp --tmpdir=$TEMPDIR repo-comp-XXXXXXXXX)
PACKAGES=$(mktemp --tmpdir=$TEMPDIR repo-comp-XXXXXXXXX)
TMPFILE=$(mktemp --tmpdir=$TEMPDIR repo-comp-XXXXXXXXX)
TABLE_TODO=$(mktemp --tmpdir=$TEMPDIR repo-comp-XXXXXXXXX)
TABLE_DONE=$(mktemp --tmpdir=$TEMPDIR repo-comp-XXXXXXXXX)

MODIFIED_IN_SID=0
MODIFIED_IN_EXP=0
BINNMUS_NEEDED=0

write_row() {
        echo "$1" >> $ROW
}

ARCH="amd64"
SUITE="unstable"
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Comparison between the reproducible builds apt repository and regular Debian suites"
write_page "<p>These source packages are different from unstable in our apt repository on alioth. They are available for <a href=\"https://wiki.debian.org/ReproducibleBuilds/ExperimentalToolchain#Usage_example\">testing using these sources.lists</a> entries:<pre>"
write_page "deb http://reproducible.alioth.debian.org/debian/ ./"
write_page "deb-src http://reproducible.alioth.debian.org/debian/ ./"
write_page "</pre></p>"
write_page "<p><table><tr><th>package</th><th>git repo</th><th>PTS link</th><th>usertagged bug</th><th>old versions in our repo<br />(needed for reproducing old builds)</th><th>version in our repo<br />(available binary packages per architecture)</th><th>version in 'testing'</th><th>version in 'unstable'</th><th>version in 'experimental'</th></tr>"

curl http://reproducible.alioth.debian.org/debian/Sources > $SOURCES
curl http://reproducible.alioth.debian.org/debian/Packages > $PACKAGES
SOURCEPKGS=$(grep-dctrl -n -s Package -r -FPackage . $SOURCES | sort -u)
for PKG in $SOURCEPKGS ; do
	echo "Processing $PKG..."
	if [ "${PKG:0:3}" = "lib" ] ; then
		PREFIX=${PKG:0:4}
	else
		PREFIX=${PKG:0:1}
	fi
	VERSIONS=$(grep-dctrl -n -s version -S $PKG $SOURCES|sort -u)
	CRUFT=""
	BET=""
	OBSOLETE_IN_SID=false
	OBSOLETE_IN_TESTING=false
	OBSOLETE_IN_EXP=false
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
	SID=$(rmadison -s unstable $PKG | egrep -v '^(debian|new):' | cut -d "|" -f2|xargs echo)
	for VERSION in ${VERSIONS} ; do
		if [ "${VERSION}" != "$BET" ] ; then
			CRUFT="$CRUFT ${VERSION}"
		fi
	done
	TESTING=$(rmadison -s testing $PKG | egrep -v '^(debian|new):' | cut -d "|" -f2|xargs echo)
	EXPERIMENTAL=$(rmadison -s experimental $PKG | egrep -v '^(debian|new):' | cut -d "|" -f2|xargs echo)
	#
	# format output
	#
	CSID=""
	CTEST=""
	CEXP=""
	if [ ! -z "$TESTING" ] ; then
		for i in $TESTING ; do
			if dpkg --compare-versions "$i" gt "$BET" ; then
				CTEST="$CTEST<span class=\"green\">$i</span><br />"
				OBSOLETE_IN_TESTING=true
				OBSOLETE_IN_SID=true
				OBSOLETE_IN_EXP=true
			else
				CTEST="$CTEST$i<br />"
			fi
		done
	fi
	if [ ! -z "$EXPERIMENTAL" ] ; then
		for i in $EXPERIMENTAL ; do
			if dpkg --compare-versions "$i" gt "$BET" ; then
				CEXP="$CEXP<a href=\"https://tracker.debian.org/media/packages/$PREFIX/$PKG/changelog-$i\">$i</a><br />"
				OBSOLETE_IN_EXP=true
		else
				CEXP="$CEXP$i<br />"
			fi
		done
	fi
	for i in $SID ; do
		if dpkg --compare-versions "$i" gt "$BET" ; then
			CSID="$CSID<a href=\"https://tracker.debian.org/media/packages/$PREFIX/$PKG/changelog-$i\">$i</a><br />"
			if [ ! -z "$BET" ] ; then
				CRUFT="$BET $CRUFT"
				BET=""
				OBSOLETE_IN_SID=true
				OBSOLETE_IN_EXP=true
			fi
		else
			CSID="$CSID$i<br />"
		fi
	done
	CBINARIES=""
	if [ ! -z "$BET" ] ; then
		ONLYALL=true
		for ARCH in all ${ARCHS} ; do
			i="$(grep-dctrl -n -s Package \( -X -FPackage $PKG --or -X -FSource $PKG \) --and -FVersion $BET --and -FArchitecture $ARCH $PACKAGES|sort -u|xargs -r echo)"
			if [ "$ARCH" != "all" ] && [ ! -z "$i" ] ; then
				ONLYALL=false
			fi
			echo "$ARCH: $i"
		done
		for ARCH in all ${ARCHS} ; do
			i="$(grep-dctrl -n -s Package \( -X -FPackage $PKG --or -X -FSource $PKG \) --and -FVersion $BET --and -FArchitecture $ARCH $PACKAGES|sort -u|xargs -r echo)"
			if [ ! -z "$i" ] ; then
				i="$ARCH: $i"
			elif [ -z "$i" ] && [ "$ARCH" != "all" ] && ! $ONLYALL ; then
				i="<span class=\"red\">no binaries for $ARCH</span>"
				let "BINNMUS_NEEDED+=1"
			fi
			CBINARIES="$CBINARIES<br />$i"
		done
		BET="<span class=\"green\">$BET</span>"
		ROW=$TABLE_TODO
	else
		BET="&nbsp;"
		ROW=$TABLE_DONE
	fi
	if [ ! -z "$CRUFT" ] ; then
		CRUFT="$(echo $CRUFT|sed 's# #<br />#g')"
	fi
	#
	# write output
	#
	write_row "<tr><td><pre>src:$PKG</pre></td>"
	write_row " <td>"
	case $PKG in
		strip-nondeterminism|debbindiff|diffoscope)
			URL="http://anonscm.debian.org/cgit/reproducible/$PKG.git" ;;
		*)
			URL="http://anonscm.debian.org/cgit/reproducible/$PKG.git/?h=pu/reproducible_builds" ;;
	esac
	curl $URL > $TMPFILE
	if [ "$(grep "'error'>No repositories found" $TMPFILE 2>/dev/null)" ] ; then
		write_row "$URL<br /><span class=\"red\">(no git repository found)</span>"
	elif [ "$(grep "'error'>Invalid branch" $TMPFILE 2>/dev/null)" ] ; then
		URL="http://anonscm.debian.org/cgit/reproducible/$PKG.git/?h=merged/reproducible_builds"
		curl $URL > $TMPFILE
		if [ "$(grep "'error'>Invalid branch" $TMPFILE 2>/dev/null)" ] ; then
			if ! $OBSOLETE_IN_SID ; then
				write_row "<a href=\"$URL\">$PKG.git</a><br /><span class=\"purple\">non-standard branch</span>"
			else
				write_row "<a href=\"$URL\">$PKG.git</a><br /><span class=\"green\">non-standard branch</span> (but that is ok, our package aint't used in unstable)"
			fi
		else
			write_row "<a href=\"$URL\">$PKG.git</a>"
			write_row "<br />(<span class=\"green\">merged</span>"
			if $OBSOLETE_IN_TESTING ; then
				write_row "and available in testing and unstable)"
			elif $OBSOLETE_IN_SID ; then
				write_row "and available in unstable)"
			elif $OBSOLETE_IN_EXP ; then
				write_row "and available in experimental)"
			fi
		fi
	else
		write_row "<a href=\"$URL\">$PKG.git</a>"
		if [ "$PKG" != "strip-nondeterminism" ] && [ "$PKG" != "diffoscope" ] ; then
			if $OBSOLETE_IN_TESTING && $OBSOLETE_IN_SID && $OBSOLETE_IN_EXP ; then
				write_row "<br />(unused?"
				write_row "<br /><span class=\"purple\">Then the branch should probably renamed.</span>"
			elif $OBSOLETE_IN_SID && $OBSOLETE_IN_EXP ; then
				write_row "<br />(only used in testing, fixed in sid,"
				write_row "<br /><span class=\"purple\">branch probably either should be renamed to <em>merged/reproducible_builds</em> or a new upload to our repo is needed?</span>)"
			elif $OBSOLETE_IN_EXP ; then
				write_row "<br />(only used in testing and unstable, fixed in experimental)"
			fi
		elif ( [ "$PKG" = "strip-nondeterminism" ] || [ "$PKG" = "diffoscope" ] ) && $OBSOLETE_IN_SID ; then
			write_row "<br />(this repo is always used)"
		fi
	fi
	if ! $OBSOLETE_IN_SID ; then
		let "MODIFIED_IN_SID+=1"
	fi
	if ! $OBSOLETE_IN_EXP ; then
		let "MODIFIED_IN_EXP+=1"
	fi
	write_row " </td>"
	write_row " <td><a href=\"https://tracker.debian.org/pkg/$PKG\">PTS</a></td>"
	URL="https://bugs.debian.org/cgi-bin/pkgreport.cgi?src=$PKG&users=reproducible-builds@lists.alioth.debian.org&archive=both"
	for TAG in $USERTAGS ; do
		URL="$URL&tag=$TAG"
	 done
	write_row " <td><a href=\"$URL\">bugs</a></td>"
	write_row " <td>$CRUFT</td>"
	write_row " <td>$BET $CBINARIES</td>"
	write_row " <td>$CTEST</td>"
	write_row " <td>$CSID</td>"
	write_row " <td>$CEXP</td>"
	write_row "</tr>"
done
cat $TABLE_TODO >> $PAGE
write_page "</table></p>"
write_page "<p><table><tr><th>package (obsolete in our repo)</th><th>git repo</th><th>PTS link</th><th>usertagged bug</th><th>old versions in our repo<br />(needed for reproducing old builds)</th><th>version in our repo<br />(available binary packages per architecture)</th><th>version in 'testing'</th><th>version in 'unstable'</th><th>version in 'experimental'</th></tr>"
cat $TABLE_DONE >> $PAGE
write_page "</table></p>"
write_page_footer
publish_page
echo "$MODIFIED_IN_SID" > /srv/reproducible-results/modified_in_sid.txt
echo "$MODIFIED_IN_EXP" > /srv/reproducible-results/modified_in_exp.txt
echo "$BINNMUS_NEEDED" > /srv/reproducible-results/binnmus_needed.txt

# cleanup
rm $SOURCES $PACKAGES $TMPFILE
rm $TABLE_TODO $TABLE_DONE

