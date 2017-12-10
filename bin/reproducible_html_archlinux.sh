#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
#                2015 anthraxx <levente@leventepolyak.net>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

#
# analyse results to create the webpage
#
echo "$(date -u) - starting to analyse build results."
DATE=$(date -u +'%Y-%m-%d')
YESTERDAY=$(date '+%Y-%m-%d' -d "-1 day")
MEMBERS_FTBFS="0 1 2 3"
MEMBERS_DEPWAIT="0 1"
MEMBERS_404="0 1 2 3 4 5 6 7 8 9"
MEMBERS_FTBR="0 1 2"
HTML_BUFFER=$(mktemp -t archlinuxrb-html-XXXXXXXX)
HTML_REPOSTATS=$(mktemp -t archlinuxrb-html-XXXXXXXX)
SIZE=""
ARCHLINUX_TOTAL=0
ARCHLINUX_TESTED=0
ARCHLINUX_NR_FTBFS=0
ARCHLINUX_NR_FTBR=0
ARCHLINUX_NR_DEPWAIT=0
ARCHLINUX_NR_404=0
ARCHLINUX_NR_GOOD=0
ARCHLINUX_NR_BLACKLISTED=0
ARCHLINUX_NR_UNKNOWN=0
WIDTH=1920
HEIGHT=960
for REPOSITORY in $ARCHLINUX_REPOS ; do
	echo "$(date -u) - starting to analyse build results for '$REPOSITORY'."
	TOTAL=$(cat ${ARCHLINUX_PKGS}_$REPOSITORY | wc -l)
	TESTED=0
	NR_FTBFS=0
	NR_FTBR=0
	NR_DEPWAIT=0
	NR_404=0
	NR_GOOD=0
	NR_BLACKLISTED=0
	NR_UNKNOWN=0
	for PKG in $(find $ARCHBASE/$REPOSITORY/* -maxdepth 1 -type d -exec basename {} \;|sort -u -f) ; do
		ARCHLINUX_PKG_PATH=$ARCHBASE/$REPOSITORY/$PKG
		if [ -z "$(cd $ARCHLINUX_PKG_PATH ; ls)" ] ; then
			# directory exists but is empty: package is building…
			echo "$(date -u )   - ignoring $PKG from '$REPOSITORY' which is building in $ARCHLINUX_PKG_PATH since $(LANG=C TZ=UTC ls --full-time -d $ARCHLINUX_PKG_PATH | cut -d ':' -f1-2 | cut -d " " -f6-) UTC"
			continue
		fi
		if [ ! -f $ARCHLINUX_PKG_PATH/pkg.state ] ; then
			blacklisted=false
			if [ -f $ARCHLINUX_PKG_PATH/pkg.version ] ; then
				VERSION=$(cat $ARCHLINUX_PKG_PATH/pkg.version)
			elif [ -f $ARCHLINUX_PKG_PATH/build1.version ] ; then
				VERSION=$(cat $ARCHLINUX_PKG_PATH/build1.version)
				if [ -f $ARCHLINUX_PKG_PATH/build2.log ] ; then
					if [ ! -f $ARCHLINUX_PKG_PATH/build2.version ] ; then
						echo "$(date -u )   - $ARCHLINUX_PKG_PATH/build2.version does not exist, so the 2nd build fails. This happens."
					elif ! diff -q $ARCHLINUX_PKG_PATH/build1.version $ARCHLINUX_PKG_PATH/build2.version ; then
						echo "$(date -u )   - $ARCHLINUX_PKG_PATH/build1.version and $ARCHLINUX_PKG_PATH/build2.version differ, this should not happen. Please tell h01ger."
						VERSION="$VERSION or $(cat $ARCHLINUX_PKG_PATH/build2.version)"
					fi
				fi
			elif [ $(ls $ARCHLINUX_PKG_PATH/*.pkg.tar.xz.html 2>/dev/null | wc -l) -eq 1 ] ; then
			# only determine version if there is exactly one artifact...
			# else it's too error prone and in future the version will
			# be determined during build anyway...
				ARTIFACT="$(ls $ARCHLINUX_PKG_PATH/*.pkg.tar.xz.html 2>/dev/null)"
				VERSION=$( basename $ARTIFACT | sed -s "s#$PKG-##" | sed -E -s "s#-(x86_64|any).pkg.tar.xz.html##" )
			else
				for i in $ARCHLINUX_BLACKLISTED ; do
					if [ "$PKG" = "$i" ] ; then
						blacklisted=true
						VERSION="undetermined"
					fi
				done
				if ! $blacklisted && [ -f $ARCHLINUX_PKG_PATH/pkg.needs_build ] ; then
					echo "$(date -u )   - ok, $PKG from '$REPOSITORY' needs build, this should go away by itself."
					continue
				elif ! $blacklisted ; then
					echo "$(date -u )   - cannot determine state of $PKG from '$REPOSITORY', please check $ARCHLINUX_PKG_PATH yourself."
				fi
			fi
			if [ "$VERSION" != "undetermined" ] || $blacklisted ; then
				echo $VERSION > $ARCHLINUX_PKG_PATH/pkg.version
			fi
			echo "     <tr>" >> $HTML_BUFFER
			echo "      <td>$REPOSITORY</td>" >> $HTML_BUFFER
			echo "      <td>$PKG</td>" >> $HTML_BUFFER
			echo "      <td>$VERSION</td>" >> $HTML_BUFFER
			echo "      <td>" >> $HTML_BUFFER
			#
			#
			if [ -z "$(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
				for i in $ARCHLINUX_BLACKLISTED ; do
					if [ "$PKG" = "$i" ] ; then
						blacklisted=true
					fi
				done
				# this horrible if elif elif elif elif...  monster is needed because
				# https://lists.archlinux.org/pipermail/pacman-dev/2017-September/022156.html
			        # has not yet been merged yet...
				if $blacklisted ; then
						echo BLACKLISTED > $ARCHLINUX_PKG_PATH/pkg.state
						echo "       <img src=\"/userContent/static/error.png\" alt=\"blacklisted icon\" /> blacklisted" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '^error: failed to prepare transaction \(conflicting dependencies\)' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					echo DEPWAIT_= > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies as there are conflicts" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '==> ERROR: (Could not resolve all dependencies|.pacman. failed to install missing dependencies)' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					echo DEPWAIT_1 > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '^error: unknown package: ' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					echo 404_0 > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> unknown package" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '==> ERROR: (Failure while downloading|One or more PGP signatures could not be verified|One or more files did not pass the validity check|Integrity checks \(.*\) differ in size from the source array|Failure while branching|Failure while creating working copy)' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					REASON="download failed"
					EXTRA_REASON=""
					echo 404_0 > $ARCHLINUX_PKG_PATH/pkg.state
					if [ ! -z "$(grep 'FAILED (unknown public key' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_6 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="to verify source with PGP due to unknown public key"
					elif [ ! -z "$(grep 'The requested URL returned error: 403' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_2 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="with 403 - forbidden"
					elif [ ! -z "$(grep 'The requested URL returned error: 500' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_4 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="with 500 - internal server error"
					elif [ ! -z "$(grep 'The requested URL returned error: 503' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_5 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="with 503 - service unavailable"
					elif [ ! -z "$(egrep '==> ERROR: One or more PGP signatures could not be verified' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_7 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="to verify source with PGP signatures"
					elif [ ! -z "$(egrep '(SSL certificate problem: unable to get local issuer certificate|^bzr: ERROR: .SSL: CERTIFICATE_VERIFY_FAILED)' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_1 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="with SSL problem"
					elif [ ! -z "$(egrep '==> ERROR: One or more files did not pass the validity check' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_8 > $ARCHLINUX_PKG_PATH/pkg.state
						REASON="downloaded ok but failed to verify source"
					elif [ ! -z "$(egrep '==> ERROR: Integrity checks \(.*\) differ in size from the source array' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_9 > $ARCHLINUX_PKG_PATH/pkg.state
						REASON="Integrity checks differ in size from the source array"
					elif [ ! -z "$(grep 'The requested URL returned error: 404' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
						echo 404_3 > $ARCHLINUX_PKG_PATH/pkg.state
						EXTRA_REASON="with 404 - file not found"
					fi
					echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> $REASON $EXTRA_REASON" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '==> ERROR: (install file .* does not exist or is not a regular file|The download program wget is not installed)' $ARCHLINUX_PKG_PATH/build1.log 2>/dev/null)" ] ; then
					echo FTBFS_0 > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, requirements not met" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '==> ERROR: A failure occurred in check' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					echo FTBFS_1 > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build while running tests" >> $HTML_BUFFER
				elif [ ! -z "$(egrep '==> ERROR: A failure occurred in (build|package|prepare)' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					echo FTBFS_2 > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build" >> $HTML_BUFFER
				elif [ ! -z "$(egrep 'makepkg was killed by timeout after' $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null)" ] ; then
					echo FTBFS_3 > $ARCHLINUX_PKG_PATH/pkg.state
					echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, killed by timeout" >> $HTML_BUFFER
				else
					echo "       probably failed to build from source, please investigate" >> $HTML_BUFFER
					echo UNKNOWN > $ARCHLINUX_PKG_PATH/pkg.state
				fi
			else
				STATE=GOOD
				SOME_GOOD=false
				for ARTIFACT in $(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html) ; do
					if [ ! -z "$(grep 'build reproducible in our test framework' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
						SOME_GOOD=true
						echo "       <img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is reproducible in our current test framework<br />" >> $HTML_BUFFER
					else
						# change $STATE unless we have found .buildinfo differences already...
						if [ "$STATE" != "FTBR_0" ] ; then
							STATE=FTBR_1
						fi
						# this shouldnt happen, but (for now) it does, so lets mark them…
						EXTRA_REASON=""
						if [ ! -z "$(grep 'class="source">.BUILDINFO' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
							STATE=FTBR_0
							EXTRA_REASON=" with variations in .BUILDINFO"
						fi
						echo "       <img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$PKG/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible$EXTRA_REASON<br />" >> $HTML_BUFFER
					fi
				done
				# we only count source packages…
				case $STATE in
					GOOD)		echo GOOD > $ARCHLINUX_PKG_PATH/pkg.state	;;
					FTBR_0)		echo FTBR_0 > $ARCHLINUX_PKG_PATH/pkg.state	;;
					FTBR_1)		if $SOME_GOOD ; then
								echo FTBR_1 > $ARCHLINUX_PKG_PATH/pkg.state
							else
								echo FTBR_2 > $ARCHLINUX_PKG_PATH/pkg.state
							fi
							;;
					*)		;;
				esac
			fi
			echo "      </td>" >> $HTML_BUFFER
			BUILD_DATE="$(LANG=C TZ=UTC ls --full-time $ARCHLINUX_PKG_PATH/build1.log | cut -d ':' -f1-2 | cut -d " " -f6- )"
			if [ ! -z "$BUILD_DATE" ] ; then
				BUILD_DATE="$BUILD_DATE UTC"
			fi
			echo "      <td>$BUILD_DATE" >> $HTML_BUFFER
			DURATION=$(cat $ARCHLINUX_PKG_PATH/pkg.build_duration 2>/dev/null || true)
			if [ -n "$DURATION" ]; then
				HOUR=$(echo "$DURATION/3600"|bc)
				MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
				SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
				BUILD_DURATION="<br />${HOUR}h:${MIN}m:${SEC}s"
			else
				BUILD_DURATION=" "
			fi
			echo "       $BUILD_DURATION</td>" >> $HTML_BUFFER

			echo "      <td>" >> $HTML_BUFFER
			for LOG in build1.log build2.log ; do
				if [ -f $ARCHLINUX_PKG_PATH/$LOG ] ; then
					if [ "$LOG" = "build2.log" ] ; then
						echo "       <br />" >> $HTML_BUFFER
					fi
					get_filesize $ARCHLINUX_PKG_PATH/$LOG
					echo "       <a href=\"/archlinux/$REPOSITORY/$PKG/$LOG\">$LOG</a> ($SIZE)" >> $HTML_BUFFER
				fi
			done
			echo "      </td>" >> $HTML_BUFFER
			echo "     </tr>" >> $HTML_BUFFER
			mv $HTML_BUFFER $ARCHLINUX_PKG_PATH/pkg.html
		fi

	done
	# prepare stats per repository
	set +e
	TESTED=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c ^)
	NR_GOOD=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c GOOD)
	NR_FTBR=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c FTBR)
	NR_FTBFS=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c FTBFS)
	NR_DEPWAIT=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c DEPWAIT)
	NR_404=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c 404)
	NR_BLACKLISTED=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c BLACKLISTED)
	NR_UNKNOWN=$(cat $ARCHBASE/$REPOSITORY/*/pkg.state | grep -c UNKNOWN)
	set -e
	PERCENT_TOTAL=$(echo "scale=1 ; ($TESTED*100/$TOTAL)" | bc)
	if [ $(echo $PERCENT_TOTAL/1|bc) -lt 99 ] ; then
		NR_TESTED="$TESTED <span style=\"font-size:0.8em;\">(tested $PERCENT_TOTAL% of $TOTAL)</span>"
	else
		NR_TESTED=$TESTED
	fi
	echo "     <tr>" >> $HTML_REPOSTATS
	echo "      <td>$REPOSITORY</td><td>$NR_TESTED</td>" >> $HTML_REPOSTATS
	for i in $NR_GOOD $NR_FTBR $NR_FTBFS $NR_DEPWAIT $NR_404 $NR_BLACKLISTED $NR_UNKNOWN ; do
		PERCENT_i=$(echo "scale=1 ; ($i*100/$TESTED)" | bc)
		if [ "$PERCENT_i" != "0" ] || [ "$i" != "0" ] ; then
			echo "      <td>$i ($PERCENT_i%)</td>" >> $HTML_REPOSTATS
		else
			echo "      <td>$i</td>" >> $HTML_REPOSTATS
		fi
	done
	echo "     </tr>" >> $HTML_REPOSTATS
	#
	# write csv file for $REPOSITORY
	#
	if [ ! -f $ARCHBASE/$REPOSITORY.csv ] ; then
		echo '; date, reproducible, unreproducible, ftbfs, depwait, download problems, untested' > $ARCHBASE/$REPOSITORY.csv
	fi
	if ! grep -q $YESTERDAY $ARCHBASE/$REPOSITORY.csv ; then
		let REAL_UNKNOWN=$TOTAL-$NR_GOOD-$NR_FTBR-$NR_FTBFS-$NR_DEPWAIT-$NR_404 || true
		echo $YESTERDAY,$NR_GOOD,$NR_FTBR,$NR_FTBFS,$NR_DEPWAIT,$NR_404,$REAL_UNKNOWN >> $ARCHBASE/$REPOSITORY.csv
	fi
	IMAGE=$ARCHBASE/$REPOSITORY.png
	if [ ! -f $IMAGE ] || [ $ARCHBASE/$REPOSITORY.csv -nt $IMAGE ] ; then
		echo "Updating $IMAGE..."
		/srv/jenkins/bin/make_graph.py $ARCHBASE/$REPOSITORY.csv $IMAGE 6 "Reproducibility status for Arch Linux packages in $REPOSITORY" "Amount (total)" $WIDTH $HEIGHT
	fi
	#
	# prepare ARCHLINUX totals
	#
	set +e
	let ARCHLINUX_TOTAL+=$TOTAL
	let ARCHLINUX_TESTED+=$TESTED
	let ARCHLINUX_NR_FTBFS+=$NR_FTBFS
	let ARCHLINUX_NR_FTBR+=$NR_FTBR
	let ARCHLINUX_NR_DEPWAIT+=$NR_DEPWAIT
	let ARCHLINUX_NR_404+=$NR_404
	let ARCHLINUX_NR_GOOD+=$NR_GOOD
	let ARCHLINUX_NR_BLACKLISTED+=$NR_BLACKLISTED
	let ARCHLINUX_NR_UNKNOWN+=$NR_UNKNOWN
	set -e
