#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#              © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2
#
# included by all reproducible_*.sh scripts
#
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ -f $PACKAGES_DB ] && [ -f $INIT ] ; then
	if [ -f ${PACKAGES_DB}.lock ] ; then
		for i in $(seq 0 200) ; do
			sleep 15
			echo "sleeping 15s, $PACKAGES_DB is locked."
			if [ ! -f ${PACKAGES_DB}.lock ] ; then
				break
			fi
		done
		if [ -f ${PACKAGES_DB}.lock ] ; then
			echo "${PACKAGES_DB}.lock still exist, exiting."
			exit 1
		fi
	fi
elif [ ! -f ${PACKAGES_DB} ] ; then
	echo "Warning: $PACKAGES_DB doesn't exist, creating it now."
		/srv/jenkins/bin/reproducible_db_maintenance.py
	# 60 seconds timeout when trying to get a lock
	cat > $INIT <<-EOF
.timeout 60000
EOF
fi

# common variables
REPRODUCIBLE_URL=https://reproducible.debian.net
# shop trailing slash
JENKINS_URL=${JENKINS_URL:0:-1}

# suites being tested
SUITES="testing unstable experimental"
# arches being tested
ARCHES="amd64"
# number of cores to be used
NUM_CPU=$(grep -c '^processor' /proc/cpuinfo)

# existing usertags
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness buildinfo cpu signatures environment umask"

# we only need them for html creation but we cannot declare them in a function
declare -A SPOKENTARGET

BASE="/var/lib/jenkins/userContent/reproducible"
mkdir -p "$BASE"

# to hold reproducible temporary files/directories without polluting /tmp
TEMPDIR="/tmp/reproducible"
mkdir -p "$TEMPDIR"

# create subdirs for suites
for i in $SUITES ; do
	mkdir -p "$BASE/$i"
done

# known package sets
META_PKGSET[1]="essential"
META_PKGSET[2]="required"
META_PKGSET[3]="build-essential"
META_PKGSET[4]="build-essential-depends"
META_PKGSET[5]="popcon_top1337-installed-sources"
META_PKGSET[6]="key_packages"
META_PKGSET[7]="installed_on_debian.org"
META_PKGSET[8]="had_a_DSA"
META_PKGSET[9]="gnome"
META_PKGSET[10]="gnome_build-depends"
META_PKGSET[11]="kde"
META_PKGSET[12]="kde_build-depends"
META_PKGSET[13]="xfce"
META_PKGSET[14]="xfce_build-depends"
META_PKGSET[15]="tails"
META_PKGSET[16]="tails_build-depends"
META_PKGSET[17]="grml"
META_PKGSET[18]="grml_build-depends"
META_PKGSET[19]="maint_pkg-perl-maintainers"
META_PKGSET[20]="maint_pkg-java-maintainers"
META_PKGSET[21]="maint_pkg-haskell-maintainers"
META_PKGSET[22]="maint_pkg-ruby-extras-maintainers"
META_PKGSET[23]="maint_pkg-golang-maintainers"
META_PKGSET[24]="maint_pkg-php-pear"
META_PKGSET[25]="maint_pkg-javascript-devel"
META_PKGSET[26]="maint_debian-boot"
META_PKGSET[27]="maint_debian-ocaml"

schedule_packages() {
	LC_USER="$REQUESTER" \
	LOCAL_CALL="true" \
	/srv/jenkins/bin/reproducible_remote_scheduler.py \
		--message "$REASON" \
		--no-notify \
		--suite "$UITE" \
		$@
}

write_page() {
	echo "$1" >> $PAGE
}

set_icon() {
	# icons taken from tango-icon-theme (0.8.90-5)
	# licenced under http://creativecommons.org/licenses/publicdomain/
	STATE_TARGET_NAME="$1"
	case "$1" in
		reproducible)		ICON=weather-clear.png
					;;
		unreproducible|FTBR)	ICON=weather-showers-scattered.png
					;;
		FTBFS)			ICON=weather-storm.png
					;;
		404)			ICON=weather-severe-alert.png
					;;
		not_for_us|"not for us")	ICON=weather-few-clouds-night.png
					STATE_TARGET_NAME="not_for_us"
					;;
		blacklisted)		ICON=error.png
					;;
		*)			ICON=""
	esac
}

