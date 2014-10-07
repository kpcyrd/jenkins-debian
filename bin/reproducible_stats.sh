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
BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"blacklisted\" ORDER BY name" | xargs echo)
COUNT_BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"blacklisted\"" | xargs echo)
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
GUESS_GOOD=$(echo "$PERCENT_GOOD*$AMOUNT/100" | bc)
declare -A STAR
declare -A LINKTARGET

write_summary() {
	echo "$1" >> $SUMMARY
	echo "$1" | html2text
}

mkdir -p /var/lib/jenkins/userContent/rb-pkg/
write_pkg_frameset() {
	FRAMESET="/var/lib/jenkins/userContent/rb-pkg/$1.html"
	cat > $FRAMESET <<-EOF
<!DOCTYPE html>
<html>
	<head>
	</head>
	<frameset framespacing="0" rows="42,*" frameborder="0" noresize>
		<frame name="top" src="$1_navigation.html" target="top">
		<frame name="main" src="$2" target="main">
	</frameset>
</html>
EOF
}

init_navi_frame() {
	echo "<!DOCTYPE html><html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />" > $NAVI
	echo "<link href=\"../static/style.css\" type=\"text/css\" rel=\"stylesheet\" /></head>" >> $NAVI
	echo "<body><table><tr><td><font size=+1>$1</font> " >> $NAVI
	echo "($2) " >> $NAVI
	echo "<font size=-1>at $3:</font> " >> $NAVI
}

append2navi_frame() {
	echo "$1" >> $NAVI
}

finish_navi_frame() {
	echo "</td><td style=\"text-align:right\"><a href=\"$JENKINS_URL/userContent/reproducible.html\" target=\"_parent\">stats for reproducible builds</a></td></tr></table></body></html>" >> $NAVI
}

