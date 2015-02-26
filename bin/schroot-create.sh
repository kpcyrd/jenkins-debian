#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# Copyright      2014 Joachim Breitner <nomeata@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# bootstraps a new chroot for schroot, and then moves it into the right location

# $1 = schroot name
# $2 = base distro
# $3 $4 ... = extra packages to install

if [ $# -lt 2 ]; then
	echo "usage: $0 TARGET DISTRO [backports] CMD [ARG1 ARG2 ...]"
	exit 1
fi
TARGET="$1"
shift
DISTRO="$1"
shift

if [ "$1" == "backports" ] ; then
	EXTRA_PACKAGES="deb $MIRROR ${DISTRO}-backports main"
	EXTRA_SOURCES="deb-src $MIRROR ${DISTRO}-backports main"
	shift
elif [ "$1" == "reproducible" ] ; then
	EXTRA_PACKAGES="deb http://reproducible.alioth.debian.org/debian/ ./"
	EXTRA_SOURCES="deb-src http://reproducible.alioth.debian.org/debian/ ./"
fi

if [ ! -d "$CHROOT_BASE" ]; then
	echo "Directory $CHROOT_BASE does not exist, aborting."
	exit 1
fi

export CHROOT_TARGET=$(mktemp -d -p $CHROOT_BASE/ schroot-install-$TARGET-XXXX)
if [ -z "$CHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi

bootstrap() {
	mkdir -p "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstraping $DISTRO into $CHROOT_TARGET now."
	sudo debootstrap $DISTRO $CHROOT_TARGET $MIRROR

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $CHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $CHROOT_TARGET/usr/sbin/policy-rc.d
	echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee    $CHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	echo "deb-src $MIRROR $DISTRO main"        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list > /dev/null
	echo "${EXTRA_PACKAGES}"                        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list >/dev/null
	echo "${EXTRA_SOURCES}"                     | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list >/dev/null

	sudo chroot $CHROOT_TARGET apt-get update
	if [ -n "$1" ] ; then
		for d in proc dev dev/pts ; do
			sudo mount --bind /$d $CHROOT_TARGET/$d
		done
		sudo chroot $CHROOT_TARGET apt-get install -y --no-install-recommends "$@" sudo
		# umount in reverse order
		for d in dev/pts dev proc ; do
			sudo umount -l $CHROOT_TARGET/$d
		done
		# configure sudo inside just like outside
		echo "jenkins    ALL=NOPASSWD: ALL" | sudo tee -a $CHROOT_TARGET/etc/sudoers.d/jenkins >/dev/null
		sudo chroot $CHROOT_TARGET chown root.root /etc/sudoers.d/jenkins
		sudo chroot $CHROOT_TARGET chmod 700 /etc/sudoers.d/jenkins
	fi
}

cleanup() {
	if [ -d $CHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
	fi
}
trap cleanup INT TERM EXIT
bootstrap $@

trap - INT TERM EXIT

# pivot the new schroot in place
rand=$RANDOM
if [ -d $SCHROOT_BASE/"$TARGET" ]
then
	sudo mv $SCHROOT_BASE/"$TARGET" $SCHROOT_BASE/"$TARGET"-"$rand"
fi

sudo mv $CHROOT_TARGET $SCHROOT_BASE/"$TARGET"

if [ -d $SCHROOT_BASE/"$TARGET"-"$rand" ]
then
	sudo rm -rf --one-file-system $SCHROOT_BASE/"$TARGET"-"$rand"
fi

# write the schroot config
echo "Writing configuration"
sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
	[jenkins-$TARGET]
	description=Jenkins schroot $TARGET
	directory=$SCHROOT_BASE/$TARGET
	type=directory
	root-users=jenkins
	source-root-users=jenkins
	union-type=aufs
	__END__

echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
