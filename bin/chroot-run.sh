#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# released under the GPLv=2

# $1 = base distro
# $2 $3 ... = command to run inside a clean chroot running the distro in $1

set -e
export LC_ALL=C

# Defaults for the jenkins.debian.net environment
if [ -z "$MIRROR" ]; then
	export MIRROR=http://ftp.de.debian.org/debian
fi
if [ -z "$http_proxy" ]; then
	export http_proxy="http://localhost:3128"
fi
if [ -z "$CHROOT_BASE" ]; then
	export CHROOT_BASE=/chroots
fi

if [ $# -lt 2 ]; then
	echo "usage: $0 DISTRO [backports] CMD [ARG1 ARG2 ...]"
	exit 1
fi

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

export CHROOT_TARGET=$(mktemp -d -p $CHROOT_BASE/ chroot-run-$DISTRO.XXXXXXXXX)
if [ -z "$CHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi

export CURDIR=$(pwd)

export SCRIPT_HEADER="#!/bin/bash
set -x
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export http_proxy=$http_proxy"

bootstrap() {
	sudo debootstrap $DISTRO $CHROOT_TARGET $MIRROR

	cat > $CHROOT_TARGET/tmp/chroot-prepare <<-EOF
$SCRIPT_HEADER
mount /proc -t proc /proc
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
echo 'Acquire::http::Proxy "$http_proxy";' > /etc/apt/apt.conf.d/80proxy
echo "deb-src $MIRROR $DISTRO main" >> /etc/apt/sources.list
echo "${BACKPORTS}" >> /etc/apt/sources.list
echo "${BACKPORTSSRC}" >> /etc/apt/sources.list
apt-get update
EOF

	chmod +x $CHROOT_TARGET/tmp/chroot-prepare
	sudo chroot $CHROOT_TARGET /tmp/chroot-prepare
}

cleanup() {
	if [ -d $CHROOT_TARGET/proc ]; then
		sudo umount -l $CHROOT_TARGET/proc || fuser -mv $CHROOT_TARGET/proc
	fi
	if [ -d $CHROOT_TARGET/testrun ]; then
		sudo umount -l $CHROOT_TARGET/testrun || fuser -mv $CHROOT_TARGET/testrun
	fi
	if [ -d $CHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
	fi
}
trap cleanup INT TERM EXIT

run() {
	cp -r $CURDIR $CHROOT_TARGET/tmp/
	mv $CHROOT_TARGET/tmp/$(basename $CURDIR) $CHROOT_TARGET/tmp/testrun
	cat > $CHROOT_TARGET/tmp/chroot-testrun <<-EOF
$SCRIPT_HEADER
cd /tmp/testrun
echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/23jenkins
apt-get install build-essential devscripts git
if [ -f debian/control ] ; then
	cat debian/control
	# install build-depends
	mk-build-deps -ir
fi
$@
EOF
	chmod +x $CHROOT_TARGET/tmp/chroot-testrun
	sudo chroot $CHROOT_TARGET /tmp/chroot-testrun

	# hack to get data out of the chroot (might be dropped when
	# haskell-package-plan uses schroot, which will bindmount the current
	# directory in the schroot)
	if [ -e $CHROOT_TARGET/tmp/testrun/stats.csv ]
	then
		cp -v $CHROOT_TARGET/tmp/testrun/stats.csv .
	fi
}

bootstrap
run "$@"
cleanup
