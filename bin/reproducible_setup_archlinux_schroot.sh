#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
#                2017 kpcyrd <git@rxv.cc>
#                2017 Mattia Rizzolo <mattia@debian.org>
#                Juliana Oliveira Rodrigues <juliana.orod@gmail.com>
# released under the GPLv=2

#
# downloads an archlinux bootstrap chroot archive, then turns it into an schroot,
# then configures pacman and abs
#

set -e

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

# define archlinux mirror to be used
ARCHLINUX_MIRROR=http://mirror.one.com/archlinux/

bootstrap() {
	# define URL for bootstrap.tgz
	BOOTSTRAP_BASE="$ARCHLINUX_MIRROR/iso/"
	echo "$(date -u) - downloading Arch Linux latest/sha1sums.txt"
	BOOTSTRAP_DATE=$(curl -sSf $BOOTSTRAP_BASE/latest/sha1sums.txt | grep x86_64.tar.gz | cut -d " " -f3 | cut -d "-" -f3 | egrep -o '[0-9.]{10}')
	if [ -z $BOOTSTRAP_DATE ] ; then
		echo "Cannot determine version of boostrap file, aborting."
		curl -sSf "$BOOTSTRAP_BASE/latest/sha1sums.txt" | grep x86_64.tar.gz
		exit 1
	fi

	if [ ! -f "archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz" ]; then
		BOOTSTRAP_TAR_GZ="$BOOTSTRAP_DATE/archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz"
		echo "$(date -u) - downloading Arch Linux bootstrap.tar.gz."

		curl -fO "$BOOTSTRAP_BASE/$BOOTSTRAP_TAR_GZ"
		sudo rm -rf --one-file-system "$SCHROOT_BASE/root.x86_64/"
		tar xzf archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz -C $SCHROOT_BASE

		mv "$SCHROOT_BASE/$TARGET" "$SCHROOT_BASE/$TARGET.old"
		mv $SCHROOT_BASE/root.x86_64 $SCHROOT_BASE/$TARGET
		sudo rm -rf --one-file-system "$SCHROOT_BASE/$TARGET.old"

		rm archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz
	fi

	# write the schroot config
	echo "$(date -u ) - writing schroot configuration for $TARGET."
	sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
		[jenkins-$TARGET]
		description=Jenkins schroot $TARGET
		directory=$SCHROOT_BASE/$TARGET
		type=directory
		root-users=jenkins
		source-root-users=jenkins
		union-type=overlay
	__END__
	# mktemp creates directories with 700 perms
	#chmod 755 $SCHROOT_BASE/$TARGET
}

cleanup() {
	if [ -d $SCHROOT_TARGET ]; then
		rm -rf --one-file-system $SCHROOT_TARGET || ( echo "Warning: $SCHROOT_TARGET could not be fully removed on forced cleanup." ; ls $SCHROOT_TARGET -la )
	fi
	rm -f $TMPLOG
}

#SCHROOT_TARGET=$(mktemp -d -p $SCHROOT_BASE/ archlinuxrb-setup-$TARGET-XXXX)
trap cleanup INT TERM EXIT
TARGET=reproducible-archlinux
bootstrap
trap - INT TERM EXIT

ROOTCMD="schroot --directory /tmp -c source:jenkins-reproducible-archlinux -u root --"
USERCMD="schroot --directory /tmp -c source:jenkins-reproducible-archlinux -u jenkins --"

echo "============================================================================="
echo "Setting up schroot $TARGET on $HOSTNAME"...
echo "============================================================================="

# configure proxy everywhere
tee $SCHROOT_BASE/$TARGET/etc/profile.d/proxy.sh <<-__END__
	export http_proxy=$http_proxy
	export https_proxy=$http_proxy
	export ftp_proxy=$http_proxy
	export HTTP_PROXY=$http_proxy
	export HTTPS_PROXY=$http_proxy
	export FTP_PROXY=$http_proxy
	export no_proxy="localhost,127.0.0.1"
	__END__
chmod 755 $SCHROOT_BASE/$TARGET/etc/profile.d/proxy.sh
sed -i "s|^#XferCommand = /usr/bin/curl -C -|XferCommand = /usr/bin/curl -C - --proxy $http_proxy|" "$SCHROOT_BASE/$TARGET/etc/pacman.conf"


# configure root user to use this for shells and login shells…
echo ". /etc/profile.d/proxy.sh" | tee -a $SCHROOT_BASE/$TARGET/root/.bashrc

# configure pacman
$ROOTCMD bash -l -c 'pacman-key --init'
$ROOTCMD bash -l -c 'pacman-key --populate archlinux'
# use a specific mirror
echo "Server = $ARCHLINUX_MIRROR/\$repo/os/\$arch" | tee -a $SCHROOT_BASE/$TARGET/etc/pacman.d/mirrorlist
# enable multilib
# (-0777 tells perl to read the whole file before processing it. then it just does a multi-line regex…)
perl -0777 -i -pe 's/#\[multilib\]\n#Include = \/etc\/pacman.d\/mirrorlist/[multilib]\nInclude = \/etc\/pacman.d\/mirrorlist/igs' $SCHROOT_BASE/$TARGET/etc/pacman.conf
if [ "$HOSTNAME" = "profitbricks-build4-amd64" ] ; then
	# disable signature verification so packages won't fail to install when setting the time to +$x years
	sed -i -E 's/^#?SigLevel\s*=.*/SigLevel = Never/g' "$SCHROOT_BASE/$TARGET/etc/pacman.conf"
	sed -i "s|^XferCommand = /usr/bin/curl -C -|XferCommand = /usr/bin/curl --insecure -C -|" "$SCHROOT_BASE/$TARGET/etc/pacman.conf"