process_packages() {
	for PKG in $@ ; do
		RESULT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT build_date,version FROM source_packages WHERE name = \"$PKG\"")
		BUILD_DATE=$(echo $RESULT|cut -d "|" -f1)
		VERSION=$(echo $RESULT|cut -d "|" -f2)
		# remove epoch
		EVERSION=$(echo $VERSION | cut -d ":" -f2)
		if $EXTRA_STAR && [ ! -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo" ] ; then
			STAR[$PKG]="<font color=\"#333333\" size=\"-1\">&beta;</font>" # used to be a star...
		fi
		# only build $PKG pages if they don't exist or are older than $BUILD_DATE
		NAVI="/var/lib/jenkins/userContent/rb-pkg/${PKG}_navigation.html"
		FILE=$(find $(dirname $NAVI) -name $(basename $NAVI) ! -newermt "$BUILD_DATE" 2>/dev/null || true)
		if [ ! -f $NAVI ] || [ "$FILE" != "" ] ; then
			MAINLINK=""
			init_navi_frame "$PKG" "$VERSION" "$BUILD_DATE"
			if [ -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo" ] ; then
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo\" target=\"main\">buildinfo</a> "
				MAINLINK="$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo"
			fi
			if [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html" ] ; then
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html\" target=\"main\">debbindiff</a> "
				MAINLINK="$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html"
			fi
			RBUILD_LOG="rbuild/${PKG}_${EVERSION}.rbuild.log"
			if [ -f "/var/lib/jenkins/userContent/${RBUILD_LOG}" ] ; then
				SIZE=$(du -sh "/var/lib/jenkins/userContent/${RBUILD_LOG}" |cut -f1)
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/${RBUILD_LOG}\" target=\"main\">rbuild ($SIZE)</a> "
				if [ "$MAINLINK" = "" ] ; then
					MAINLINK="$JENKINS_URL/userContent/${RBUILD_LOG}"
				fi
			fi
			append2navi_frame " <a href=\"https://packages.qa.debian.org/${PKG}\" target=\"main\">PTS</a> "
			append2navi_frame " <a href=\"https://bugs.debian.org/src:${PKG}\" target=\"main\">BTS</a> "
			append2navi_frame " <a href=\"https://sources.debian.net/src/${PKG}/\" target=\"main\">sources</a> "
			append2navi_frame " <a href=\"https://sources.debian.net/src/${PKG}/${VERSION}/debian/rules\" target=\"main\">debian/rules</a> "

			finish_navi_frame
			write_pkg_frameset "$PKG" "$MAINLINK"
		fi
		if [ -f "/var/lib/jenkins/userContent/rbuild/${PKG}_${EVERSION}.rbuild.log" ] ; then
			LINKTARGET[$PKG]="<a href=\"$JENKINS_URL/userContent/rb-pkg/$PKG.html\">$PKG</a>${STAR[$PKG]}"
		else
			LINKTARGET[$PKG]="$PKG"
		fi
	done
}

link_packages() {
	for PKG in $@ ; do
		write_summary " ${LINKTARGET[$PKG]} "
	done
}

echo "Processing packages... this will take a while."
EXTRA_STAR=true
process_packages $BAD
EXTRA_STAR=false
process_packages $UGLY $GOOD

echo "Starting to write statistics index page."
echo
SUMMARY=index.html
rm -f $SUMMARY
write_summary "<!DOCTYPE html><html><head>"
write_summary "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
write_summary "<link href=\"static/style.css\" type=\"text/css\" rel=\"stylesheet\" /></head>"
write_summary "<body><header><h2>Statistics for reproducible builds</h2>"
write_summary "<p>This page is updated every three hours. Results are obtained from <a href=\"$JENKINS_URL/view/reproducible\">several build jobs running on jenkins.debian.net</a>. Thanks to <a href=\"https://www.profitbricks.com\">Profitbricks</a> for donating the virtual machine it's running on!</p>"
write_summary "<p>$COUNT_TOTAL packages attempted to build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently. Out of these, $PERCENT_GOOD% were successful, so quite wildly guessing this roughy means about $GUESS_GOOD <a href=\"https://wiki.debian.org/ReproducibleBuilds\">packages should be reproducibly buildable!</a> Join <code>#debian-reproducible</code> on OFTC to get support for making sure your packages build reproducibly too!</p></header>"
write_summary "<p>$COUNT_BAD packages ($PERCENT_BAD% of $COUNT_TOTAL) failed to built reproducibly: <code>"
link_packages $BAD
write_summary "</code></p>"
write_summary "<p><font size=\"-1\">A &beta; sign after a package name indicates that no .buildinfo file was generated.</font></p>"
write_summary
write_summary "<p>$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source: <code>"
link_packages $UGLY
write_summary "</code></p>"
if [ $COUNT_SOURCELESS -gt 0 ] ; then
	write_summary "<p>$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) packages where the source could not be downloaded. <code>$SOURCELESS</code></p>"
fi
if [ $COUNT_NOTFORUS -gt 0 ] ; then
	write_summary "<p>$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any' nor 'all' nor 'amd64' nor 'linux-amd64': <code>$NOTFORUS</code></p>"
fi
if [ $COUNT_BLACKLISTED -gt 0 ] ; then
	write_summary "<p>$COUNT_BLACKLISTED packages are blacklisted and will never be tested here: <code>$BLACKLISTED</code></p>"
fi
write_summary "<p>$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly: <code>"
link_packages $GOOD
write_summary "</code></p>"
write_summary "<hr/><h2>Packages which failed to build reproducibly, sorted by Maintainers: and Uploaders: fields</h2>"
write_summary "<p><pre>$(echo $BAD | dd-list -i) </pre></p>"
write_summary "<hr/><p><font size='-1'><a href=\"$JENKINS_URL/userContent/reproducible.html\">Static URL for this page.</a> Last modified: $(date). Copyright 2014 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a>, GPL-2 licensed. <a href=\"https://jenkins.debian.net/userContent/about.html\">About jenkins.debian.net</a></font>"
write_summary "</p></body></html>"
echo

# job output
cp $SUMMARY /var/lib/jenkins/userContent/reproducible.html
rm $SUMMARY
