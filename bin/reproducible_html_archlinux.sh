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
for REPOSITORY in $ARCHLINUX_REPOS ; do
	for PKG in $(find $ARCHBASE/$REPOSITORY/* -maxdepth 1 -type d -exec basename {} \;) ; do
		if [ -z "$(cd $ARCHBASE/$REPOSITORY/$PKG/ ; ls)" ] ; then
			# directory exists but is empty: package is building…
			echo "$(date -u ) - ignoring $PKG from '$REPOSITORY' which is building right now…"
			continue
		fi
		write_page "     <tr>"
		write_page "      <td>$REPOSITORY</td>"
		write_page "      <td>$PKG</td>"
		write_page "      <td>"
		if [ -z "$(cd $ARCHBASE/$REPOSITORY/$PKG/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
			if [ ! -z "$(grep '==> ERROR: Could not resolve all dependencies' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies"
			elif [ ! -z "$(egrep '==> ERROR: .pacman. failed to install missing dependencies.' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> failed to install dependencies"
			elif [ ! -z "$(egrep '==> ERROR: A failure occurred in (build|package)' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build from source"
			elif [ ! -z "$(egrep '==> ERROR: A failure occurred in check' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build from source, while running tests"
			elif [ ! -z "$(egrep '==> ERROR: Failure while downloading' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> failed to download source"
			elif [ ! -z "$(egrep '==> ERROR: One or more files did not pass the validity check' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to verify source"
			elif [ ! -z "$(egrep 'makepkg was killed by timeout after 4h' $ARCHBASE/$REPOSITORY/$PKG/build1.log)" ] ; then
				write_page "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, killed by timeout after 4h"
			else
				write_page "       probably failed to build from source, please investigate"
				# or is it reproducible???
			fi
		else
			for ARTIFACT in $(cd $ARCHBASE/$REPOSITORY/$PKG/ ; ls *.pkg.tar.xz.html) ; do
				write_page "       <img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible<br />"
			done
		fi
		write_page "      </td>"
		write_page "      <td>$(LANG=C TZ=UTC ls --full-time $ARCHBASE/$REPOSITORY/$PKG/build1.log | cut -d ' ' -f6 )</td>"
		for LOG in build1.log build2.log ; do
			if [ -f $ARCHBASE/$REPOSITORY/$PKG/$LOG ] ; then
				write_page "      <td><a href=\"/archlinux/$REPOSITORY/$PKG/$LOG\">$LOG</a></td>"
			else
				write_page "      <td>&nbsp;</td>"
			fi
		done
		write_page "     </tr>"
	done
done
write_page "    </table>"
write_page "</div></div>"
write_page_footer 'Arch Linux'
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"
