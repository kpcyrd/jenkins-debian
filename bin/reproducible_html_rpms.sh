#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

RPMBASE=$BASE/rpms
RELEASE="$1"
ARCH="$2"
#
# analyse results to create the webpage
#
echo "$(date -u) - starting to analyse build results."
HTML_FTBFS=$(mktemp)
HTML_FTBR=$(mktemp)
HTML_DEPWAIT=$(mktemp)
HTML_404=$(mktemp)
HTML_GOOD=$(mktemp)
HTML_UNKNOWN=$(mktemp)
HTML_BUFFER=$(mktemp)
HTML_TARGET=""
HTML_RPM_STATS=$(mktemp)

echo "$(date -u) - starting to analyse build results for '$RELEASE' ($ARCH)."
TOTAL=187 # FIXME: calculate this like $(cat ${ARCHLINUX_PKGS}_$RELEASE | sed -s "s# #\n#g" | wc -l)
TESTED=0
NR_FTBFS=0
NR_FTBR=0
NR_DEPWAIT=0
NR_404=0
NR_GOOD=0
NR_UNKNOWN=0
for PKG in $(find $RPMBASE/$RELEASE/$ARCH/* -maxdepth 1 -type d -exec basename {} \;|sort -u) ; do
	if [ -z "$(cd $RPMBASE/$RELEASE/$ARCH/$PKG/ ; ls)" ] ; then
		# directory exists but is empty: package is building…
		echo "$(date -u ) - ignoring $PKG from '$RELEASE' ($ARCH) which is building right now…"
		continue
	fi
	let TESTED+=1
	echo "     <tr>" >> $HTML_BUFFER
	echo "      <td>$PKG</td>" >> $HTML_BUFFER
	echo "      <td>" >> $HTML_BUFFER
	if [ -z "$(cd $RPMBASE/$RELEASE/$ARCH/$PKG/ ; ls *.rpm.html 2>/dev/null)" ] ; then
		if [ ! -z "$(grep '==> ERROR: Could not resolve all dependencies' $RPMBASE/$RELEASE/$ARCH/$PKG/build1.log)" ] ; then
			HTML_TARGET=$HTML_DEPWAIT
			let NR_DEPWAIT+=1
			echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies" >> $HTML_BUFFER
		elif [ ! -z "$(egrep '==> ERROR: Failure while downloading' $RPMBASE/$RELEASE/$ARCH/$PKG/build1.log)" ] ; then
			HTML_TARGET=$HTML_404
			let NR_404+=1
			echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> failed to download source" >> $HTML_BUFFER
		elif [ ! -z "$(egrep '==> ERROR: One or more files did not pass the validity check' $RPMBASE/$RELEASE/$ARCH/$PKG/build1.log)" ] ; then
			HTML_TARGET=$HTML_FTBFS
			let NR_FTBFS+=1
			echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to verify source" >> $HTML_BUFFER
		else
			echo "       probably failed to build from source, please investigate" >> $HTML_BUFFER
			HTML_TARGET=$HTML_UNKNOWN
			let NR_UNKNOWN+=1
			# or is it reproducible???
		fi
	else
		HTML_TARGET=$HTML_FTBR
		let NR_FTBR+=1
		for ARTIFACT in $(cd $RPMBASE/$RELEASE/$ARCH/$PKG/ ; ls *.rpm.html) ; do
			echo "       <img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> <a href=\"/rpms/$RELEASE/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible<br />" >> $HTML_BUFFER
		done
	fi
	echo "      </td>" >> $HTML_BUFFER
	echo "      <td>$(LANG=C TZ=UTC ls --full-time $RPMBASE/$RELEASE/$ARCH/$PKG/build1.log | cut -d ' ' -f6 )</td>" >> $HTML_BUFFER
	for LOG in build1.log build2.log ; do
		if [ -f $RPMBASE/$RELEASE/$ARCH/$PKG/$LOG ] ; then
			echo "      <td><a href=\"/rpms/$RELEASE/$PKG/$LOG\">$LOG</a></td>" >> $HTML_BUFFER
		else
			echo "      <td>&nbsp;</td>" >> $HTML_BUFFER
		fi
	done
	echo "     </tr>" >> $HTML_BUFFER
	cat $HTML_BUFFER >> $HTML_TARGET
	rm $HTML_BUFFER > /dev/null
done
# prepare stats per repository
PERCENT_TOTAL=$(echo "scale=1 ; ($TESTED*100/$TOTAL)" | bc)
if [ $(echo $PERCENT_TOTAL/1|bc) -lt 98 ] ; then
	NR_TESTED="$TESTED <span style=\"font-size:0.8em;\">($PERCENT_TOTAL% of $TOTAL tested)</span>"
else
	NR_TESTED=$TESTED
fi
echo "     <tr>" >> $HTML_RPM_STATS
echo "      <td>$RELEASE ($ARCH)</td><td>$NR_TESTED</td>" >> $HTML_RPM_STATS
for i in $NR_GOOD $NR_FTBR $NR_FTBFS $NR_DEPWAIT $NR_404 $NR_UNKNOWN ; do
	PERCENT_i=$(echo "scale=1 ; ($i*100/$TOTAL)" | bc)
	if [ "$PERCENT_i" != "0" ] ; then
		echo "      <td>$i ($PERCENT_i%)</td>" >> $HTML_RPM_STATS
	else
		echo "      <td>$i</td>" >> $HTML_RPM_STATS
	fi
done
echo "     </tr>" >> $HTML_RPM_STATS

#
# write out the actual webpage
#
DATE=$(date -u +'%Y-%m-%d')
cd $RPMBASE
PAGE=$RELEASE.html
echo "$(date -u) - starting to build $PAGE"
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <title>Repoducible $RELEASE ($ARCH) ?!</title>
    <link rel='stylesheet' href='global.css' type='text/css' media='all' />
  </head>
  <body>
    <div id="archnavbar">
	    <div id="logo"></div>
    </div>
    <div class="content">
      <h1>Reproducible $RELEASE ($ARCH) ?!</h1>
      <div class="page-content">

EOF
write_page_intro "$RELEASE"
write_explaination_table "$RELEASE"
write_page "    <table><tr><th>release (architecture)</th><th>all sources packages</th><th>reproducible packages</th><th>unreproducible packages</th><th>packages failing to build</th><th>packages in depwait state</th><th>packages 404</th><th>unknown state</th></tr>"
cat $HTML_RPM_STATS >> $PAGE
rm $HTML_RPM_STATS > /dev/null
write_page "    </table>"
write_page "    <table><tr><th>source package</th><th>test result</th><th>test date</th><th>1st build log</th><th>2nd build log</th></tr>"
for i in $HTML_UNKNOWN $HTML_FTBFS $HTML_DEPWAIT $HTML_404 $HTML_FTBR $HTML_GOOD ; do
	cat $i >> $PAGE
	rm $i > /dev/null
done
write_page "    </table>"
write_page "</div></div>"
write_page_footer "$RELEASE"
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/rpms/$PAGE"
