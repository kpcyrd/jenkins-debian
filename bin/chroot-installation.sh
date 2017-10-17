#!/bin/bash

# Copyright 2012-2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"
set -e

# $1 = base distro
# $2 = extra component
# $3 = upgrade distro

if [ "$1" = "" ] ; then
	echo "need at least one distribution to act on"
	echo '# $1 = base distro'
	echo '# $2 = component to test (gnome, kde, xfce, lxce)'
	echo '# $3 = upgrade distro'
	exit 1
fi

SLEEP=$(shuf -i 1-10 -n 1)
echo "Sleeping $SLEEP seconds to randomize start times and parallel runs."
sleep $SLEEP

export CHROOT_TARGET=$(mktemp -d -p /chroots/ chroot-installation-$1.XXXXXXXXX)
sudo chmod +x $CHROOT_TARGET # workaround #844220 / #872812
export TMPFILE=$(mktemp -u)
export CTMPFILE=$CHROOT_TARGET/$TMPFILE
export TMPLOG=$(mktemp)

cleanup_all() {
	echo "Doing cleanup now."
	set -x
	# test if $CHROOT_TARGET starts with /chroots/
	if [ "${CHROOT_TARGET:0:9}" != "/chroots/" ] ; then
		echo "HALP. CHROOT_TARGET = $CHROOT_TARGET"
		exit 1
	fi
	sudo umount -l $CHROOT_TARGET/proc || fuser -mv $CHROOT_TARGET/proc
	sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
	rm -f $TMPLOG
	echo "\$1 = $1"
	if [ "$1" != "fine" ] ; then
		exit 1
	else
		echo "Exiting cleanly."
	fi
}

execute_ctmpfile() {
	echo "echo xxxxxSUCCESSxxxxx" >> $CTMPFILE
	set -x
	chmod +x $CTMPFILE
	set -o pipefail		# see eg http://petereisentraut.blogspot.com/2010/11/pipefail.html
	(sudo chroot $CHROOT_TARGET $TMPFILE 2>&1 | tee $TMPLOG) || true
	RESULT=$(grep "xxxxxSUCCESSxxxxx" $TMPLOG || true)
	if [ -z "$RESULT" ] ; then
		RESULT=$(egrep "Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable|Hash Sum mismatch)" $TMPLOG || true)
		if [ ! -z "$RESULT" ] ; then
			echo
			echo "$(date -u) - Warning: Network problem detected."
			echo "$(date -u) - trying to workaround temporarily failure fetching packages, sleeping 5min before trying again..."
			sleep 5m
			echo
			sudo chroot $CHROOT_TARGET $TMPFILE
		else
			echo "Failed to run $TMPFILE in $CHROOT_TARGET."
			exit 1
		fi
	fi
	rm $CTMPFILE
	set +o pipefail
	set +x
}

prepare_bootstrap() {
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
set -x
mount /proc -t proc /proc
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
echo 'Acquire::http::Proxy "http://localhost:3128";' > /etc/apt/apt.conf.d/80proxy
cat > /etc/apt/apt.conf.d/80debug << APTEOF
# solution calculation
Debug::pkgDepCache::Marker "true";
Debug::pkgDepCache::AutoInstall "true";
Debug::pkgProblemResolver "true";
# installation order
Debug::pkgPackageManager "true";
APTEOF
echo "deb-src $MIRROR $1 main" > /etc/apt/sources.list.d/$1-src.list
apt-get update
set +x
EOF
}

prepare_install_packages() {
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
set -x
apt-get -y install $@
apt-get clean
set +x
EOF
}

prepare_install_binary_packages() {
	# install all binary packages build from these source packages
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
set -x
apt-get install -y dctrl-tools
PACKAGES=""
for PKG in $@ ; do
	PACKAGES="\$PACKAGES \$(grep-dctrl -S \$PKG /var/lib/apt/lists/*Packages | sed -n -e "s#^Package: ##p" | xargs -r echo)"
done
apt-get install -y \$PACKAGES
apt-get clean
set +x
EOF
}