done
# prepare stats per repository
ARCHLINUX_PERCENT_TOTAL=$(echo "scale=1 ; ($ARCHLINUX_TESTED*100/$ARCHLINUX_TOTAL)" | bc)
if [ $(echo $ARCHLINUX_PERCENT_TOTAL/1|bc) -lt 99 ] ; then
	NR_TESTED="$ARCHLINUX_TESTED <span style=\"font-size:0.8em;\">(tested $ARCHLINUX_PERCENT_TOTAL% of $ARCHLINUX_TOTAL)</span>"
else
	NR_TESTED=$ARCHLINUX_TESTED
fi
echo "     <tr>" >> $HTML_REPOSTATS
echo "      <td><b>all combined</b></td><td>$NR_TESTED</td>" >> $HTML_REPOSTATS
for i in $ARCHLINUX_NR_GOOD $ARCHLINUX_NR_FTBR $ARCHLINUX_NR_FTBFS $ARCHLINUX_NR_DEPWAIT $ARCHLINUX_NR_404 $ARCHLINUX_NR_BLACKLISTED $ARCHLINUX_NR_UNKNOWN ; do
	PERCENT_i=$(echo "scale=1 ; ($i*100/$ARCHLINUX_TESTED)" | bc)
	if [ "$PERCENT_i" != "0" ] || [ "$i" != "0" ] ; then
		echo "      <td>$i ($PERCENT_i%)</td>" >> $HTML_REPOSTATS
	else
		echo "      <td>$i</td>" >> $HTML_REPOSTATS
	fi
