#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# Copyright      2014 Joachim Breitner <nomeata@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# bootstraps a new chroot for schroot, and then moves it into the right location

# $1 = schroot name
# $2 = base distro/suite
# $3 $4 ... = extra packages to install

if [ $# -lt 2 ]; then
	echo "usage: $0 TARGET SUITE [backports] CMD [ARG1 ARG2 ...]"
	exit 1
fi
TARGET="$1"
shift
SUITE="$1"
shift

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

	echo "Bootstraping $SUITE into $CHROOT_TARGET now."
	sudo debootstrap $SUITE $CHROOT_TARGET $MIRROR

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $CHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $CHROOT_TARGET/usr/sbin/policy-rc.d
	echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee    $CHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	echo "deb-src $MIRROR $SUITE main"        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list > /dev/null

	sudo chroot $CHROOT_TARGET apt-get update
	if [ -n "$1" ] ; then
		# install debbindiff with all recommends...
		#sudo chroot $CHROOT_TARGET apt-get install -y --no-install-recommends "$@"
		sudo chroot $CHROOT_TARGET apt-get install -y "$@"
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

remove_writelock() {
	# remove the lock
	rm $DBDCHROOT_WRITELOCK
}

trap remove_writelock INT TERM EXIT
# aquire a write lock in any case
touch $DBDCHROOT_WRITELOCK
if [ -f $DBDCHROOT_READLOCK ] ; then
	# patiently wait for our users to using the schroot
	for i in $(seq 0 100) ; do
		sleep 15
		echo "sleeping 15s, debbindiff schroot is locked and used."
		if [ ! -f $DBDCHROOT_READLOCK ] ; then
			break
		fi
	done
	if [ -f $DBDCHROOT_READLOCK ] ; then
		echo "Warning: lock $DBDCHROOT_READLOCK still exists, exiting."
		exit 1
	fi
fi

# pivot the new schroot in place
rand=$RANDOM
if [ -d $SCHROOT_BASE/"$TARGET" ]
then
	sudo mv $SCHROOT_BASE/"$TARGET" $SCHROOT_BASE/"$TARGET"-"$rand"
fi

sudo mv $CHROOT_TARGET $SCHROOT_BASE/"$TARGET"

if [ -d $SCHROOT_BASE/"$TARGET"-"$rand" ]
then
	sudo rm -rf --one-file-system $SCHROOT_BASE/"$TARGET"-"$rand" || ( echo "Warning: $SCHROOT_BASE/${TARGET}-$rand could not be fully removed." ; ls $SCHROOT_BASE/${TARGET}-$rand -la )
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

trap - INT TERM EXIT
remove_writelock