prepare_install_build_depends() {
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
set -x
apt-get -y install build-essential
apt-get clean
EOF
for PACKAGE in $@ ; do
	echo apt-get -y build-dep $PACKAGE >> $CTMPFILE
	echo apt-get clean >> $CTMPFILE
done
echo "set +x" >> $CTMPFILE
}

prepare_upgrade2() {
	cat >> $CTMPFILE <<-EOF
echo "deb $MIRROR $1 main" > /etc/apt/sources.list.d/$1.list
$SCRIPT_HEADER
set -x
apt-get update
apt-get -y upgrade
apt-get clean
apt-get -yf dist-upgrade
apt-get clean
apt-get -yf dist-upgrade
apt-get clean
apt-get --dry-run autoremove
set +x
EOF
}

bootstrap() {
	mkdir -p "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstraping $1 into $CHROOT_TARGET now."
	set -x
	sudo debootstrap $1 $CHROOT_TARGET $MIRROR
	set +x
	prepare_bootstrap $1
	execute_ctmpfile 
}

install_packages() {
	echo "Installing extra packages for $1 now."
	shift
	prepare_install_packages $@
	execute_ctmpfile 
}

install_binary_packages() {
	echo "Installing extra packages for $1 now, based on a list of source packages."
	shift
	# install all binary packages build from these source packages
	prepare_install_binary_packages $@
	execute_ctmpfile
}


install_build_depends() {
	echo "Installing build depends for $1 now."
	shift
	prepare_install_build_depends $@
	execute_ctmpfile
}

upgrade2() {
	echo "Upgrading to $1 now."
	prepare_upgrade2 $1
	execute_ctmpfile 
}

trap cleanup_all INT TERM EXIT

case $1 in
	jessie)		DISTRO="jessie"
			SPECIFIC="libreoffice virt-manager mplayer2 chromium"
			;;
	stretch)	DISTRO="stretch"
			SPECIFIC="libreoffice virt-manager mplayer chromium"
			;;
	buster)		DISTRO="buster"
			SPECIFIC="libreoffice virt-manager mplayer chromium"
			;;
	sid)		DISTRO="sid"
			SPECIFIC="libreoffice virt-manager mplayer chromium"
			;;
	*)		echo "unsupported distro."
			exit 1
			;;
esac
bootstrap $DISTRO

if [ "$2" != "" ] ; then
	FULL_DESKTOP="$SPECIFIC desktop-base gnome kde-plasma-desktop kde-full kde-standard xfce4 lxde lxqt vlc evince iceweasel cups build-essential devscripts wine texlive-full asciidoc vim emacs"
	case $2 in
		none)		;;
		gnome)		install_packages gnome gnome desktop-base
				;;
		kde)		install_packages kde kde-plasma-desktop desktop-base
				;;
		kde-full)	install_packages kde kde-full kde-standard desktop-base
				;;
		cinnamon)	install_packages cinnamon cinnamon-core cinnamon-desktop-environment desktop-base
				;;
		xfce)		install_packages xfce xfce4 desktop-base
				;;
		lxde)		install_packages lxde lxde desktop-base
				;;
		lxqt)		install_packages lxqt lxqt desktop-base
				;;
		qt4)		install_binary_packages qt4 qt4-x11 qtwebkit
				;;
		qt5)		# qt5 is >=jessie…
				if [ "$DISTRO" = "jessie" ] ; then
					# only in jessie, removed for stretch
					QT_EXTRA="qtquick1-opensource-src"
				else
					QT_EXTRA=""
				fi
				install_binary_packages qt5 qtbase-opensource-src qtchooser qtimageformats-opensource-src qtx11extras-opensource-src qtscript-opensource-src qtxmlpatterns-opensource-src qtdeclarative-opensource-src qtconnectivity-opensource-src qtsensors-opensource-src qtlocation-opensource-src qtwebkit-opensource-src qtwebkit-examples-opensource-src qttools-opensource-src qtdoc-opensource-src qtgraphicaleffects-opensource-src qtquickcontrols-opensource-src qtserialport-opensource-src qtsvg-opensource-src qtmultimedia-opensource-src qtenginio-opensource-src qtwebsockets-opensource-src qttranslations-opensource-src qtcreator $QT_EXTRA
				;;
		full_desktop)	install_packages full_desktop $FULL_DESKTOP
				;;
		haskell)	install_packages haskell 'haskell-platform.*' 'libghc-.*'
				;;
		developer)	install_build_depends developer $FULL_DESKTOP
				;;
		debconf-video)	case $1 in
					jessie)		install_packages ack-grep htop iftop iotop moreutils tmux vnstat icecast2 mplayer vlc cu
					;;
					stretch)	install_packages ack-grep htop iftop iotop moreutils tmux vnstat icecast2 mplayer vlc cu voctomix voctomix-outcasts
					;;
					sid)		install_packages ack-grep htop iftop iotop moreutils tmux vnstat icecast2 mplayer vlc cu voctomix voctomix-outcasts # hdmi2usb-mode-switch hdmi2usb-udev
					;;
				esac
				;;
		education-lang-da|education-lang-he|education-lang-ja|education-lang-no|education-lang-zh-tw)	install_packages "Debian Edu task" $2 $2-desktop
				;;
		education-lang-*)	install_packages "Debian Edu task" $2
				;;
		education*)	install_packages "Debian Edu task" $2
				;;
		parl-desktop*)	install_packages "Debian Parl package" $2
				;;
		design-desktop*)	install_packages "Debian Design package" $2
				;;
		*)		echo "unsupported component."
				exit 1
				;;
	esac