done
echo "     </tr>" >> $HTML_REPOSTATS

#
# write csv file for totals
#
if [ ! -f $ARCHBASE/archlinux.csv ] ; then
	echo '; date, reproducible, unreproducible, ftbfs, depwait, download problems, untested' > $ARCHBASE/archlinux.csv
fi
if ! grep -q $YESTERDAY $ARCHBASE/archlinux.csv ; then
	let ARCHLINUX_REAL_UNKNOWN=$ARCHLINUX_TOTAL-$ARCHLINUX_NR_GOOD-$ARCHLINUX_NR_FTBR-$ARCHLINUX_NR_FTBFS-$ARCHLINUX_NR_DEPWAIT-$ARCHLINUX_NR_404 || true
	echo $YESTERDAY,$ARCHLINUX_NR_GOOD,$ARCHLINUX_NR_FTBR,$ARCHLINUX_NR_FTBFS,$ARCHLINUX_NR_DEPWAIT,$ARCHLINUX_NR_404,$ARCHLINUX_REAL_UNKNOWN >> $ARCHBASE/archlinux.csv
fi
IMAGE=$ARCHBASE/archlinux.png
if [ ! -f $IMAGE ] || [ $ARCHBASE/archlinux.csv -nt $IMAGE ] ; then
	echo "Updating $IMAGE..."
	/srv/jenkins/bin/make_graph.py $ARCHBASE/archlinux.csv $IMAGE 6 "Reproducibility status for all tested Arch Linux packages" "Amount (total)" $WIDTH $HEIGHT
	irc_message archlinux-reproducible "Daily graphs on $REPRODUCIBLE_URL/archlinux/ updated, $(echo "scale=1 ; ($ARCHLINUX_NR_GOOD*100/$ARCHLINUX_TESTED)" | bc)% reproducible packages in our current test framework."
