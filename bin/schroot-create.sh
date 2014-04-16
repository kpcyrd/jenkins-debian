#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# released under the GPLv=2

# $2 = schroot name
# $1 = base distro
# $2 $3 ... = extra packages to install

# bootstraps a new chroot for schroot, and then moves it into the right location

set -e
export LC_ALL=C

# Defaults for the jenkins.debian.net environment
if [ -z "$MIRROR" ]; then
	export MIRROR=http://ftp.de.debian.org/debian
fi
if [ -z "$http_proxy" ]; then
	# export http_proxy="http://localhost:3128"
	:
fi
if [ -z "$CHROOT_BASE" ]; then
	export CHROOT_BASE=/chroots
fi
if [ -z "$SCHROOT_BASE" ]; then
	export SCHROOT_BASE=/schroots
fi

if [ $# -lt 2 ]; then
	echo "usage: $0 DISTRO [backports] CMD [ARG1 ARG2 ...]"
	exit 1
fi

TARGET="$1"
shift
DISTRO="$1"
shift

if [ "$1" == "backports" ] ; then
	BACKPORTS="deb $MIRROR ${DISTRO}-backports main"
	BACKPORTSSRC="deb-src $MIRROR ${DISTRO}-backports main"
	shift
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

export CURDIR=$(pwd)

bootstrap() {
	sudo debootstrap $DISTRO $CHROOT_TARGET $MIRROR

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $CHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $CHROOT_TARGET/usr/sbin/policy-rc.d
	echo 'Acquire::http::Proxy "$http_proxy";' | sudo tee    $CHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	echo "deb-src $MIRROR $DISTRO main"        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list > /dev/null
	echo "${BACKPORTS}"                        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list >/dev/null
	echo "${BACKPORTSSRC}"                     | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list >/dev/null
}

cleanup() {
	if [ -d $CHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
	fi
}
trap cleanup INT TERM EXIT
bootstrap

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

schroot -c "source:jenkins-$TARGET" -u root -- apt-get update
if [ -n "$1" ]
then
	schroot -c "source:jenkins-$TARGET" -u root -- apt-get install -y --no-install-recommends "$@"
fi
