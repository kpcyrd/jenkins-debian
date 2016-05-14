#!/bin/bash


# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
#              © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2
#
# included by all reproducible_*.sh scripts
#
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
MAINNODE="jenkins" # host which contains reproducible.db
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
elif [ ! -f ${PACKAGES_DB} ] && [ "$HOSTNAME" = "$MAINNODE" ] ; then
	echo "Warning: $PACKAGES_DB doesn't exist, creating it now."
		/srv/jenkins/bin/reproducible_db_maintenance.py
	# 60 seconds timeout when trying to get a lock
	cat > $INIT <<-EOF
.timeout 60000
EOF
fi

# common variables
REPRODUCIBLE_URL=https://tests.reproducible-builds.org
REPRODUCIBLE_DOT_ORG_URL=https://reproducible-builds.org
# shop trailing slash
JENKINS_URL=${JENKINS_URL:0:-1}
DBDSUITE="unstable"

# Debian suites being tested
SUITES="testing unstable experimental"
# Debian architectures being tested
ARCHS="amd64 i386 armhf"

# define Debian build nodes in use
. /srv/jenkins/bin/jenkins_node_definitions.sh

# variables on the nodes we are interested in
BUILD_ENV_VARS="ARCH NUM_CPU CPU_MODEL DATETIME KERNEL" # these also needs to be defined in bin/reproducible_info.sh

# existing usertags in the Debian BTS
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness buildinfo cpu signatures environment umask ftbfs locale"

# common settings for testing Arch Linux
ARCHLINUX_BUILD_NODE=profitbricks-build3-amd64
ARCHLINUX_REPOS="core extra multilib community"
ARCHLINUX_PKGS=/srv/reproducible-results/.archlinux_pkgs

# common settings for testing rpm based distros
RPM_BUILD_NODE=profitbricks-build3-amd64
RPM_PKGS=/srv/reproducible-results/.rpm_pkgs

# number of cores to be used
NUM_CPU=$(grep -c '^processor' /proc/cpuinfo)

# we only this array for html creation but we cannot declare them in a function
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

# table names and image names
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
TABLE[4]=stats_notes
TABLE[5]=stats_issues
TABLE[6]=stats_meta_pkg_state
TABLE[7]=stats_bugs_state
TABLE[8]=stats_bugs_sin_ftbfs
TABLE[9]=stats_bugs_sin_ftbfs_state

# known package sets
META_PKGSET[1]="essential"
META_PKGSET[2]="required"
META_PKGSET[3]="build-essential"
META_PKGSET[4]="build-essential-depends"
META_PKGSET[5]="popcon_top1337-installed-sources"
META_PKGSET[6]="key_packages"
META_PKGSET[7]="installed_on_debian.org"
META_PKGSET[8]="had_a_DSA"
META_PKGSET[9]="cii-census"
META_PKGSET[10]="gnome"
META_PKGSET[11]="gnome_build-depends"
META_PKGSET[12]="kde"
META_PKGSET[13]="kde_build-depends"
META_PKGSET[14]="xfce"
META_PKGSET[15]="xfce_build-depends"
META_PKGSET[16]="tails"
META_PKGSET[17]="tails_build-depends"
META_PKGSET[18]="grml"
META_PKGSET[19]="grml_build-depends"
META_PKGSET[20]="freedombox"
META_PKGSET[21]="freedombox_build-depends"
META_PKGSET[22]="subgraph_OS"
META_PKGSET[23]="subgraph_OS_build-depends"
META_PKGSET[24]="maint_pkg-perl-maintainers"
META_PKGSET[25]="maint_pkg-java-maintainers"
META_PKGSET[26]="maint_pkg-haskell-maintainers"
META_PKGSET[27]="maint_pkg-ruby-extras-maintainers"
META_PKGSET[28]="maint_pkg-golang-maintainers"
META_PKGSET[29]="maint_pkg-php-pear"
META_PKGSET[30]="maint_pkg-javascript-devel"
META_PKGSET[31]="maint_debian-boot"
META_PKGSET[32]="maint_debian-ocaml"
META_PKGSET[33]="maint_debian-x"
META_PKGSET[34]="maint_lua"

# sleep 1-23 secs to randomize start times
delay_start() {
	/bin/sleep $(echo "scale=1 ; $(shuf -i 1-230 -n 1)/10" | bc )
}