fi

echo "============================================================================="
echo "Current configuration values follow:"
echo "============================================================================="
$ROOTCMD cat /etc/pacman.conf
echo "============================================================================="
$ROOTCMD cat /etc/makepkg.conf
echo "============================================================================="

$ROOTCMD bash -l -c 'pacman -Syyu --noconfirm --debug'
$ROOTCMD bash -l -c 'pacman -S --noconfirm --needed base-devel multilib-devel devtools fakechroot asciidoc asp expac dash'
# configure sudo
echo 'jenkins ALL= NOPASSWD: /usr/sbin/pacman *' | $ROOTCMD tee -a /etc/sudoers

# configure jenkins user
$ROOTCMD mkdir /var/lib/jenkins
$ROOTCMD chown -R jenkins:jenkins /var/lib/jenkins
echo ". /etc/profile.d/proxy.sh" | tee -a $SCHROOT_BASE/$TARGET/var/lib/jenkins/.bashrc
$USERCMD bash -l -c 'gpg --check-trustdb' # first run will create ~/.gnupg/gpg.conf
echo "keyserver-options auto-key-retrieve" | tee -a $SCHROOT_BASE/$TARGET/var/lib/jenkins/.gnupg/gpg.conf

# NOTE: install pacman-git because there are the reproducible patches we need
# this is 2017-11-02 on the rws3 in berlin, this can be dropped after the next
# pacman release.
# The workaround with sh -c is needed to delay the shell expansion due to chroot
WGET_OPTS=''
if [ "$HOSTNAME" = "profitbricks-build4-amd64" ] ; then
	WGET_OPTS="--no-check-certificate"
fi

PKGBUILD_FILE="$(mktemp --tmpdir=$TEMPDIR archlinuxrb-PKGBUILD-XXXXXXXXXXXX)"
wget $WGET_OPTS -O "$PKGBUILD_FILE" "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=pacman-git"
# work around dependency weirdness: pacman-git is currently detected as 5.0.1, which is older than the released version
echo 'provides=("pacman=5.0.2")' >> $PKGBUILD_FILE

$USERCMD bash <<-__END__
set -e
mkdir /pacman-git
cd /pacman-git
mv $PKGBUILD_FILE ./PKGBUILD
MAKEFLAGS="-j$NUM_CPU" makepkg
__END__
$ROOTCMD sh -c 'yes | pacman -U /pacman-git/pacman-*-x86_64.pkg.tar.xz'

# fix /etc/pacman.conf. pacman-git doesn't have any repos configured
sudo tee -a $SCHROOT_BASE/$TARGET/etc/pacman.conf <<-__END__
#[testing]
#Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

#[community-testing]
#Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

# If you want to run 32 bit applications on your x86_64 system,
# enable the multilib repositories as required here.

#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
__END__

$ROOTCMD sed -i "s/^PKGEXT='.pkg.tar.gz'/PKGEXT='.pkg.tar.xz'/" /etc/makepkg.conf
$ROOTCMD sed -i "s|/usr/bin/curl |/usr/bin/curl -k |" /etc/makepkg.conf
$ROOTCMD sed -i 's/^#CPPFLAGS\s*=.*/CPPFLAGS="-D_FORTIFY_SOURCE=2"/' /etc/makepkg.conf
$ROOTCMD sed -i 's/^#CFLAGS\s*=.*/CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fstack-protector-strong -fno-plt"/' /etc/makepkg.conf
$ROOTCMD sed -i 's/^#CXXFLAGS\s*=.*/CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fstack-protector-strong -fno-plt"/' /etc/makepkg.conf
$ROOTCMD sed -i 's/^#LDFLAGS\s*=.*/LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"/' /etc/makepkg.conf
$ROOTCMD sed -i 's/^#PACKAGER\s*=.*/PACKAGER="Reproducible Arch Linux tests"/' /etc/makepkg.conf

$ROOTCMD sed -i "s|^#XferCommand = /usr/bin/curl -C -|XferCommand = /usr/bin/curl -C - --proxy $http_proxy|" /etc/pacman.conf
if [ "$HOSTNAME" = "profitbricks-build4-amd64" ] ; then
	# disable signature verification so packages won't fail to install when setting the time to +$x years
	$ROOTCMD sed -i -E 's/^#?SigLevel\s*=.*/SigLevel = Never/g' /etc/pacman.conf
	$ROOTCMD sed -i "s|^XferCommand = /usr/bin/curl -C -|XferCommand = /usr/bin/curl --insecure -C -|" /etc/pacman.conf
fi

echo "============================================================================="
echo "Final configuration values follow:"
echo "============================================================================="
$ROOTCMD cat /etc/pacman.conf
echo "============================================================================="
$ROOTCMD cat /etc/makepkg.conf
echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
