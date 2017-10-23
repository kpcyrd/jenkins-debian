#!/bin/bash

# Copyright 2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# run with "bug" as first parameter for interactive mode which will fire up mutt for 10 buggy packages
# 
#
if [ -z "$1" ] ; then
	echo "Call $(basename $0) [bug] NEXT SUITE1 SUITE2 SUITE3"
	echo "         bug to enter manual mode"
	echo "         NEXT suite which is being developed, eg 'buster'"
	echo "         SUITE1/2/3: suites to look at, eg. 'jessie stretch sid'"
	exit 0
fi

DEBUG=false
if [ -f /srv/jenkins/bin/common-functions.sh ] ; then
	. /srv/jenkins/bin/common-functions.sh
	common_init "$@"
else
	#normally defined in common-functions.sh
	export MIRROR=http://deb.debian.org/debian
	#for quicker development:
	#PACKAGES[0]=/home/schroots/jessie/var/lib/apt/lists/deb.debian.org_debian_dists_jessie_main_binary-amd64_Packages
	#PACKAGES[1]=/var/lib/apt/lists/deb.debian.org_debian_dists_stretch_main_binary-amd64_Packages
	#PACKAGES[2]=/home/schroots/sid/var/lib/apt/lists/deb.debian.org_debian_dists_sid_main_binary-amd64_Packages
fi

if ! which chdist ; then
	echo "Please install devscripts."
	exit 1
elif ! which grep-dctrl ; then
	echo "Please install grep-dctrl."
	exit 1
fi

if [ "$1" = "bug" ] ; then
	MANUAL_MODE=true
	echo "Entering manual bug filing mode."
	shift
else
	MANUAL_MODE=false
fi


LANG="en_EN.UTF-8"
ARCH=amd64
NEXT="$1"		# buster
shift
SUITES="$@" 		# jessie stretch sid
OLDSTABLE="jessie"
STABLE="stretch"
if [ "$NEXT" != "buster" ] ; then
	echo "This script needs more changes to work on other suites than buster…"
	echo "Not many, but a very few."
	exit 1
fi
echo "Looking at $SUITES for obsolete transitional packages in $NEXT."
# transitional packages we know bugs have been filed about…
BUGGED="multiarch-support jadetex dh-systemd libpcap-dev transfig myspell-it myspell-sl python-gobject ttf-dejavu ttf-dejavu-core ttf-dejavu-extra libav-tools netcat gnupg2 libkf5akonadicore-bin qml-module-org-kde-extensionplugin myspell-ca myspell-en-gb myspell-sv-se myspell-lt khelpcenter4 libqca2-plugin-ossl gambas3-gb-desktop-gnome git-core gperf-ace libalberta2-dev asterisk-prompt-it libatk-adaptor-data kdemultimedia-dev kdemultimedia-kio-plugins autoconf-gl-macros autofs5 autofs5-hesiod autofs5-ldap librime-data-stroke5 librime-data-stroke-simp librime-data-triungkox3p pmake host bibledit bibledit-data baloo libc-icap-mod-clamav otf-symbols-circos migemo condor condor-dbg condor-dev condor-doc cscope-el cweb-latex dconf-tools python-decoratortools deluge-torrent deluge-webui django-filter python-django-filter django-tables django-xmlrpc drbd8-utils libefreet1 libjs-flot conky ttf-kacst ttf-junicode ttf-isabella font-hosny-amiri ttf-hanazono ttf-georgewilliams otf-freefont ttf-freefont ttf-freefarsi ttf-liberation libhdf5-serial-dev graphviz-dev git-bzr libgd-gd2-noxpm-ocaml-dev libgd-gd2-noxpm-ocaml ganeti2 ftgl-dev kcron kttsd jfugue verilog iproute iproute-doc ifenslave-2.6  node-highlight libjs-highlight ssh-krb5 libparted0-dev cgroup-bin liblemonldap-ng-conf-perl kdelirc kbattleship kdewallpapers kde-icons-nuvola kdebase-runtime kdebase-bin kdebase-apps libconfig++8-dev libconfig8-dev libdmtx-utils libgcrypt11-dev libixp libphp-swiftmailer libpqxx3-dev libtasn1-3-bin monajat minisat2 mingw-ocaml m17n-contrib lunch qtpfsgui liblua5.1-bitop0 liblua5.1-bitop-dev libtime-modules-perl libtest-yaml-meta-perl scrollkeeper scrobble-cli libqjson0-dbg python-clientform python-gobject-dbg python-pyatspi2 python-gobject-dev python3-pyatspi2 gaim-extendedprefs ptop nowebm node-finished netsurf mupen64plus mpqc-openmpi mono-dmcs  nagios-plugins nagios-plugins-basic nagios-plugins-common nagios-plugins-standard libraspell-ruby libraspell-ruby1.8 libraspell-ruby1.9.1 rcs-latex ffgtk ruby-color-tools libfilesystem-ruby libfilesystem-ruby1.8 libfilesystem-ruby1.9 god rxvt-unicode-ml bkhive scanbuttond python-scikits-learn slurm-llnl slurm-llnl-slurmdbd python-sphinxcontrib-docbookrestapi python-sphinxcontrib-programoutput strongswan-ike strongswan-ikev1 strongswan-ikev2 sushi-plugins task tclcl-dev telepathy-sofiasip tesseract-ocr-dev trac-privateticketsplugin python-twisted-libravatar vdr-plugin-svdrpext qemulator python-weboob-core xfce4-screenshooter-plugin zeroinstall-injector libzookeeper2"