schedule_packages() {
	LC_USER="$REQUESTER" \
	LOCAL_CALL="true" \
	/srv/jenkins/bin/reproducible_remote_scheduler.py \
		--message "$REASON" \
		--no-notify \
		--suite "$SUITE" \
		--architecture "$ARCH" \
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
					STATE_TARGET_NAME="FTBR"
					;;
		FTBFS)			ICON=weather-storm.png
					;;
		depwait)		ICON=weather-snow.png
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
	# this is really quite uncomprehensible and should be killed
	# the solution is to write all html pages with python…
	rm -f $PAGE
	MAINVIEW="dashboard"
	ALLSTATES="reproducible FTBR FTBFS depwait not_for_us 404 blacklisted"
	ALLVIEWS="notes no_notes pkg_sets last_24h last_48h all_abc arch scheduled suite_stats dd-list dashboard issues repositories notify"
	GLOBALVIEWS="issues scheduled notify repositories dashboard"
	SUITEVIEWS="dd-list suite_stats"
	SPOKENTARGET["issues"]="issues"
	SPOKENTARGET["notes"]="packages with notes"
	SPOKENTARGET["no_notes"]="packages without notes"
	SPOKENTARGET["scheduled"]="currently scheduled"
	SPOKENTARGET["last_24h"]="packages tested in the last 24h"
	SPOKENTARGET["last_48h"]="packages tested in the last 48h"
	SPOKENTARGET["all_abc"]="all tested packages (sorted alphabetically)"
	SPOKENTARGET["notify"]="⚑ packages with enabled notifications"
	SPOKENTARGET["dd-list"]="maintainers of unreproducible packages"
	SPOKENTARGET["pkg_sets"]="package sets"
	SPOKENTARGET["suite_stats"]="suite: $SUITE"
	SPOKENTARGET["repositories"]="repositories overview"
	SPOKENTARGET["dashboard"]="Debian dashboard"
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<meta name=\"viewport\" content=\"width=device-width\" />"
	write_page "<link href=\"/userContent/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	if [ "$1" != "$MAINVIEW" ] ; then
		write_page "<body class=\"wrapper\"><header class=\"head\"><h2>$2</h2>"
	else
		write_page "<body class=\"wrapper\" onload=\"selectSearch()\"><header class=\"head\"><h2>$2</h2>"
	fi
	write_page "<ul class=\"menu\">"
	write_page "<li>$SUITE/$ARCH:<ul class=\"children\">"
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
		# prepare unsorted lists
		if [ "$TARGET" = "notes" ] ; then
			write_page "<li>Notes<ul class=\"children\">"
		elif [ "$TARGET" = "last_24h" ] ; then
			write_page "<li>Recently tested:<ul class=\"children\">"
		fi
		# prepare links
		if [ "$TARGET" = "scheduled" ] ; then
			write_page "<li><a href=\"/index_${ARCH}_scheduled.html\">${SPOKEN_TARGET}</a></li>"
		elif [ "$TARGET" = "notify" ] ; then
			write_page "<li><a href=\"$BASEURL/index_${TARGET}.html\" title=\"notify icon\">${SPOKEN_TARGET}</a></li>"
		elif [ "$TARGET" = "arch" ] ; then
			write_page "<li>Architectures:<ul class=\"children\"><li>"
			for i in ${ARCHS} ; do
				write_page " <a href=\"/$SUITE/index_suite_${i}_stats.html\">$i</a>"
			done
			write_page "</li>"
		elif [ "$TARGET" = "suite_stats" ] ; then
			write_page "<li>Suites:<ul class=\"children\"><li>"
			for i in $SUITES ; do
				write_page " <a href=\"/$i/index_suite_${ARCH}_stats.html\">$i</a>"
			done
			write_page "</li>"
		elif [ "$TARGET" = "dashboard" ] ; then
			write_page "<li><a href=\"$BASEURL/index_${TARGET}.html\">${SPOKEN_TARGET}</a><ul class=\"children\">"
		else
			# finally, write link
			write_page "<li><a href=\"$BASEURL/index_${TARGET}.html\">${SPOKEN_TARGET}</a></li>"
		fi
		# close unsorted lists (and package states loop)
		if [ "$TARGET" = "all_abc" ] ; then
			write_page "</ul></li>"
		elif [ "$TARGET" = "last_48h" ] ; then
			write_page "</ul></li>"
		elif [ "$TARGET" = "notify" ] ; then
			write_page "</ul></li>"
		elif [ "$TARGET" = "scheduled" ] ; then
			write_page "</ul></li>"
		elif [ "$TARGET" = "dd-list" ] ; then
			write_page "</ul></li>"
		elif [ "$TARGET" = "no_notes" ] ; then
			write_page "</ul></li>"
			# after notes we have package states
			write_page "<li>Package states:"
			write_page "<ul class=\"children\"><li>"
			for MY_STATE in $ALLSTATES ; do
				set_icon $MY_STATE
			write_icon
			write_page " "
			done
			write_page "</li></ul></li>"
		fi
	done
	write_page "</ul>"
	# project links
	write_page "    <ul class=\"reproducible-links\">"
	write_page "        <li>Reproducible Builds projects links"
	write_page "         <ul class=\"children\"><li>"
	write_page "            <a href=\"https://Reproducible-builds.org\">Reproducible-builds.org</a><br />"
	write_page "            Reproducible-builds.org - <a href=\"https://Reproducible-builds.org/docs/\">HowTo</a><br />"
	write_page "            Reproducible Debian - <a href=\"https://wiki.debian.org/ReproducibleBuilds\">Wiki</a><br />"
	write_page "            Reproducible builds <a href=\"https://reproducible.alioth.debian.org/blog/\">weekly news</a><br />"
	write_page "            </li><li>"
	write_page "            Reproducible <a href=\"https://tests.reproducible-builds.org/archlinux/\">Arch Linux</a> /"
	write_page "            <a href=\"https://tests.reproducible-builds.org/coreboot/\">coreboot</a> /"
	write_page "            <a href=\"https://tests.reproducible-builds.org/fedora/\">Fedora</a> /"
	write_page "            <a href=\"https://tests.reproducible-builds.org/freebsd/\">FreeBSD</a> /"
	write_page "            <a href=\"https://tests.reproducible-builds.org/netbsd/\">NetBSD</a> /"
	write_page "            <a href=\"https://tests.reproducible-builds.org/openwrt/\">OpenWrt</a>"
	write_page "        </li></ul></li>"
	write_page "    </ul>"
	# end project links
	write_page "</header>"
	write_page "<div class=\"mainbody\">"
	if [ "$1" = "$MAINVIEW" ] ; then
		write_page "<ul>"
		write_page "   A general website <li><a href=\"https://reproducible-builds.org\">Reproducible-builds.org</a></li> is available now."
		write_page "   We think that reproducible builds should become the norm, so we wrote <li><a href=\"https://reproducible-builds.org/howto\">How to make your software reproducible</a></li>."
		write_page "   Also aimed at the free software world at large, is the first specification we have written: the <li><a href=\"https://reproducible-builds.org/specs/source-date-epoch/\">SOURCE_DATE_EPOCH specification</a></li>."
		write_page "</ul>"
		write_page "<ul>"
		write_page "   These pages are showing the <em>prospects</em> of <li><a href=\"https://wiki.debian.org/ReproducibleBuilds\" target=\"_blank\">reproducible builds of Debian packages</a></li>."
		write_page "   The results shown were obtained by <a href=\"$JENKINS_URL/view/reproducible\">several jobs</a> running on"
		write_page "   <a href=\"$JENKINS_URL/userContent/about.html#_reproducible_builds_jobs\">jenkins.debian.net</a>."
		write_page "   Thanks to <a href=\"https://www.profitbricks.co.uk\">Profitbricks</a> for donating the virtual machines this is running on!"
		write_page "</ul>"
		LATEST=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id = s.id WHERE r.status IN ('unreproducible') AND s.suite = 'unstable' AND s.architecture = 'amd64' AND s.id NOT IN (SELECT package_id FROM notes) ORDER BY build_date DESC LIMIT 23"|sort -R|head -1)
		write_page "<form action=\"$REPRODUCIBLE_URL/redirect\" method=\"GET\">$REPRODUCIBLE_URL/"
		write_page "<input type=\"text\" name=\"SrcPkg\" placeholder=\"Type my friend..\" value=\"$LATEST\" />"
		write_page "<input type=\"submit\" value=\"submit source package name\" />"
		write_page "</form>"
	elif [ "$1" = "dd-list" ] || [ "$1" = "$MAINVIEW" ] ; then
		write_page "<ul>"
		write_page "   We are reachable via IRC (<code>#debian-reproducible</code> and <code>#reproducible-builds</code> on OFTC),"
		write_page "   or <a href="mailto:reproducible-builds@lists.alioth.debian.org">email</a>,"
		write_page "   and we care about free software in general,"
		write_page "   so whether you are an upstream developer or working on another distribution, or have any other feedback - we'd love to hear from you!"
		write_page "   Besides Debian we are also testing <li><a href=\"/coreboot/\">coreboot</a></li>, <li><a href=\"/openwrt/\">OpenWrt</a></li>, <li><a href=\"netbsd\">NetBSD</a></li>, <li><a href=\"/freebsd/\">FreeBSD</a></li> and <li><a href=\"archlinux\">Arch Linux</a></li> now, though not as thoroughly as Debian (yet?) - and testing of <li><a href=\"/rpms/fedora-23.html\">Fedora</a></li> has just begun, and there are plans to test <a href=\"https://jenkins.debian.net/userContent/todo.html#_reproducible_fdroid\">F-Droid</a> and <a href=\"https://jenkins.debian.net/userContent/todo.html#_reproducible_guix\">GNU Guix</a> too, and more, if you contribute!"
		write_page "</ul>"
	fi
}