write_icon() {
	# ICON and STATE_TARGET_NAME are set by set_icon()
	write_page "<a href=\"/$SUITE/$ARCH/index_${STATE_TARGET_NAME}.html\" target=\"_parent\"><img src=\"/userContent/static/$ICON\" alt=\"${STATE_TARGET_NAME} icon\" /></a>"
}

write_page_header() {
	rm -f $PAGE
	MAINVIEW="stats"
	ALLSTATES="reproducible FTBR FTBFS 404 not_for_us blacklisted"
	ALLVIEWS="issues notes no_notes scheduled last_24h last_48h all_abc notify dd-list pkg_sets suite_stats repositories stats"
	GLOBALVIEWS="issues scheduled notify repositories stats"
	SUITEVIEWS="dd-list suite_stats"
	SPOKENTARGET["issues"]="issues"
	SPOKENTARGET["notes"]="packages with notes"
	SPOKENTARGET["no_notes"]="packages without notes"
	SPOKENTARGET["scheduled"]="currently scheduled"
	SPOKENTARGET["last_24h"]="packages tested in the last 24h"
	SPOKENTARGET["last_48h"]="packages tested in the last 48h"
	SPOKENTARGET["all_abc"]="all tested packages (sorted alphabetically)"
	SPOKENTARGET["notify"]="⚑"
	SPOKENTARGET["dd-list"]="maintainers of unreproducible packages"
	SPOKENTARGET["pkg_sets"]="package sets"
	SPOKENTARGET["suite_stats"]="suite: $SUITE"
	SPOKENTARGET["repositories"]="repositories overview"
	SPOKENTARGET["stats"]="reproducible stats"
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<link href=\"/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	if [ "$1" != "$MAINVIEW" ] ; then
		write_page "<body><header><h2>$2</h2>"
	else
		write_page "<body onload=\"selectSearch()\"><header><h2>$2</h2>"
		write_page "<p>These pages are showing the <em>prospects</em> of <a href=\"https://wiki.debian.org/ReproducibleBuilds\" target=\"_blank\">reproducible builds of Debian packages</a>."
		write_page " The results shown were obtained from <a href=\"$JENKINS_URL/view/reproducible\">several jobs</a> running on"
		write_page " <a href=\"$JENKINS_URL/userContent/about.html#_reproducible_builds_jobs\">jenkins.debian.net</a>."
		write_page " Thanks to <a href=\"https://www.profitbricks.co.uk\">Profitbricks</a> for donating the virtual machine this is running on!</p>"
	fi
	if [ "$1" = "dd-list" ] || [ "$1" = "stats" ] ; then
		write_page "<p>Join <code>#debian-reproducible</code> on OFTC"
		write_page "   or <a href="mailto:reproducible-builds@lists.alioth.debian.org">send us an email</a>"
		write_page "   to get support for making sure your packages build reproducibly too. Also, we care about free software in general, so if you are an upstream developer or working on another distribution, we'd love to hear from you! Just now we've started to programatically test <a href=\"/coreboot/\">coreboot</a> and <a href=\"/openwrt/\">OpenWrt</a>!"
		write_page "</p>"
	fi
	write_page "<ul><li>Have a look at:</li>"
	for MY_STATE in $ALLSTATES ; do
		set_icon $MY_STATE
		write_page "<li>"
		write_icon
		write_page "</li>"
	done
	for TARGET in $ALLVIEWS ; do
		if [ "$TARGET" = "pkg_sets" ] && [ "$SUITE" = "experimental" ] ; then
			# no pkg_sets are tested in experimental
			continue
		fi
		SPOKEN_TARGET=${SPOKENTARGET[$TARGET]}
		BASEURL="/$SUITE/$ARCH"
		local i
		for i in $GLOBALVIEWS ; do
			if [ "$TARGET" = "$i" ] ; then
				BASEURL=""
			fi
		done
		for i in ${SUITEVIEWS} ; do
			if [ "$TARGET" = "$i" ] ; then
				BASEURL="/$SUITE"
			fi
		done
		if [ "$TARGET" = "suite_stats" ] ; then
			for i in $SUITES ; do
				write_page "<li><a href=\"/$i\">suite: $i</a></li>"
			done
		elif [ "$TARGET" = "notify" ] ; then
			write_page "<li><a href=\"$BASEURL/index_${TARGET}.html\" title=\"notify icon\">${SPOKEN_TARGET}</a></li>"
		else
			write_page "<li><a href=\"$BASEURL/index_${TARGET}.html\">${SPOKEN_TARGET}</a></li>"
		fi
	done
	write_page "<li><a href=\"https://wiki.debian.org/ReproducibleBuilds\" target=\"_blank\">wiki</a></li>"
	write_page "</ul>"
	if [ "$1" = "$MAINVIEW" ] ; then
		write_page "<form onsubmit=\"location.href='https://reproducible.debian.net/' + document.getElementById('SrcPkg').value; return false;\">"
		write_page "https://reproducible.debian.net/<input type=\"text\" id=\"SrcPkg\" />"
		write_page "<input type=\"submit\" value=\"submit source package name\" />"
	fi
	write_page "</header>"
}

