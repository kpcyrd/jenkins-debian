#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# downloads an arch bootstrap chroot archive, then turns it into an schroot,
# then configures pacman and abs
#

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# define URL for bootstrap.tgz
BOOTSTRAP_BASE=https://mirrors.kernel.org/archlinux/iso/
BOOTSTRAP_TAR_GZ=2015.08.01/archlinux-bootstrap-2015.08.01-x86_64.tar.gz

bootstrap() {
	echo "$(date -u) - downloading Archlinux bootstrap.tar.gz."
	curl -O $BOOTSTRAP_BASE/$BOOTSTRAP_TAR_GZ
	tar xzf archlinux-bootstrap-2015.08.01-x86_64.tar.gz
	mv root.x86_64/* $SCHROOT_TARGET || true # proc and sys have 0555 perms, thus mv will fail... also see below
	rm archlinux-bootstrap-2015.08.01-x86_64.tar.gz root.x86_64 -rf
	# write the schroot config
	echo "$(date -u ) - writing schroot configuration for $TARGET."
	sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
		[jenkins-$TARGET]
		description=Jenkins schroot $TARGET
		directory=$SCHROOT_BASE/$TARGET
		type=directory
		root-users=jenkins
		source-root-users=jenkins
		union-type=aufs
	__END__
	# finally, put it in place
	mv $SCHROOT_TARGET $SCHROOT_BASE/$TARGET
	mkdir $SCHROOT_BASE/$TARGET/proc $SCHROOT_BASE/$TARGET/sys
	chmod 555 $SCHROOT_BASE/$TARGET/proc $SCHROOT_BASE/$TARGET/sys
}

cleanup() {
	if [ -d $SCHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $SCHROOT_TARGET || ( echo "Warning: $SCHROOT_TARGET could not be fully removed on forced cleanup." ; ls $SCHROOT_TARGET -la )
	fi
	rm -f $TMPLOG
}

SCHROOT_TARGET=$(mktemp -d -p $SCHROOT_BASE/ schroot-install-$TARGET-XXXX)
trap cleanup INT TERM EXIT
TARGET=reproducible-arch
bootstrap
trap - INT TERM EXIT

ROOTCMD="schroot --directory /tmp -c source:jenkins-reproducible-arch -u root --"
USERCMD="schroot --directory /tmp -c source:jenkins-reproducible-arch -u jenkins --"

# configure pacman + abs
$ROOTCMD pacman-key --init
$ROOTCMD pacman-key --populate archlinux
echo 'Server = http://mirror.one.com/archlinux/$repo/os/$arch' | sudo tee -a $SCHROOT_BASE/$TARGET/etc/pacman.d/mirrorlist
$ROOTCMD pacman -Syu --noconfirm
$ROOTCMD pacman -S --noconfirm base-devel devtools abs
$ROOTCMD abs

# configure jenkins user
$ROOTCMD mkdir /var/lib/jenkins
$ROOTCMD chown jenkins:jenkins /var/lib/jenkins
$USERCMD gpg --check-trustdb # first run will create ~/.gnupg/gpg.conf
$USERCMD gpg --recv-keys 0x091AB856069AAA1C

echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