write_page_intro() {
	write_page "       <p><em>Reproducible builds</em> enable anyone to reproduce bit by bit identical binary packages from a given source, so that anyone can verify that a given binary derived from the source it was said to be derived."
	write_page "         There is a lot more information about <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds on the Debian wiki</a> and on <a href=\"https://tests.reproducible-builds.org\">https://tests.reproducible-builds.org</a>."
	write_page "         The wiki explains in more depth why this is useful, what common issues exist and which workarounds and solutions are known."
	write_page "        </p>"
	local BUILD_ENVIRONMENT=" in a Debian environment"
	local BRANCH="master"
	if [ "$1" = "coreboot" ] ; then
		write_page "        <p><em>Reproducible Coreboot</em> is an effort to apply this to coreboot. Thus each coreboot.rom is build twice (without payloads), with a few varitations added and then those two ROMs are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="$1"
		local PROJECTURL="https://review.coreboot.org/p/coreboot.git"
	elif [ "$1" = "OpenWrt" ] ; then
		write_page "        <p><em>Reproducible OpenWrt</em> is an effort to apply this to OpenWrt. Thus each OpenWrt target is build twice, with a few varitations added and then the resulting images and packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. OpenWRT generates many different types of raw <code>.bin</code> files, and diffoscope does not know how to parse these. Thus the resulting diffoscope output is not nearly as clear as it could be - hopefully this limitation will be overcome eventually, but in the meanwhile the input components (uImage kernel file, rootfs.tar.gz, and/or rootfs squashfs) can be inspected. Also please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="openwrt"
		local PROJECTURL="git://git.openwrt.org/openwrt.git"
	elif [ "$1" = "NetBSD" ] ; then
		write_page "        <p><em>Reproducible NetBSD</em> is an effort to apply this to NetBSD. Thus each NetBSD target is build twice, with a few varitations added and then the resulting files from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="netbsd"
		local PROJECTURL="https://github.com/jsonn/src"
	elif [ "$1" = "FreeBSD" ] ; then
		write_page "        <p><em>Reproducible FreeBSD</em> is an effort to apply this to FreeBSD. Thus FreeBSD is build twice, with a few varitations added and then the resulting filesystems from the two builds are put into a compressed tar archive, which is finally compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="freebsd"
		local PROJECTURL="https://github.com/freebsd/freebsd.git"
		local BUILD_ENVIRONMENT=", which via ssh triggers a build on a FreeBSD 10.2 system"
		local BRANCH="release/10.2.0"
	elif [ "$1" = "Arch Linux" ] ; then
		local PROJECTNAME="Arch Linux"
		write_page "        <p><em>Reproducible $PROJECTNAME</em> is an effort to apply this to $PROJECTNAME. Thus $PROJECTNAME packages are build twice, with a few varitations added and then the resulting packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
	elif [ "$1" = "fedora-23" ] ; then
		local PROJECTNAME="Fedora 23"
		write_page "        <p><em>Reproducible $PROJECTNAME</em> is an effort to apply this to $PROJECTNAME. Thus $PROJECTNAME packages are build twice, with a few varitations added and then the resulting packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		write_page "        <p>Please note that this set up is as new as December 12th, so quite some things are still lacking, eg. https://github.com/kholia/ReproducibleBuilds is not followed at all yet and there are no variations introduced for the 2nd build. Also only a subset of all source packages is currently being tested. OTOH this setup is mature enough that it requires very few trivial changes to build all 17080 source packages in $PROJECTNAME, if it were sensible. Which it isn't right now, but should be soon.</p>"
	fi
	if [ "$1" != "Arch Linux" ] && [ "$1" != "fedora-23" ] ; then
		write_page "       <p>There is a weekly run <a href=\"https://jenkins.debian.net/view/reproducible/job/reproducible_$PROJECTNAME/\">jenkins job</a> to test the <code>$BRANCH</code> branch of <a href=\"$PROJECTURL\">$PROJECTNAME.git</a>. The jenkins job is running <a href=\"https://anonscm.debian.org/git/qa/jenkins.debian.net.git/tree/bin/reproducible_$PROJECTNAME.sh\">reproducible_$PROJECTNAME.sh</a>$BUILD_ENVIRONMENT and this script is solely responsible for creating this page. Feel invited to join <code>#debian-reproducible</code> (on irc.oftc.net) to request job runs whenever sensible. Patches and other <a href=\"mailto:reproducible-builds@lists.alioth.debian.org\">feedback</a> are very much appreciated - if you want to help, please start by looking at the <a href=\"https://jenkins.debian.net/userContent/todo.html#_reproducible_$(echo $1|tr '[:upper:]' '[:lower:]')\">ToDo list for $1</a>, you might find something easy to contribute."
		write_page "       <br />Thanks to <a href=\"https://www.profitbricks.co.uk\">Profitbricks</a> for donating the virtual machines this is running on!</p>"
	else
		write_page "       <p>FIXME: explain $PROJECTNAME test setup here.</p>"
	fi
}

