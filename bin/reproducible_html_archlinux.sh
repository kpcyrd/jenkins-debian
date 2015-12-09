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
write_page "    <table><tr><th>source package</th><th>test result</th><th>test date</th><th>1st build log</th><th>2nd build log</th></tr>"
for PKG in $(find $ARCHBASE/* -maxdepth 1 -type d -exec basename {} \;) ; do
	write_page "     <tr>"
	write_page "      <td>$PKG</td>"
	write_page "      <td>"
	if [ -z "$(cd $ARCHBASE/$PKG/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
		if [ ! -z "$(grep '==> ERROR: Could not resolve all dependencies' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       could not resolve dependencies"
		elif [ ! -z "$(egrep '==> ERROR: .pacman. failed to install missing dependencies.' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       failed to install dependencies"
		elif [ ! -z "$(egrep '==> ERROR: A failure occurred in (build|package)' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       failed to build from source"
		elif [ ! -z "$(egrep '==> ERROR: A failure occurred in check' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       failed to build from source, while running tests"
		elif [ ! -z "$(egrep '==> ERROR: Failure while downloading' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       failed to download source"
		elif [ ! -z "$(egrep '==> ERROR: One or more files did not pass the validity check' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       failed to verify source"
		elif [ ! -z "$(egrep 'makepkg was killed by timeout after 4h' $ARCHBASE/$PKG/build1.log)" ] ; then
			write_page "       failed to build, killed by timeout after 4h"
		else
			write_page "       probably failed to build from source, please investigate"
		fi
	else
		for ARTIFACT in $(cd $ARCHBASE/$PKG/ ; ls *.pkg.tar.xz.html) ; do
			write_page "       <a href=\"/archlinux/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a>is unreproducible<br />"
		done
	fi
	write_page "      </td>"
	write_page "      <td>$(ls -dl $ARCHBASE/$PKG/build1.log|cut -d " " -f6-8)</td>"
	for LOG in build1.log build2.log ; do
		if [ -f $ARCHBASE/$PKG/$LOG ] ; then
			write_page "      <td><a href=\"/archlinux/$PKG/$LOG\">$LOG</a></td>"
		else
			write_page "      <td>&nbsp;</td>"
		fi
	done
	write_page "     </tr>"
done
write_page "    </table>"
write_page "</div></div>"
write_page_footer 'Arch Linux'
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"
