#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
#                2015 anthraxx <levente@leventepolyak.net>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

ARCHBASE=$BASE/archlinux
#
# analyse results to create the webpage
#
echo "$(date -u) - starting to analyse build results."
MEMBERS_FTBFS="0 1 2 3 4"
MEMBERS_DEPWAIT="0 1"
MEMBERS_404="0 1 2 3 4 5 6 7"
for i in $MEMBERS_FTBFS ; do
	HTML_FTBFS[$i]=$(mktemp)
done
for i in $MEMBERS_DEPWAIT ; do
	HTML_DEPWAIT[$i]=$(mktemp -t rhtml-archlinux-XXXXXXXX)
done
for i in $MEMBERS_404 ; do
	HTML_404[$i]=$(mktemp -t rhtml-archlinux-XXXXXXXX)
done
HTML_FTBR=$(mktemp -t rhtml-archlinux-XXXXXXXX)
HTML_GOOD=$(mktemp -t rhtml-archlinux-XXXXXXXX)
HTML_UNKNOWN=$(mktemp -t rhtml-archlinux-XXXXXXXX)
HTML_BUFFER=$(mktemp -t rhtml-archlinux-XXXXXXXX)
HTML_TARGET=""
HTML_REPOSTATS=$(mktemp -t rhtml-archlinux-XXXXXXXX)
SIZE=""
for REPOSITORY in $ARCHLINUX_REPOS ; do
	echo "$(date -u) - starting to analyse build results for '$REPOSITORY'."
	TOTAL=$(cat ${ARCHLINUX_PKGS}_$REPOSITORY | sed -s "s# #\n#g" | wc -l)
	TESTED=0
	NR_FTBFS=0
	NR_FTBR=0
	NR_DEPWAIT=0
	NR_404=0
	NR_GOOD=0
	NR_UNKNOWN=0
	for PKG in $(find $ARCHBASE/$REPOSITORY/* -maxdepth 1 -type d -exec basename {} \;|sort -u -f) ; do
		ARCHLINUX_PKG_PATH=$ARCHBASE/$REPOSITORY/$PKG
		if [ -z "$(cd $ARCHLINUX_PKG_PATH ; ls)" ] ; then
			# directory exists but is empty: package is building…
			echo "$(date -u ) - ignoring $PKG from '$REPOSITORY' which is building in $ARCHLINUX_PKG_PATH right now…"
			continue
		fi
		let TESTED+=1
		echo "     <tr>" >> $HTML_BUFFER
		echo "      <td>$REPOSITORY</td>" >> $HTML_BUFFER
		echo "      <td>$PKG</td>" >> $HTML_BUFFER
		echo "      <td>" >> $HTML_BUFFER
		if [ -z "$(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
			if [ ! -z "$(egrep '^error: failed to prepare transaction \(conflicting dependencies\)' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_DEPWAIT[0]}
				let NR_DEPWAIT+=1
				echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies as there are conflicts" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '(==> ERROR: Could not resolve all dependencies|==> ERROR: .pacman. failed to install missing dependencies)' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_DEPWAIT[1]}
				let NR_DEPWAIT+=1
				echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '(==> ERROR: Failure while downloading|==> ERROR: One or more PGP signatures could not be verified)' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_404[0]}
				EXTRA_REASON=""
				let NR_404+=1
				if [ ! -z "$(grep 'FAILED (unknown public key' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[6]}
					EXTRA_REASON="to verify source with PGP due to unknown public key"
				elif [ ! -z "$(grep 'The requested URL returned error: 404' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[3]}
					EXTRA_REASON="with 404 - file not found"
				elif [ ! -z "$(grep 'The requested URL returned error: 403' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[2]}
					EXTRA_REASON="with 403 - forbidden"
				elif [ ! -z "$(grep 'The requested URL returned error: 500' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[4]}
					EXTRA_REASON="with 500 - internal server error"
				elif [ ! -z "$(grep 'The requested URL returned error: 503' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[5]}
					EXTRA_REASON="with 503 - service unavailable"
				elif [ ! -z "$(egrep '==> ERROR: One or more PGP signatures could not be verified' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[7]}
					EXTRA_REASON="to verify source with PGP signatures"
				elif [ ! -z "$(grep 'SSL certificate problem: unable to get local issuer certificate' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
					HTML_TARGET=${HTML_404[1]}
					EXTRA_REASON="with SSL certificate problem"
				fi
				echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> download failed $EXTRA_REASON" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: One or more files did not pass the validity check' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_FTBFS[0]}
				let NR_FTBFS+=1
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to verify source" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '(==> ERROR: install file .* does not exist or is not a regular file|==> ERROR: The download program wget is not installed)' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_FTBFS[1]}
				let NR_FTBFS+=1
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, requirements not met" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: A failure occurred in check' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_FTBFS[2]}
				let NR_FTBFS+=1
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build while running tests" >> $HTML_BUFFER
			elif [ ! -z "$(egrep '==> ERROR: A failure occurred in (build|package)' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_FTBFS[3]}
				let NR_FTBFS+=1
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build" >> $HTML_BUFFER
			elif [ ! -z "$(egrep 'makepkg was killed by timeout after' $ARCHLINUX_PKG_PATH/build1.log)" ] ; then
				HTML_TARGET=${HTML_FTBFS[4]}
				let NR_FTBFS+=1
				echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, killed by timeout" >> $HTML_BUFFER
			else
				echo "       probably failed to build from source, please investigate" >> $HTML_BUFFER
				HTML_TARGET=$HTML_UNKNOWN
				let NR_UNKNOWN+=1
				# or is it reproducible???
			fi
		else
			HTML_TARGET=$HTML_GOOD
			for ARTIFACT in $(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html) ; do
				if [ ! -z "$(grep 'build reproducible in our test framework' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
					let NR_GOOD+=1
					echo "       <img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is reproducible<br />" >> $HTML_BUFFER
				else
					HTML_TARGET=$HTML_FTBR
					let NR_FTBR+=1
					echo "       <img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible<br />" >> $HTML_BUFFER
				fi
			done
		fi
		echo "      </td>" >> $HTML_BUFFER
		echo "      <td>$(LANG=C TZ=UTC ls --full-time $ARCHLINUX_PKG_PATH/build1.log | cut -d ' ' -f6 )</td>" >> $HTML_BUFFER
		for LOG in build1.log build2.log ; do
			if [ -f $ARCHLINUX_PKG_PATH/$LOG ] ; then
				get_filesize $ARCHLINUX_PKG_PATH/$LOG
				echo "      <td><a href=\"/archlinux/$REPOSITORY/$PKG/$LOG\">$LOG</a> ($SIZE)</td>" >> $HTML_BUFFER
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
	if [ $(echo $PERCENT_TOTAL/1|bc) -lt 99 ] ; then
		NR_TESTED="$TESTED <span style=\"font-size:0.8em;\">($PERCENT_TOTAL% of $TOTAL tested)</span>"
	else
		NR_TESTED=$TESTED
	fi
	echo "     <tr>" >> $HTML_REPOSTATS
	echo "      <td>$REPOSITORY</td><td>$NR_TESTED</td>" >> $HTML_REPOSTATS
	for i in $NR_GOOD $NR_FTBR $NR_FTBFS $NR_DEPWAIT $NR_404 $NR_UNKNOWN ; do
		PERCENT_i=$(echo "scale=1 ; ($i*100/$TESTED)" | bc)
		if [ "$PERCENT_i" != "0" ] ; then
			echo "      <td>$i ($PERCENT_i%)</td>" >> $HTML_REPOSTATS
		else
			echo "      <td>$i</td>" >> $HTML_REPOSTATS
		fi
	done
	echo "     </tr>" >> $HTML_REPOSTATS
done
#
# write out the actual webpage
#
DATE=$(date -u +'%Y-%m-%d')
cd $ARCHBASE
PAGE=archlinux.html
echo "$(date -u) - starting to build $PAGE"
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <title>Reproducible Arch Linux ?!</title>
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
write_variation_table 'Arch Linux'
write_page "    <table><tr><th>repository</th><th>all source packages</th><th>reproducible packages</th><th>unreproducible packages</th><th>packages failing to build</th><th>packages in depwait state</th><th>packages download failures</th><th>unknown state</th></tr>"
cat $HTML_REPOSTATS >> $PAGE
rm $HTML_REPOSTATS > /dev/null
write_page "    </table>"
write_page "    <table><tr><th>repository</th><th>source package</th><th>test result</th><th>test date</th><th>1st build log</th><th>2nd build log</th></tr>"
for i in $HTML_UNKNOWN $(for j in $MEMBERS_404 ; do echo ${HTML_404[$j]} ; done) $(for j in $MEMBERS_DEPWAIT ; do echo ${HTML_DEPWAIT[$j]} ; done) $(for j in $MEMBERS_FTBFS ; do echo ${HTML_FTBFS[$j]} ; done) $HTML_FTBR $HTML_GOOD ; do
	cat $i >> $PAGE
	rm $i > /dev/null
done
write_page "    </table>"
write_page "</div></div>"
write_page_footer 'Arch Linux'
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"

# vim: set sw=0 noet :
