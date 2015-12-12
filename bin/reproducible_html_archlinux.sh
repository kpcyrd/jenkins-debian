#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

#
#  create the webpage
#
DATE=$(date -u +'%Y-%m-%d')
ARCHBASE=$BASE/archlinux
cd $ARCHBASE
PAGE=archlinux.html
echo "$(date -u) - starting to build $PAGE"
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <title>Repoducible Arch Linux ?!</title>
    <link rel='stylesheet' href='global.css' type='text/css' media='all' />
  </head>
  <body>
    <div id="archnavbar">
	    <div id="logo"></div>
    </div>
    <div class="content">
      <h1>Reproducible Arch Linux?!</h1>
      <div class="page-content">

EOF
write_page_intro 'Arch Linux'
write_explaination_table 'Arch Linux'
write_page "    <table><tr><th>repository</th><th>source package</th><th>test result</th><th>test date</th><th>1st build log</th><th>2nd build log</th></tr>"
HTML_FTBFS=$(mktemp)
HTML_FTBR=$(mktemp)
HTML_DEPWAIT=$(mktemp)
HTML_404=$(mktemp)
HTML_GOOD=$(mktemp)
HTML_UNKNOWN=$(mktemp)
HTML_BUFFER=$(mktemp)
HTML_TARGET=""
for REPOSITORY in $ARCHLINUX_REPOS ; do
	for PKG in $(find $ARCHBASE/$REPOSITORY/* -maxdepth 1 -type d -exec basename {} \;) ; do
		if [ -z "$(cd $ARCHBASE/$REPOSITORY/$PKG/ ; ls)" ] ; then
			# directory exists but is empty: package is building…
			echo "$(date -u ) - ignoring $PKG from '$REPOSITORY' which is building right now…"
			continue
		fi
		echo "     <tr>" >> $HTML_BUFFER
		echo "      <td>$REPOSITORY</td>" >> $HTML_BUFFER
		echo "      <td>$PKG</td>" >> $HTML_BUFFER
		echo "      <td>" >> $HTML_BUFFER
		if [ -z "$(cd $ARCHBASE/$REPOSITORY/$PKG/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
			if [ ! -z "$(grep '==> ERROR: Could not resolve all dependencies' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_DEPWAIT
				echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: .pacman. failed to install missing dependencies.' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_DEPWAIT
				echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> failed to install dependencies" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: A failure occurred in (build|package)' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_FTBFS
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build from source" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: A failure occurred in check' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_FTBFS
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build from source, while running tests" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: Failure while downloading' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_404
				echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> failed to download source" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: One or more files did not pass the validity check' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_FTBFS
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to verify source" >> $HTML_BUFFER
			elif [ ! -z "$(egrep 'makepkg was killed by timeout after' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				HTML_TARGET=$HTML_FTBFS
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, killed by timeout" >> $HTML_BUFFER
			else
				echo "       probably failed to build from source, please investigate" >> $HTML_BUFFER
				HTML_TARGET=$HTML_UNKNOWN
				# or is it reproducible???
			fi
		else
			HTML_TARGET=$HTML_FTBR
			for ARTIFACT in $(cd $ARCHBASE/$REPOSITORY/$PKG/ ; ls *.pkg.tar.xz.html) ; do
				echo "       <img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible<br />" >> $HTML_BUFFER
			done
		fi
		echo "      </td>" >> $HTML_BUFFER
		echo "      <td>$(LANG=C TZ=UTC ls --full-time $ARCHBASE/$REPOSITORY/$PKG/build1.log | cut -d ' ' -f6 )</td>" >> $HTML_BUFFER
		for LOG in build1.log build2.log ; do
			if [ -f $ARCHBASE/$REPOSITORY/$PKG/$LOG ] ; then
				echo "      <td><a href=\"/archlinux/$REPOSITORY/$PKG/$LOG\">$LOG</a></td>" >> $HTML_BUFFER
			else
				echo "      <td>&nbsp;</td>" >> $HTML_BUFFER
			fi
		done
		echo "     </tr>" >> $HTML_BUFFER
		cat $HTML_BUFFER >> $HTML_TARGET
		rm $HTML_BUFFER > /dev/null
	done
done
for i in $HTML_UNKNOWN $HTML_FTBFS $HTML_DEPWAIT $HTML_404 $HTML_FTBR $HTML_GOOD ; do
	cat $i >> $PAGE
	rm $i > /dev/null
done
write_page "    </table>"
write_page "</div></div>"
write_page_footer 'Arch Linux'
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"