write_page_footer() {
	write_page "<hr/><p style=\"font-size:0.9em;\">There is more information <a href=\"$JENKINS_URL/userContent/about.html\">about jenkins.debian.net</a> and about <a href=\"https://wiki.debian.org/ReproducibleBuilds\"> reproducible builds of Debian</a> available elsewhere. Last update: $(date +'%Y-%m-%d %H:%M %Z'). Copyright 2014-2015 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a> and others, GPL2 licensed. The weather icons are public domain and have been taken from the <a href="http://tango.freedesktop.org/Tango_Icon_Library" target="_blank">Tango Icon Library</a>."
	if [ "$1" = "coreboot" ] ; then
		write_page "The <a href=\"http://www.coreboot.org\">Coreboot</a> logo is Copyright © 2008 by Konsult Stuge and coresystems GmbH and can be freely used to refer to the Coreboot project."
	fi
	write_page "</p></body></html>"
}

write_page_meta_sign() {
	write_page "<p style=\"font-size:0.9em;\">A package name displayed with a bold font is an indication that this package has a note. Visited packages are linked in green, those which have not been visited are linked in blue.</br>"
	write_page "A <code><span class=\"bug\">&#35;</span></code> sign after the name of a package indicates that a bug is filed against it. Likewise, a <code><span class=\"bug-patch\">&#43;</span></code> sign indicates there is a patch available. <code><span class=\"bug-done\">&#35;</span></code> indicates a closed bug. In cases of several bugs, the symbol is repeated.</p>"
}

