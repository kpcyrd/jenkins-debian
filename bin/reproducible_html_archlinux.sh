#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Reiner Herrmann <reiner@reiner-h.de>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

#
#  finally create the webpage
#
PAGE=archlinux/archlinux.html
cd $BASE
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <title>Repoducible Archlinux ?</title>
  </head>
  <body>
EOF
cd $BASE/archlinux
write_page "<table><tr><th>source package</th><th>test date</th><th>1st build log</th><th>2nd build log</th><th>diffoscope output for binary packages</th></tr>"
for PKG in $(ls * -d1) ; do
	write_page " <td>$PKG</td>"
	write_page " <td>$(ls $PKG -dl|cut -d " " -f6-8)</td>"
	for LOG in build1.log build2.log ; do
		if [ -f $PKG/$LOG ] ; then
			write_page " <td><a href=\"$LOG\">$LOG</a></td>"
		else
			write_page " <td>&nbsp;</td>"
		fi
	done
	if [ -z "$(ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
		write_page " <td>failed to build from source</td>"
	else
		write_page " <td>"
		for ARTIFACT in *.pkg.tar.xz.html ; do
			write_page "  <a href=\"$ARTIFACT\">${ARTIFACT:0:-5}</a><br />"
		done
		write_page " </td>"
	fi
done

write_page "</table>"
write_page_footer Archlinux
publish_page

