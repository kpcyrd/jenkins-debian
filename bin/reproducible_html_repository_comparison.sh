#!/bin/bash

# Copyright 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh
 
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

custom_curl() {
	echo -n "$(date -u) - downloading $1 to $2 - "
	curl -s $1 > $2
	local SIZE=$(ls -la $2 |cut -d " " -f5)
	echo "$SIZE bytes."
}

ARCH="amd64"
SUITE="unstable"
echo "$(date -u) - starting to write $PAGE page. Downloading Sources and Packages files from our repository."
write_page_header $VIEW "Comparison between the reproducible builds apt repository and regular Debian suites"
write_page "<p>These source packages (and their binaries packages) are different from unstable in our apt repository on alioth. They are available for <a href=\"https://wiki.debian.org/ReproducibleBuilds/ExperimentalToolchain#Usage_example\">testing using these sources.lists</a> entries:<pre>"
write_page "deb http://reproducible.alioth.debian.org/debian/ ./"
write_page "deb-src http://reproducible.alioth.debian.org/debian/ ./"
write_page "</pre></p>"

custom_curl http://reproducible.alioth.debian.org/debian/Sources $SOURCES
custom_curl http://reproducible.alioth.debian.org/debian/Packages $PACKAGES
SOURCEPKGS=$(grep-dctrl -n -s Package -r -FPackage . $SOURCES | sort -u)
echo

for PKG in $SOURCEPKGS ; do
	echo "$(date -u) - Processing $PKG..."
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
			echo " $ARCH: $i"
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
	GIT="$PKG.git"
	case $PKG in
		debbindiff)
			URL="https://anonscm.debian.org/git/reproducible/diffoscope.git"
			GIT="diffoscope.git" ;;
		strip-nondeterminism|diffoscope|disorderfs)
			URL="https://anonscm.debian.org/git/reproducible/$GIT" ;;
		*)
			URL="https://anonscm.debian.org/git/reproducible/$GIT/?h=pu/reproducible_builds" ;;
	esac
	custom_curl $URL $TMPFILE
	if [ "$(grep "'error'>No repositories found" $TMPFILE 2>/dev/null)" ] ; then
		write_row "<span class=\"red\">no git repository found:</span><br />$URL"
	elif [ "$(grep "'error'>Invalid branch" $TMPFILE 2>/dev/null)" ] ; then
		URL="https://anonscm.debian.org/git/reproducible/$GIT/?h=merged/reproducible_builds"
		custom_curl $URL $TMPFILE
		if [ "$(grep "'error'>Invalid branch" $TMPFILE 2>/dev/null)" ] ; then
			if ! $OBSOLETE_IN_SID ; then
				write_row "<a href=\"$URL\">$GIT</a><br /><span class=\"purple\">non-standard branch</span>"
			else
				write_row "<a href=\"$URL\">$GIT</a><br /><span class=\"green\">non-standard branch</span> (but that is ok, our package ain't used in unstable)"
			fi
		else
			write_row "<a href=\"$URL\">$GIT</a>"
			MERGEINFO=""
			if $OBSOLETE_IN_TESTING ; then
				MERGEINFO=" and available in testing and unstable"
			elif $OBSOLETE_IN_SID ; then
				MERGEINFO=" and available in unstable"
			elif $OBSOLETE_IN_EXP ; then
				MERGEINFO=" and available in experimental"
			fi
			write_row "<br />(<span class=\"green\">merged</span>$MERGEINFO)"
		fi
	else
		write_row "<a href=\"$URL\">$GIT</a>"
		if [ "$PKG" != "strip-nondeterminism" ] && [ "$PKG" != "diffoscope" ] && [ "$PKG" != "debbindiff" ] && [ "$PKG" != "disorderfs" ] ; then
			if $OBSOLETE_IN_TESTING && $OBSOLETE_IN_SID && $OBSOLETE_IN_EXP ; then
				write_row "<br />(unused?"
				write_row "<br /><span class=\"purple\">Then the branch should probably renamed.</span>)"
			elif $OBSOLETE_IN_SID && $OBSOLETE_IN_EXP ; then
				write_row "<br />(only used in testing, fixed in sid,"
				write_row "<br /><span class=\"purple\">branch probably either should be renamed to <em>merged/reproducible_builds</em> or a new upload to our repo is needed?</span>)"
			elif $OBSOLETE_IN_EXP ; then
				write_row "<br />(only used in testing and unstable, fixed in experimental)"
			fi
		elif [ "$PKG" = "disorderfs" ] ; then
			write_row "<br />(only used to modify the build environment in the 2nd build)"
		elif [ "$PKG" = "debbindiff" ] && $OBSOLETE_IN_SID ; then
			write_row "<br />(debbindiff has been renamed to diffoscope)"
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
	echo "$(date -u) - Package $PKG done."
	echo
done
if [ -s $TABLE_TODO ] ; then
	write_page "<p><table><tr><th class=\"center\">package</th><th class=\"center\">git repo</th><th class=\"center\">PTS link</th><th class=\"center\">usertagged bug(s)</th><th class=\"center\">old versions in our repo<br />(needed for reproducing old builds)</th><th class=\"center\">version in our repo<br />(available binary packages per architecture)</th><th class=\"center\">version in 'testing'</th><th class=\"center\">version in 'unstable'</th><th class=\"center\">version in 'experimental'</th></tr>"
	cat $TABLE_TODO >> $PAGE
	write_page "</table></p>"
else
	write_page "<p>Congratulations! There are no modified packages in our repository compared to unstable. (Yes, that means our repository is obsolete now.)"
fi
if [ -s $TABLE_DONE ] ; then
	write_page "<p><table><tr><th class=\"center\">obsoleted package,<br />version in sid higher than in our repo</th><th class=\"center\">git repo</th><th class=\"center\">PTS link</th><th class=\"center\">usertagged bug(s)</th><th class=\"center\">old version(s) in our repo<br />(needed for reproducing old builds)</th><th class=\"center\">version in our repo<br />(available binary packages per architecture)</th><th class=\"center\">version in 'testing'</th><th class=\"center\">version in 'unstable'</th><th class=\"center\">version in 'experimental'</th></tr>"
	cat $TABLE_DONE >> $PAGE
	write_page "</table></p>"
fi
write_page_footer
publish_page debian
echo "$MODIFIED_IN_SID" > /srv/reproducible-results/modified_in_sid.txt
echo "$MODIFIED_IN_EXP" > /srv/reproducible-results/modified_in_exp.txt
echo "$BINNMUS_NEEDED" > /srv/reproducible-results/binnmus_needed.txt

# cleanup
rm $SOURCES $PACKAGES $TMPFILE
rm $TABLE_TODO $TABLE_DONE