write_page_footer() {
	write_page "<hr id=\"footer_separator\" /><p style=\"font-size:0.9em;\"><div id=\"page_footer\">"
	if [ -n "$JOB_URL" ] ; then
		write_page "This page was built by the jenkins job"
		write_page "<a href=\"$JOB_URL\">$(basename $JOB_URL)</a> which is configured"
		write_page "via this <a href=\"https://anonscm.debian.org/git/qa/jenkins.debian.net.git/\">git repo</a>."
	fi
	write_page "There is more information <a href=\"https://jenkins.debian.net/userContent/about.html\">about jenkins.debian.net</a> and about <a href=\"https://wiki.debian.org/ReproducibleBuilds\"> reproducible builds of Debian</a> available elsewhere."
	write_page "<br /> Last update: $(date +'%Y-%m-%d %H:%M %Z'). Copyright 2014-2016 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a> and <a href=\"https://jenkins.debian.net//userContent/thanks.html\">many others</a>."
	write_page "The code of <a href=\"https://anonscm.debian.org/git/qa/jenkins.debian.net.git/\">jenkins.debian.net.git</a> is mostly GPL-2 licensed. The weather icons are public domain and have been taken from the <a href=\"http://tango.freedesktop.org/Tango_Icon_Library\" target=\"_blank\">Tango Icon Library</a>."
	write_page "<br />"
	if [ "$1" = "coreboot" ] ; then
		write_page "The <a href=\"http://www.coreboot.org\">Coreboot</a> logo is Copyright © 2008 by Konsult Stuge and coresystems GmbH and can be freely used to refer to the Coreboot project."
	elif [ "$1" = "NetBSD" ] ; then
		write_page "NetBSD® is a registered trademark of The NetBSD Foundation, Inc."
	elif [ "$1" = "FreeBSD" ] ; then
		write_page "FreeBSD is a registered trademark of The FreeBSD Foundation. The FreeBSD logo and The Power to Serve are trademarks of The FreeBSD Foundation."
	elif [ "$1" = "Arch Linux" ] ; then
		write_page "The <a href=\"https://www.archlinux.org\">Arch Linux</a> name and logo are recognized trademarks. Some rights reserved. The registered trademark Linux® is used pursuant to a sublicense from LMI, the exclusive licensee of Linus Torvalds, owner of the mark on a world-wide basis."
	elif [ "$1" = "fedora-23" ] ; then
		write_page "FIXME: add fedora copyright+trademark disclaimers here."
	fi
	write_page "</div></p>"
	write_page "</div>"
	write_page "</body></html>"
}

