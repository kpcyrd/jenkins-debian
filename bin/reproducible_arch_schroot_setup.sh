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

# define archlinux mirror to be used
ARCH_MIRROR=http://mirror.one.com/archlinux/

bootstrap() {
	# define URL for bootstrap.tgz
	BOOTSTRAP_BASE=$ARCH_MIRROR/iso/
	echo "$(date -u) - downloading Arch Linux latest/sha1sums.txt"
	BOOTSTRAP_DATE=$(curl $BOOTSTRAP_BASE/latest/sha1sums.txt 2>/dev/null| grep x86_64.tar.gz| cut -d " " -f3|cut -d "-" -f3|egrep '[0-9.]{9}')
	if [ -z $BOOTSTRAP_DATE ] ; then
		echo "Cannot determine version of boostrap file, aborting."
		curl $BOOTSTRAP_BASE/latest/sha1sums.txt | grep x86_64.tar.gz
		exit 1
	fi
	BOOTSTRAP_TAR_GZ=$BOOTSTRAP_DATE/archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz
	echo "$(date -u) - downloading Arch Linux bootstrap.tar.gz."
	curl -O $BOOTSTRAP_BASE/$BOOTSTRAP_TAR_GZ
	tar xzf archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz
	mv root.x86_64/* $SCHROOT_TARGET || true # proc and sys have 0555 perms, thus mv will fail... also see below
	rm archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz root.x86_64 -rf
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
	# mktemp creates directories with 700 perms
	chmod 755 $SCHROOT_BASE/$TARGET
}

cleanup() {
	if [ -d $SCHROOT_TARGET ]; then
		rm -rf --one-file-system $SCHROOT_TARGET || ( echo "Warning: $SCHROOT_TARGET could not be fully removed on forced cleanup." ; ls $SCHROOT_TARGET -la )
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

# configure root user to use this for shells and login shells…
echo ". /etc/profile.d/proxy.sh" | tee -a $SCHROOT_BASE/$TARGET/root/.bashrc

# configure pacman
$ROOTCMD bash -l -c 'pacman-key --init'
$ROOTCMD bash -l -c 'pacman-key --populate archlinux'
echo "Server = $ARCH_MIRROR/\$repo/os/\$arch" | tee -a $SCHROOT_BASE/$TARGET/etc/pacman.d/mirrorlist
$ROOTCMD bash -l -c 'pacman -Syu --noconfirm'
$ROOTCMD bash -l -c 'pacman -S --noconfirm base-devel devtools abs'
# configure abs
$ROOTCMD bash -l -c 'abs core extra'
# configure sudo
echo 'jenkins ALL= NOPASSWD: /usr/sbin/pacman *' | $ROOTCMD tee -a /etc/sudoers

# configure jenkins user
$ROOTCMD mkdir /var/lib/jenkins
$ROOTCMD chown -R jenkins:jenkins /var/lib/jenkins
echo ". /etc/profile.d/proxy.sh" | tee -a $SCHROOT_BASE/$TARGET/var/lib/jenkins/.bashrc
$USERCMD bash -l -c 'gpg --check-trustdb' # first run will create ~/.gnupg/gpg.conf
$USERCMD bash -l -c 'gpg --recv-keys 0x091AB856069AAA1C'

echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