write_explaination_table() {
	write_page "<p style=\"clear:both;\">"
	write_page "<table class=\"main\" id=\"variation\"><tr><th>variation</th><th>first build</th><th>second build</th></tr>"
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>hostname</td><td>$(hostname)</td><td>i-capture-the-hostname</td></tr>"
		write_page "<tr><td>domainname</td><td>$(hostname -d)</td><td>i-capture-the-domainname</td></tr>"
	else
		write_page "<tr><td>hostname</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>domainname</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
	fi
	export CAPTURE_ENVIRONMENT="I capture the environment"
	write_page "<tr><td>env CAPTURE_ENVIRONMENT</td><td><em>not set</em></td><td>CAPTURE_ENVIRONMENT=\"I capture the environment\"</td></tr>"
	write_page "<tr><td>env TZ</td><td>TZ=\"/usr/share/zoneinfo/Etc/GMT+12\"</td><td>TZ=\"/usr/share/zoneinfo/Etc/GMT-14\"</td></tr>"
	write_page "<tr><td>env LANG</td><td>LANG=\"en_GB.UTF-8\"</td><td>LANG=\"fr_CH.UTF-8\"</td></tr>"
	write_page "<tr><td>env LC_ALL</td><td><em>unset</em></td><td>LC_ALL=\"fr_CH.UTF-8\"</td></tr>"
	write_page "<tr><td>env PATH</td><td>PATH=\"/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:\"</td><td>PATH=\"/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path\"</td></tr>"
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>env BUILDUSERID</td><td>BUILDUSERID=\"1111\"</td><td>BUILDUSERID=\"2222\"</td></tr>"
		write_page "<tr><td>env BUILDUSERNAME</td><td>BUILDUSERNAME=\"pbuilder1\"</td><td>BUILDUSERNAME=\"pbuilder2\"</td></tr>"
		write_page "<tr><td>env USER</td><td>USER=\"pbuilder1\"</td><td>USER=\"pbuilder2\"</td></tr>"
		write_page "<tr><td>uid</td><td>uid=1111</td><td>uid=2222</td></tr>"
		write_page "<tr><td>gid</td><td>gid=1111</td><td>gid=2222</td></tr>"
		write_page "<tr><td>env DEB_BUILD_OPTIONS</td><td>DEB_BUILD_OPTIONS=\"parallel=$NUM_CPU\"</td><td>DEB_BUILD_OPTIONS=\"parallel=$(echo $NUM_CPU-1|bc)\"<br />(using a different number of cores is on the agenda)</td></tr>"
		write_page "<tr><td>UTS namespace</td><td><em>shared with the host</em></td><td><em>modified using</em> /usr/bin/unshare --uts</td></tr>"
	else
		write_page "<tr><td>env USER</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>uid</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>gid</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>UTS namespace</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
	fi
	write_page "<tr><td>kernel version, modified using /usr/bin/linux64 --uname-2.6</td><td>$(uname -sr)</td><td>$(/usr/bin/linux64 --uname-2.6 uname -sr)</td></tr>"
	write_page "<tr><td>umask</td><td>0022<td>0002</td><tr>"
	write_page "<tr><td>CPU type</td><td>$(cat /proc/cpuinfo|grep 'model name'|head -1|cut -d ":" -f2-)</td><td>same for both builds (currently, work in progress)</td></tr>"
	write_page "<tr><td>year, month, date</td><td>today ($DATE)</td><td>same for both builds (currently, work in progress)</td></tr>"
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>hour, minute</td><td>hour is usually the same...</td><td>usually, the minute differs... (currently, work in progress)</td></tr>"
		write_page "<tr><td><em>everything else...</em></td><td colspan=\"2\">is likely the same. So far, this is just about the <em>prospects</em> of <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds of Debian</a> - there will be more variations in the wild.</td></tr>"
	else
		write_page "<tr><td>hour, minute</td><td>hour is usually the same...</td><td>the minute differs... (currently, work in progress)</td></tr>"
		write_page "<tr><td><em>everything else...</em></td><td colspan=\"2\">is likely the same. There will be more variations in the wild.</td></tr>"
	fi
	write_page "</table></p>"
}

publish_page() {
	if [ "$1" = "" ] ; then
		TARGET=$PAGE
	else
		TARGET=$1/$PAGE
	fi
	cp $PAGE $BASE/$TARGET
	rm $PAGE
	echo "Enjoy $REPRODUCIBLE_URL/$TARGET"
}

link_packages() {
	set +x
        local i
	for (( i=1; i<$#+1; i=i+400 )) ; do
		local string='['
		local delimiter=''
		local j
		for (( j=0; j<400; j++)) ; do
			local item=$(( $j+$i ))
			if (( $item < $#+1 )) ; then
				string+="${delimiter}\"${!item}\""
				delimiter=','
			fi
		done
		string+=']'
		cd /srv/jenkins/bin
		DATA=" $(python3 -c "from reproducible_common import link_packages; \
				print(link_packages(${string}, '$SUITE', '$ARCH'))" 2> /dev/null)"
		cd - > /dev/null
		write_page "$DATA"
	done
	if "$DEBUG" ; then set -x ; fi
}

gen_packages_html() {
	local suite="$1"
	shift
	CWD=$(pwd)
	cd /srv/jenkins/bin
	local i
	for (( i=1; i<$#+1; i=i+100 )) ; do
		local string='['
		local delimiter=''
		local j
		for (( j=0; j<100; j++)) ; do
			local item=$(( $j+$i ))
			if (( $item < $#+1 )) ; then
				string+="${delimiter}\"${!item}\""
				delimiter=','
			fi
		done
		string+=']'
		python3 -c "from reproducible_html_packages import gen_packages_html; gen_packages_html(${string}, suite=\"${suite}\", no_clean=True)" || echo "Warning: cannot update html pages for ${string} in ${suite}"
	done
	cd "$CWD"
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

print_out_duration() {
	local HOUR=$(echo "$DURATION/3600"|bc)
	local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date) - total duration: ${HOUR}h ${MIN}m ${SEC}s." | tee -a ${RBUILDLOG}
}

irc_message() {
	local MESSAGE="$@"
	kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE" || true # don't fail the whole job
}

