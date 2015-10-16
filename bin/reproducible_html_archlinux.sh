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
ARCHBASE=$BASE/archlinux
cd $ARCHBASE
PAGE=archlinux.html
echo "$(date -u) - starting to build $PAGE"
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <title>Repoducible Archlinux ?</title>
  </head>
  <body>
  <p>This is work in progress and brand new…</p>
EOF
write_page "<table><tr><th>source package</th><th>test date</th><th>1st build log</th><th>2nd build log</th><th>diffoscope output for binary packages</th></tr>"
for PKG in $(find $ARCHBASE/* -maxdepth 1 -type d -exec basename {} \;) ; do
	write_page " <tr>"
	write_page "  <td>$PKG</td>"
	write_page "  <td>$(ls $ARCHBASE/$PKG -dl|cut -d " " -f6-8)</td>"
	for LOG in build1.log build2.log ; do
		if [ -f $ARCHBASE/$PKG/$LOG ] ; then
			write_page "  <td><a href=\"/archlinux/$PKG/$LOG\">$LOG</a></td>"
		else
			write_page "  <td>&nbsp;</td>"
		fi
	done
	if [ -z "$(cd $ARCHBASE/$PKG/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
		write_page "  <td>failed to build from source</td>"
	else
		write_page "  <td>"
		for ARTIFACT in $(cd $ARCHBASE/$PKG/ ; ls *.pkg.tar.xz.html) ; do
			write_page "   <a href=\"/archlinux/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a><br />"
		done
		write_page "  </td>"
	fi
	write_page " </tr>"
done
write_page "</table>"
write_page_footer Archlinux
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"