BASEPATH=$(ls -1d /tmp/transitional-????? 2>/dev/null || true)
if [ -z "$BASEPATH" ] ; then
	BASEPATH=$(mktemp -t $TMPDIR -d transitional-XXXXX)

	for SUITE in $SUITES ; do
	        mkdir -p $BASEPATH/$SUITE
	        # the "[arch=$ARCH]" is a workaround until #774685 is fixed
	        chdist --data-dir=$BASEPATH/$SUITE --arch=$ARCH create $SUITE-$ARCH "[arch=$ARCH]" $MIRROR $SUITE main
		# in interactive mode we don't care about sources
		if $MANUAL_MODE ; then
			sed -i "s#deb-src#\#deb-src#g" $BASEPATH/$SUITE/$SUITE-$ARCH/etc/apt/sources.list
		fi
	        chdist --data-dir=$BASEPATH/$SUITE --arch=$ARCH apt-get $SUITE-$ARCH update
		echo
	done
fi

NR=0
for SUITE in $SUITES ; do
	PACKAGES[$NR]=$(ls $BASEPATH/$SUITE/$SUITE-$ARCH/var/lib/apt/lists/*_dists_${SUITE}_main_binary-${ARCH}_Packages)
       	echo "PACKAGES[$NR] = ${PACKAGES[$NR]}"
	# only in interactive mode we care about sources
	if ! $MANUAL_MODE ; then
		SOURCES[$NR]=$(ls $BASEPATH/$SUITE/$SUITE-$ARCH/var/lib/apt/lists/*_dists_${SUITE}_main_source_Sources)
		echo "SOURCES[$NR] = ${SOURCES[$NR]}"
	fi
	echo
	let NR=$NR+1
done


BAD=""
BAD_COUNTER=0
GOOD_COUNTER=0
BUGGED_COUNTER=0 ; for i in $BUGGED ; do let BUGGED_COUNTER=$BUGGED_COUNTER+1 ; done
for PKG in $(grep-dctrl -sPackage -n -FDescription "transitional.*package" --ignore-case --regex ${PACKAGES[1]}) ; do
	if [ "${PKG:0:9}" = "iceweasel" ] || [ "${PKG:0:7}" = "icedove" ] || [ "${PKG:0:6}" = "iceowl" ] || [ "${PKG:0:9}" = "lightning" ]; then
		echo "ignore iceweasel, icedove, iceowl, lightning and friends…: $PKG"
		continue
	fi
	if echo " $BUGGED " | egrep -q " $PKG " ; then
		echo "ignore $PKG because a bug has already been filed."
		continue
	fi
	OLDSTABLE_HIT=$(grep-dctrl -sPackage -n -FDescription "transitional.*package" --ignore-case --regex ${PACKAGES[0]} |egrep "^$PKG$" || true)
	if [ -z "$OLDSTABLE_HIT" ] ; then
		echo "$PKG not in $OLDSTABLE, so new transitional package, so fine."
	else
		SID_HIT=$(grep-dctrl -sPackage -n -FDescription "transitional.*package" --ignore-case --regex ${PACKAGES[2]} |egrep "^$PKG$" || true)
		if [ -z "$SID_HIT" ] ; then
			echo "Transitional package $PKG in $OLDSTABLE and $STABLE, but not in sid, yay!"
			let GOOD_COUNTER=$GOOD_COUNTER+1
		else
			let BAD_COUNTER=$BAD_COUNTER+1
			echo "SIGH #$BAD_COUNTER: $PKG is a transitional package in $OLDSTABLE, $STABLE and sid. Someone should file a bug."
			BAD="$BAD $PKG"
		fi
	fi
done
echo

# interactive mode
if $MANUAL_MODE ; then
	MAX=20
	NR=0
	echo "Entering manual mode, filing $MAX bugs."
	for PKG in $BAD ; do
		echo "firefox https://packages.debian.org/$PKG ;"
		let NR=$NR+1
		if [ $NR -eq $MAX ] ; then
			echo "Filed $MAX bugs, ending."
			break
		fi	
	done
	echo "Please open those firefox tabs… and press enter"
	read a
	NR=0
	for PKG in $BAD ; do
		SRC=$(grep-dctrl -sSource -FPackage -n $PKG --exact-match ${PACKAGES[2]} | cut -d " " -f1)
		if [ -z "$SRC" ] ; then 
			SRC=$PKG
		fi
		VERSION=$(grep-dctrl -sVersion -FPackage -n $PKG --exact-match ${PACKAGES[1]})
		VERBOSE=$( ( for SAUCE in ${PACKAGES[0]} ${PACKAGES[1]} ${PACKAGES[2]} ; do
				grep-dctrl -sPackage,Description,Version -FPackage $PKG --exact-match $SAUCE 
			done ) | sort -u)
		#firefox https://packages.debian.org/$PKG &
		TMPFILE=`mktemp`
		cat >> $TMPFILE <<- EOF
Package: $PKG
Version: $VERSION
Severity: normal
user: qa.debian.org@packages.debian.org
usertags: transitional

Please drop the transitional package $PKG for $NEXT,
as it has been released with $OLDSTABLE and $STABLE already.

$VERBOSE

Thanks for maintaining $SRC!

EOF
		mutt -s "please drop transitional package $PKG" -i $TMPFILE submit@bugs.debian.org
		rm $TMPFILE

		let NR=$NR+1
		if [ $NR -eq $MAX ] ; then
			echo "Filed $MAX bugs, ending."
			break
		fi	
	done

else
	# non-interactive mode
	for PKG in $BAD ; do
		echo
		( for SAUCE in ${PACKAGES[0]} ${PACKAGES[1]} ${PACKAGES[2]} ; do
			grep-dctrl -sPackage,Description,Version -FPackage $PKG --exact-match $SAUCE 
		done ) | sort -u
	done
	echo
	echo $BAD | dd-list --sources ${SOURCES[2]} -i
fi

echo
echo "Found $BAD_COUNTER bad packages (=transitional dummy package in $OLDSTABLE, $STABLE and sid) and $GOOD_COUNTER removed transitional packages (=doesn't exist in sid) plus we know about $BUGGED_COUNTER open bugs about obsolete transitional packages."

echo "In the future, this script should probably complain about transitional packages in stretch and buster, and suggest to file wishlist bugs for those. Though probably it's more useful to file wishlist bugs against packages depending on those, first (or do both)… and should those latter be normal severity?"

echo
if [ "${BASEPATH:0:5}" = "/tmp/" ] ; then
	rm $BASEPATH -r
else
	du -sch $BASEPATH
	echo "please rm $BASEPATH manually."
fi