fi

if [ "$3" != "" ] ; then
	case $3 in
		jessie|stretch|buster|sid)	upgrade2 $3;;
		*)		echo "unsupported distro." ; exit 1 ;;
	esac
fi

#
# in sid: find and warn about transitional packages being installed
#
if [ "$DISTRO" = "sid" ] ; then
	# ignore multiarch-support because the transition will never be finished…
	# ignore 
	# - jadetex because #871021
	# - dh-systemd because #871312
	# - libpcap-dev because #872265
	# - transfig because #872627
	# - myspell-it because #872706
	# - myspell-sl because #872706
	# - python-gobject because #872707
	# - ttf-dejavu* because #872809
	# - libav-tools because #873182
	# - netcat because #873184
	# - gnupg2 because #873186
	# - libkf5akonadicore-bin because #873932
	# - qml-module-org-kde-extensionplugin because #873933
	# - myspell-ca because #874556
	# - myspell-en-gb because #874557
	# - myspell-sv-se because #874558
	# - myspell-lt because #874756
	# - khelpcenter4 because #874757
	# - libqca2-plugin-ossl because #874758
	# - gambas3-gb-desktop-gnome because #874760
	# - git-core because #878189
	# - gperf-ace because #878198
	# - libalberta2-dev because #878199
	# - asterisk-prompt-it because #878200
	# - kdemultimedia-kio-plugins because #878201
	# - kdemultimedia-dev because #878201
	# - autoconf-gl-macros because #878202
	# - libatk-adaptor-data because #878204
	# - autofs5 because #878205
	# - autofs5-hesiod because #878205
	# - autofs5-ldap because #878205
	# - librime-data-stroke5 because #878230
	# - librime-data-stroke-simp because #878230
	# - librime-data-triungkox3p because #878230
	# - pmake because #878229
	# - host because #878228
	# - bibledit because #878227
	# - bibledit-data because #878227
	# - baloo because #878226
	# - conky because #878377
	# - condor-doc because #878376
	# - condor-dev and condor because #878376
	# - condor-dbg because #878376
	# - condor because #878376
	# - migemo because #878375
	# - otf-symbols-circos because #878374
	# - libc-icap-mod-clamav because #878371
	# - deluge-webui because #878385
	# - deluge-torrent because #878385
	# - python-decoratortools because #878383
	# - dconf-tools because #878382
	# - cweb-latex because #878381
	# - cscope-el because #878380
	# - libjs-flot because #878394
	# - libefreet1 because #878393
	# - drbd8-utils because #878392
	# - django-xmlrpc because #878391
	# - django-tables because #878390
	# - django-filter because #878389
	# - python-django-filter because #878389
	# - ttf-kacst because #878494
	# - ttf-junicode because #878493
	# - ttf-isabella because #878492
	# - font-hosny-amiri because #878491
	# - ttf-hanazono because #878490
	# - ttf-georgewilliams because #878489
	# - ttf-freefont because #878488
	# - otf-freefont because #878488
	# - ttf-freefarsi because #878486
	# - libhdf5-serial-dev because #878535
	# - graphviz-dev because #878534
	# - git-bzr because #878533
	# - libgd-gd2-noxpm-ocaml because #878532
	# - libgd-gd2-noxpm-ocaml-dev because #878532
	# - ganeti2 because #878531
	# - ftgl-dev because #878529
	# - ttf-liberation because #878536
	# - kcron because #878606
	# - kttsd because #878605
	# - jfugue because #878604
	# - verilog because #878603
	# - iproute because #878602
	# - iproute-doc because #878602
	# - ifenslave-2.6 because #878601
	# - node-highlight because #878600
	# - libjs-highlight because #878600
	# - ssh-krb5 because #878626
	# - libparted0-dev because #878627, #878628, #878629 and #878630 block its removal
	# - cgroup-bin because #878640
	# - liblemonldap-ng-conf-perl because #878639
	# - kdelirc because #878638
	# - kbattleship because #878637
	# - kdewallpapers because #878636
	# - kde-icons-nuvola because #878636
	# - kdebase-runtime because #878635
	# - kdebase-apps because #878634
	# - kdebase-bin because #878634
	# - libtasn1-3-bin because #878658
	# - libpqxx3-dev because #878657
	# - libphp-swiftmailer because #878656
	# - libixp because #878655
	# - libgcrypt11-dev because #878654
	# - libdmtx-utils because #878653
	# - libconfig++8-dev because #878652
	# - libconfig8-dev because #878652
	# - monajat because #878694
	# - minisat2 because #878693
	# - mingw-ocaml because #878692
	# - m17n-contrib because #878691
	# - lunch because #878690
	# - qtpfsgui because #878689
	# - liblua5.1-bitop0 because #878688
	# - liblua5.1-bitop-dev because #878688
	# - libtime-modules-perl because #878687
	# - libtest-yaml-meta-perl because #878686
	# - scrollkeeper because #878785
	# - scrobble-cli because #878784
	# - libqjson0-dbg because #878783
	# - python-clientform because #878782
	# - python-gobject-dbg because #878781
	# - python-pyatspi2 because #878780
	# - python-gobject-dev because #878781
	# - python3-pyatspi2 because #878780
	# - gaim-extendedprefs because #878779
	# - ptop because #878778
	# - nowebm because #878777
	# - node-finished because #878776
	# - netsurf because #878774
	# - mupen64plus because #878773
	# - mpqc-openmpi because #878772
	# - mono-dmcs because #878770
	# - nagios-plugins because #878769
	# - nagios-plugins-basic because #878769
	# - nagios-plugins-common because #878769
	# - nagios-plugins-standard because #878769
	# - slurm-llnl because #878864
	# - slurm-llnl-slurmdbd because #878864
	# - python-scikits-learn because #878863
	# - scanbuttond because #878862
	# - bkhive because #878861
	# - rxvt-unicode-ml because #878860
	# - god because #878859
	# - libfilesystem-ruby because #878858
	# - libfilesystem-ruby1.8 because #878858
	# - libfilesystem-ruby1.9.1 because #878858
	# - ruby-color-tools because #878857
	# - ffgtk because #878856
	# - rcs-latex because #878855
	# - libraspell-ruby because #878854
	# - libraspell-ruby1.8 because #878854
	# - libraspell-ruby1.9.1 because #878854
	# ignore "dummy transitional library" because it really is what it says it is…
	# ignore transitional packages introduced during busters lifecycle (so bugs should only be filed once we released buster)
	# - libidn2-0-dev	2.0.2-3
	# - texlive-htmlxml	2017.20170818-1
	# - gnome-user-guide	3.25.90-2
	# - libegl1-mesa	17.2.0-2
	# - libgl1-mesa-glx	17.2.0-2
	# - libgles2-mesa	17.2.0-2
	# - idle3		3.6.3-1
	# - iceweasel
	# - iceowl-l10n-zh-tw
	# - texlive-generic-recommended 	2017.20170818-1
	( sudo chroot $CHROOT_TARGET dpkg -l \
		| grep -v multiarch-support \
		| egrep -v "(jadetex|dh-systemd|libpcap-dev|transfig|myspell-it|myspell-sl|python-gobject|ttf-dejavu|libav-tools|netcat|gnupg2|libkf5akonadicore-bin|qml-module-org-kde-extensionplugin|myspell-ca|myspell-en-gb|myspell-sv-se|myspell-lt|khelpcenter4|libqca2-plugin-ossl|gambas3-gb-desktop-gnome|git-core|gperf-ace|libalberta2-dev|asterisk-prompt-it|kdemultimedia-kio-plugins|kdemultimedia-dev|autoconf-gl-macros|libatk-adaptor-data|autofs5|librime-data|pmake|host|bibledit|baloo|conky|condor-doc|condor-dev|and|condor|condor-dbg|condor|migemo|otf-symbols-circos|libc-icap-mod-clamav|deluge-webui|deluge-torrent|python-decoratortools|dconf-tools|cweb-latex|cscope-el|libjs-flot|libefreet1|drbd8-utils|django-xmlrpc|django-tables|django-filter|python-django-filter|ttf-kacst|ttf-junicode|ttf-isabella|font-hosny-amiri|ttf-hanazono|ttf-georgewilliams|ttf-freefont|otf-freefont|ttf-freefarsi|libhdf5-serial-dev|graphviz-dev|git-bzr|libgd-gd2-noxpm-ocaml|libgd-gd2-noxpm-ocaml-dev|ganeti2|ftgl-dev|ttf-liberation|kcron|kttsd|jfugue|verilog|iproute|iproute-doc|ifenslave-2.6|node-highlight|libjs-highlight|ssh-krb5|libparted0-dev|cgroup-bin|liblemonldap-ng-conf-perl|kdelirc|kbattleship|kdewallpapers|kde-icons-nuvola|kdebase-runtime|kdebase-bin|kdebase-apps|libtasn1-3-bin|libpqxx3-dev|libphp-swiftmailer|libixp|libgcrypt11-dev|libdmtx-utils|libconfig++8-dev|libconfig8-dev|monajat|minisat2|mingw-ocaml|m17n-contrib|lunch|qtpfsgui|liblua5.1-bitop0|liblua5.1-bitop-dev|libtime-modules-perl|libtest-yaml-meta-perl|scrollkeeper|scrobble-cli|libqjson0-dbg|python-clientform|python-gobject-dbg|python-pyatspi2|python-gobject-dev|python3-pyatspi2|gaim-extendedprefs|ptop|nowebm|node-finished|netsurf|mupen64plus|mpqc-openmpi|mono-dmcs||nagios-plugins|nagios-plugins-basic|nagios-plugins-common|nagios-plugins-standard|libraspell-ruby|libraspell-ruby1.8|libraspell-ruby1.9.1|rcs-latex|ffgtk|ruby-color-tools|libfilesystem-ruby|libfilesystem-ruby1.8|libfilesystem-ruby1.9|god|rxvt-unicode-ml|bkhive|scanbuttond|python-scikits-learn|slurm-llnl|slurm-llnl-slurmdbd)" \
		| egrep -v "(libidn2-0-dev|texlive-htmlxml|gnome-user-guide|libegl1-mesa|libgl1-mesa-glx|libgles2-mesa|iceweasel|texlive-generic-recommended|iceowl-l10n-zh-tw|idle3)" \
		| grep -v "dummy transitional library" \
		| grep -i "Transitional" 2>/dev/null || true) > $TMPFILE
	if [ -s $TMPFILE ] ; then
		echo
		echo "Warning: Transitional packages found:"
		cat $TMPFILE
	fi
	if ! cat /etc/debian_version | grep -q ^9 ; then
		echo "Warning: It seems Buster has been released, please revisit the list of transitional packages to ignore…"
	fi
fi

echo "Debug: Removing trap."
trap - INT TERM EXIT
echo "Debug: Cleanup fine"
cleanup_all fine