write_page_meta_sign() {
	write_page "<p style=\"font-size:0.9em;\">A package name displayed with a <span style=\"font-weight: bold;\">bold font</span> is an indication that this package has a note. Visited packages are linked in green, those which have not been visited are linked in blue.</br>"
	write_page "A <code><span class=\"bug\">&#35;</span></code> sign after the name of a package indicates that a bug is filed against it. Likewise, a <code><span class=\"bug-patch\">&#43;</span></code> sign indicates there is a patch available, a <code><span class="bug-pending">P</span></code> means a pending bug while <code><span class=\"bug-done\">&#35;</span></code> indicates a closed bug. In cases of several bugs, the symbol is repeated.</p>"
}

write_variation_table() {
	write_page "<p style=\"clear:both;\">"
	if [ "$1" = "fedora-23" ] ; then
		write_page "There are no variations introduced in the $1 builds yet. Stay tuned.</p>"
		return
	fi
	write_page "<table class=\"main\" id=\"variation\"><tr><th>variation</th><th width=\"40%\">first build</th><th width=\"40%\">second build</th></tr>"
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>hostname</td><td>one of:"
		for a in ${ARCHS} ; do
			local COMMA=""
			local ARCH_NODES=""
			write_page "<br />&nbsp;&nbsp;"
			for i in $(echo $BUILD_NODES | sed -s 's# #\n#g' | sort -u) ; do
				if [ "$(echo $i | grep $a)" ] ; then
					echo -n "$COMMA ${ARCH_NODES}$(echo $i | cut -d '.' -f1 | sed -s 's# ##g')" >> $PAGE
					if [ -z $COMMA ] ; then
						COMMA=","
					fi
				fi
			done
		done
		write_page "</td><td>i-capture-the-hostname</td></tr>"
		write_page "<tr><td>domainname</td><td>$(hostname -d)</td><td>i-capture-the-domainname</td></tr>"
	else
		write_page "<tr><td>hostname</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>domainname</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
	fi
	if [ "$1" != "FreeBSD" ] && [ "$1" != "Arch Linux" ] && [ "$1" != "fedora-23" ] ; then
		write_page "<tr><td>env CAPTURE_ENVIRONMENT</td><td><em>not set</em></td><td>CAPTURE_ENVIRONMENT=\"I capture the environment\"</td></tr>"
	fi
	write_page "<tr><td>env TZ</td><td>TZ=\"/usr/share/zoneinfo/Etc/GMT+12\"</td><td>TZ=\"/usr/share/zoneinfo/Etc/GMT-14\"</td></tr>"
	if [ "$1" = "debian" ]  ; then
		write_page "<tr><td>env LANG</td><td>LANG=\"C\"</td><td>on amd64: LANG=\"fr_CH.UTF-8\"<br />on i386: LANG=\"de_CH.UTF-8\"<br />on armhf: LANG=\"it_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>env LANGUAGE</td><td>LANGUAGE=\"en_US:en\"</td><td>on amd64: LANGUAGE=\"fr_CH:fr\"<br />on i386: LANGUAGE=\"de_CH:de\"<br />on armhf: LANGUAGE=\"it_CH:it\"</td></tr>"
		write_page "<tr><td>env LC_ALL</td><td><em>not set</em></td><td>on amd64: LC_ALL=\"fr_CH.UTF-8\"<br />on i386: LC_ALL=\"de_CH.UTF-8\"<br />on armel: LC_ALL=\"it_CH.UTF-8\"</td></tr>"
	elif [ "$1" = "Arch Linux" ]  ; then
		write_page "<tr><td>env LANG</td><td><em>not set</em></td><td>LANG=\"fr_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>env LC_ALL</td><td><em>not set</em></td><td>LC_ALL=\"fr_CH.UTF-8\"</td></tr>"
	else
		write_page "<tr><td>env LANG</td><td>LANG=\"en_GB.UTF-8\"</td><td>LANG=\"fr_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>env LC_ALL</td><td><em>not set</em></td><td>LC_ALL=\"fr_CH.UTF-8\"</td></tr>"
	fi
	if [ "$1" != "FreeBSD" ] && [ "$1" != "Arch Linux" ]  ; then
		write_page "<tr><td>env PATH</td><td>PATH=\"/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:\"</td><td>PATH=\"/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path\"</td></tr>"
	else
		write_page "<tr><td>env PATH</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
	fi
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>env BUILDUSERID</td><td>BUILDUSERID=\"1111\"</td><td>BUILDUSERID=\"2222\"</td></tr>"
		write_page "<tr><td>env BUILDUSERNAME</td><td>BUILDUSERNAME=\"pbuilder1\"</td><td>BUILDUSERNAME=\"pbuilder2\"</td></tr>"
		write_page "<tr><td>env USER</td><td>USER=\"pbuilder1\"</td><td>USER=\"pbuilder2\"</td></tr>"
		write_page "<tr><td>uid</td><td>uid=1111</td><td>uid=2222</td></tr>"
		write_page "<tr><td>gid</td><td>gid=1111</td><td>gid=2222</td></tr>"
		write_page "<tr><td>env DEB_BUILD_OPTIONS</td><td>DEB_BUILD_OPTIONS=\"parallel=XXX\"<br />&nbsp;&nbsp;XXX on amd64 and i386: 18 or 17<br />&nbsp;&nbsp;XXX on armhf: 8, 4 or 2</td><td>DEB_BUILD_OPTIONS=\"parallel=YYY\"<br />&nbsp;&nbsp;YYY on amd64 and i386: 17 or 18 (!= the first build)<br />&nbsp;&nbsp;YYY on armhf: 8, 4, or 2 (not varied systematically)</td></tr>"
		write_page "<tr><td>UTS namespace</td><td><em>shared with the host</em></td><td><em>modified using</em> /usr/bin/unshare --uts</td></tr>"
	else
		write_page "<tr><td>env USER</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>uid</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>gid</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		if [ "$1" != "FreeBSD" ] ; then
			write_page "<tr><td>UTS namespace</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		fi
	fi
	if [ "$1" != "FreeBSD" ] ; then
		if [ "$1" = "debian" ] ; then
			write_page "<tr><td>kernel version</td></td><td>"
			for a in ${ARCHS} ; do
				write_page "<br />on $a one of:"
				write_page "$(cat /srv/reproducible-results/node-information/*$a* | grep KERNEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')"
			done
			write_page "</td>"
			write_page "<td>(on amd64 systematically varied, on i386 as well and also with 32 and 64 bit kernel variation, while on armhf not systematically)<br />"
			for a in ${ARCHS} ; do
				write_page "<br />on $a one of:"
				write_page "$(cat /srv/reproducible-results/node-information/*$a* | grep KERNEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')"
			done
			write_page "</td></tr>"
		elif [ "$1" != "Arch Linux" ]  ; then
			write_page "<tr><td>kernel version, modified using /usr/bin/linux64 --uname-2.6</td><td>$(uname -sr)</td><td>$(/usr/bin/linux64 --uname-2.6 uname -sr)</td></tr>"
		else
			write_page "<tr><td>kernel version</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		fi
		write_page "<tr><td>umask</td><td>0022<td>0002</td><tr>"
	else
		write_page "<tr><td>FreeBSD kernel version</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>umask</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td><tr>"
	fi
	FUTURE=$(date --date="${DATE}+398 days" +'%Y-%m-%d')
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>CPU type</td><td>one of: $(cat /srv/reproducible-results/node-information/* | grep CPU_MODEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')</td><td>on amd64: systematically varied (AMD or Intel CPU with different names & features)<br />on i386: same for both builds (currently, work in progress)<br />on armhf: sometimes varied (depending on the build job), but only the minor CPU revision</td></tr>"
		write_page "<tr><td>/bin/sh</td><td>/bin/dash</td><td>/bin/bash</td></tr>"
		write_page "<tr><td>year, month, date</td><td>today ($DATE) or (on amd64 and i386 only) also: $FUTURE</td><td>on amd64 and i386: varied (398 days difference)<br />on armhf: same for both builds (currently, work in progress)</td></tr>"
	else
		write_page "<tr><td>CPU type</td><td>$(cat /proc/cpuinfo|grep 'model name'|head -1|cut -d ":" -f2-)</td><td>same for both builds</td></tr>"
		write_page "<tr><td>/bin/sh</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		if [ "$1" != "FreeBSD" ] ; then
			write_page "<tr><td>year, month, date</td><td>today ($DATE)</td><td>same for both builds (currently, work in progress)</td></tr>"
		else
			write_page "<tr><td>year, month, date</td><td>today ($DATE)</td><td>398 days in the future ($FUTURE)</td></tr>"
		fi
	fi
	if [ "$1" != "FreeBSD" ] ; then
		if [ "$1" = "debian" ] ; then
			write_page "<tr><td>hour, minute</td><td>at least the minute will probably vary between two builds anyway...</td><td>on amd64 and i386 the \"future builds\" additionally run 6h and 23min ahead</td></tr>"
		        write_page "<tr><td>filesystem</td><td>tmpfs</td><td><em>temporarily not</em> varied using <a href=\"https://tracker.debian.org/disorderfs\">disorderfs</a> (<a href=\"https://sources.debian.net/src/disorderfs/sid/disorderfs.1.txt/\">manpage</a>)</td></tr>"
		else
			write_page "<tr><td>hour, minute</td><td>hour and minute will probably vary between two builds...</td><td>but this is not enforced systematically... (currently, work in progress)</td></tr>"
			write_page "<tr><td>Filesystem</td><td>tmpfs</td><td>same for both builds (currently, this could be varied using <a href=\"https://tracker.debian.org/disorderfs\">disorderfs</a>)</td></tr>"
		fi
	else
		write_page "<tr><td>year, month, date</td><td>today ($DATE)</td><td>the 2nd build is done with the build node set 1 year, 1 month and 1 day in the future</td></tr>"
		write_page "<tr><td>hour, minute</td><td>hour and minute will vary between two builds</td><td>additionally the \"future build\" also runs 6h and 23min ahead</td></tr>"
		write_page "<tr><td>filesystem of the build directory</td><td>ufs</td><td>same for both builds</td></tr>"
	fi
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td><em>everything else...</em></td><td colspan=\"2\">is likely the same. So far, this is just about the <em>prospects</em> of <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds of Debian</a> - there will be more variations in the wild.</td></tr>"
	else
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

gen_package_html() {
	cd /srv/jenkins/bin
	python3 -c "import reproducible_html_packages as rep
pkg = rep.Package('$1', no_notes=True)
rep.gen_packages_html([pkg], no_clean=True)" || echo "Warning: cannot update html pages for $1"
	cd - > /dev/null
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

print_out_duration() {
	if [ -z "$DURATION" ]; then
		return
	fi
	local HOUR=$(echo "$DURATION/3600"|bc)
	local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date -u) - total duration: ${HOUR}h ${MIN}m ${SEC}s." | tee -a ${RBUILDLOG}
}

irc_message() {
	local CHANNEL="$1"
	shift
	local MESSAGE="$@"
	kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE" || true # don't fail the whole job
}

call_diffoscope() {
	mkdir -p $TMPDIR/$1/$(dirname $2)
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	local msg=""
	set +e
	# remember to also modify the retry diffoscope call 15 lines below
	( timeout $TIMEOUT nice schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-diffoscope \
		diffoscope -- \
			--html $TMPDIR/$1/$2.html \
			$TMPDIR/b1/$1/$2 \
			$TMPDIR/b2/$1/$2 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	LOG_RESULT=$(grep '^E: 15binfmt: update-binfmts: unable to open' $TMPLOG || true)
	if [ ! -z "$LOG_RESULT" ] ; then
		rm -f $TMPLOG $TMPDIR/$1/$2.html
		echo "$(date -u) - schroot jenkins-reproducible-${DBDSUITE}-diffoscope not available, will sleep 2min and retry."
		sleep 2m
		# remember to also modify the retry diffoscope call 15 lines above
		( timeout $TIMEOUT nice schroot \
			--directory $TMPDIR \
			-c source:jenkins-reproducible-${DBDSUITE}-diffoscope \
			diffoscope -- \
				--html $TMPDIR/$1/$2.html \
				$TMPDIR/b1/$1/$2 \
				$TMPDIR/b2/$1/$2 2>&1 \
			) 2>&1 >> $TMPLOG
		RESULT=$?
	fi
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG # print dbd output
	rm -f $TMPLOG
	case $RESULT in
		0)	echo "$(date -u) - $1/$2 is reproducible, yay!"
			;;
		1)
			echo "$(date -u) - $DIFFOSCOPE found issues, please investigate $1/$2"
			;;
		2)
			msg="$(date -u) - $DIFFOSCOPE had trouble comparing the two builds. Please investigate $1/$2"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				msg="$(date -u) - $DIFFOSCOPE produced no output for $1/$2 and was killed after running into timeout after ${TIMEOUT}..."
			else
				msg="$DIFFOSCOPE was killed after running into timeout after $TIMEOUT, but there is still $TMPDIR/$1/$2.html"
			fi
			;;
		*)
			msg="$(date -u) - Something weird happened when running $DIFFOSCOPE on $1/$2 (which exited with $RESULT) and I don't know how to handle it."
			;;
	esac
	if [ ! -z "$msg" ] ; then
		echo $msg | tee -a $TMPDIR/$1/$2.html
	fi
}

get_filesize() {
		local BYTESIZE="$(du -h -b $1 | cut -f1)"
		# numbers below 16384K are understood and more meaningful than 16M...
		if [ $BYTESIZE -gt 16777216 ] ; then
			SIZE="$(echo $BYTESIZE/1048576|bc)M"
		elif [ $BYTESIZE -gt 1024 ] ; then
			SIZE="$(echo $BYTESIZE/1024|bc)K"
		else
			SIZE="$BYTESIZE bytes"
		fi
}

cleanup_pkg_files() {
	rm -vf $BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_*.rbuild.log{,.gz}
	rm -vf $BASE/logs/${SUITE}/${ARCH}/${SRCPACKAGE}_*.build?.log{,.gz}
	rm -vf $BASE/dbd/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diffoscope.html
	rm -vf $BASE/dbdtxt/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diffoscope.txt{,.gz}
	rm -vf $BASE/buildinfo/${SUITE}/${ARCH}/${SRCPACKAGE}_*.buildinfo
	rm -vf $BASE/logdiffs/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diff{,.gz}
}

#
# create the png (and query the db to populate a csv file...)
#
create_png_from_table() {
	echo "Checking whether to update $2..."
	# $1 = id of the stats table
	# $2 = image file name
	# $3 = meta package set, only sensible if $1=6
	echo "${FIELDS[$1]}" > ${TABLE[$1]}.csv
	# prepare query
	WHERE_EXTRA="WHERE suite = '$SUITE'"
	if [ "$ARCH" = "armhf" ] ; then
		# armhf was only build since 2015-08-30
		WHERE2_EXTRA="WHERE s.datum >= '2015-08-30'"
	elif [ "$ARCH" = "i386" ] ; then
		# i386 was only build since 2016-03-28
		WHERE2_EXTRA="WHERE s.datum >= '2016-03-28'"
	else
		WHERE2_EXTRA=""
	fi
	if [ $1 -eq 3 ] || [ $1 -eq 4 ] || [ $1 -eq 5 ] || [ $1 -eq 8 ] ; then
		# TABLE[3+4+5] don't have a suite column: (and TABLE[8] (and 9) is faked, based on 3)
		WHERE_EXTRA=""
	fi
	if [ $1 -eq 0 ] || [ $1 -eq 2 ] || [ $1 -eq 6 ] ; then
		# TABLE[0+2+6] have a architecture column:
		WHERE_EXTRA="$WHERE_EXTRA AND architecture = \"$ARCH\""
		if [ "$ARCH" = "armhf" ]  ; then
			if [ $1 -eq 2 ] ; then
				# unstable/armhf was only build since 2015-08-30 (and experimental/armhf since 2015-12-19 and testing/armhf since 2016-01-01)
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2015-08-30'"
			elif [ $1 -eq 6 ] ; then
				# armhf only has pkg sets for unstable since 2015-12-22 and since 2016-02-13 for testing
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2015-12-22'"
			fi
		elif [ "$ARCH" = "i386" ]  ; then
			if [ $1 -eq 2 ] ; then
				# i386 was only build since 2016-03-28
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2016-03-28'"
			elif [ $1 -eq 6 ] ; then
				# i386 only has pkg sets since later to make nicer graphs
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2016-05-06'"
			fi
		fi
		# testing/amd64 was only build since...
		# WHERE2_EXTRA="WHERE s.datum >= '2015-03-08'"
		# experimental/amd64 was only build since...
		# WHERE2_EXTRA="WHERE s.datum >= '2015-02-28'"
	fi
	if [ $1 -eq 6 ] ; then
		# 6 is very special too...
		WHERE_EXTRA="$WHERE_EXTRA and meta_pkg = '$3'"
	fi
	# run query
	if [ $1 -eq 1 ] ; then
		# not sure if it's worth to generate the following query...
		WHERE_EXTRA="AND architecture='$ARCH'"
		sqlite3 -init ${INIT} --nullvalue 0 -csv ${PACKAGES_DB} "SELECT s.datum,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='testing' $WHERE_EXTRA),0) AS reproducible_testing,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA),0) AS reproducible_unstable,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA),0) AS reproducible_experimental,
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing' $WHERE_EXTRA) AS unreproducible_testing,
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS unreproducible_unstable,
			 (SELECT e.unreproducible FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS unreproducible_experimental,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing' $WHERE_EXTRA) AS FTBFS_testing,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS FTBFS_unstable,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS FTBFS_experimental,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='testing' $WHERE_EXTRA) AS other_testing,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS other_unstable,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS other_experimental
			 FROM stats_builds_per_day AS s $WHERE2_EXTRA GROUP BY s.datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 2 ] ; then
		# just make a graph of the oldest reproducible build (ignore FTBFS and unreproducible)
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, oldest_reproducible FROM ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 7 ] ; then
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, $SUM_DONE, $SUM_OPEN from ${TABLE[3]} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 8 ] ; then
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$1]} from ${TABLE[3]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 9 ] ; then
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT datum, $REPRODUCIBLE_DONE, $REPRODUCIBLE_OPEN from ${TABLE[3]} ORDER BY datum" >> ${TABLE[$1]}.csv
	else
		sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$1]} from ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	fi
	# this is a gross hack: normally we take the number of colors a table should have...
	#  for the builds_age table we only want one color, but different ones, so this hack:
	COLORS=${COLOR[$1]}
	if [ $1 -eq 2 ] ; then
		case "$SUITE" in
			testing)	COLORS=40 ;;
			unstable)	COLORS=41 ;;
			experimental)	COLORS=42 ;;
		esac
	fi
	local WIDTH=1920
	local HEIGHT=960
	# only generate graph if the query returned data
	if [ $(cat ${TABLE[$1]}.csv | wc -l) -gt 1 ] ; then
		echo "Updating $2..."
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Generating $2."
		/srv/jenkins/bin/make_graph.py ${TABLE[$1]}.csv $2 ${COLORS} "${MAINLABEL[$1]}" "${YLABEL[$1]}" $WIDTH $HEIGHT
		mv $2 $BASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	# create empty dummy png if there havent been any results ever
	elif [ ! -f $BASE/$DIR/$(basename $2) ] ; then
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Creating $2 dummy."
		convert -size 1920x960 xc:#aaaaaa -depth 8 $2
		if [ "$3" != "" ] ; then
			local THUMB="${TABLE[1]}_${3}-thumbnail.png"
			convert $2 -adaptive-resize 160x80 ${THUMB}
			mv ${THUMB} $BASE/$DIR
		fi
		mv $2 $BASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	fi
	rm ${TABLE[$1]}.csv
}