fi

#
# write out the actual webpage
#
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
write_page "    <table><tr><th>repository</th><th>all source packages</th><th>reproducible packages</th><th>unreproducible packages</th><th>packages failing to build</th><th>packages in depwait state</th><th>packages download problems</th><th>blacklisted</th><th>unknown state</th></tr>"
cat $HTML_REPOSTATS >> $PAGE
rm $HTML_REPOSTATS > /dev/null
write_page "    </table>"
# include graphs
write_page '<p style="clear:both;">'
for REPOSITORY in $ARCHLINUX_REPOS ; do
	write_page "<a href=\"/archlinux/$REPOSITORY.png\"><img src=\"/archlinux/$REPOSITORY.png\" class=\"overview\" alt=\"$REPOSITORY stats\"></a>"
done
write_page '</p><p style="clear:both;"><center>'
write_page "<a href=\"/archlinux/archlinux.png\"><img src=\"/archlinux/archlinux.png\" alt=\"total Arch Linux stats\"></a></p>"
# packages table header
write_page "    <table><tr><th>repository</th><th>source package</th><th>version</th><th>test result</th><th>test date<br />test duration</th><th>1st build log<br />2nd build log</th></tr>"
# output all HTML snipplets
for i in UNKNOWN $(for j in $MEMBERS_404 ; do echo 404_$j ; done) BLACKLISTED $(for j in $MEMBERS_DEPWAIT ; do echo DEPWAIT_$j ; done) $(for j in $MEMBERS_FTBFS ; do echo FTBFS_$j ; done) $(for j in $MEMBERS_FTBR ; do echo FTBR_$j ; done) GOOD ; do
	for REPOSITORY in $ARCHLINUX_REPOS ; do
		grep -l $i $REPOSITORY/*/pkg.state | sort -u | sed -s 's#\.state$#.html#g' | xargs -r cat >> $PAGE 2>/dev/null || true
	done
done
write_page "    </table>"
write_page "</div></div>"
write_page_footer 'Arch Linux'
echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"

echo "$(date -u) - Sleeping 5min now to prevent immediate restart of this job…"
sleep 5m

# vim: set sw=0 noet :
