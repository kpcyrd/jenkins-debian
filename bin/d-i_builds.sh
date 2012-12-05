#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# $1 = base distro
# $2 = action (create, update, install_builddeps, use)
# $3 = type of action

if [ "$1" == "" ] ; then
	echo "need at least one distribution to act on"
	echo '# $1 = base distro'
	echo '# $2 = action (create, update, install_builddeps, use)'
	echo '# $3 = type of action'
	exit 1
fi

#
# default settings
#
set -x
set -e
export LC_ALL=C
export MIRROR=http://ftp.de.debian.org/debian
export http_proxy="http://localhost:3128"

export SCRIPT_HEADER="#!/bin/bash
set -x
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export http_proxy=$http_proxy"

export CHROOT_TARGET=/chroots/d-i-$1
export TMPFILE=$(mktemp -u)
export CTMPFILE=$CHROOT_TARGET/$TMPFILE

cleanup_all() {
	# List the processes using the partition
	fuser -mv $CHROOT_TARGET
	# test if $CHROOT_TARGET starts with /chroots/
	if [ "${CHROOT_TARGET:0:9}" != "/chroots/" ] ; then
		echo "HALP. CHROOT_TARGET = $CHROOT_TARGET"
		exit 1
	fi
	sudo umount -l $CHROOT_TARGET/proc || true
	sudo umount -l $CHROOT_TARGET/run/lock || true
	sudo umount -l $CHROOT_TARGET/run/shm || true
	sudo umount -l $CHROOT_TARGET/run || true
	sudo rm -rf --one-file-system $CHROOT_TARGET
}

execute_ctmpfile() {
	chmod +x $CTMPFILE
	sudo chroot $CHROOT_TARGET $TMPFILE
	rm $CTMPFILE
}

prepare_bootstrap() {
cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
mount /proc -t proc /proc
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
echo 'Acquire::http::Proxy "http://localhost:3128";' > /etc/apt/apt.conf.d/80proxy
EOF
}

prepare_install_packages() {
cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
apt-get update
apt-get -y install $1
EOF
}

prepare_upgrade2() {
cat >> $CTMPFILE <<-EOF
echo "deb $MIRROR $1 main contrib non-free" > /etc/apt/sources.list
$SCRIPT_HEADER
apt-get update
#apt-get -y install apt
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
EOF
}

bootstrap() {
	echo "Bootstraping $1 into $CHROOT_TARGET now."
	sudo debootstrap $1 $CHROOT_TARGET $MIRROR
	prepare_bootstrap
	execute_ctmpfile 
}

install_packages() {
	echo "Installing extra packages for $1 now."
	prepare_install_packages $2
	execute_ctmpfile 
}

upgrade2() {
	echo "Upgrading to $1 now."
	prepare_upgrade2 $1
	execute_ctmpfile 
}

trap cleanup_all INT TERM EXIT

case $1 in
	squeeze)bootstrap squeeze;;
	wheezy)	bootstrap wheezy;;
	sid)	bootstrap sid;;
	*)	echo "unsupported distro." ; exit 1 ;;
esac

if [ "$2" != "" ] ; then
	case $2 in
		none)	;;
		gnome)	install_packages gnome gnome ;;
		kde)	install_packages kde kde-plasma-desktop ;;
		xfce)	install_packages xfce xfce4 ;;
		lxde)	install_packages lxde lxde ;;
		*)	echo "unsupported component." ; exit 1 ;;
	esac
fi

if [ "$3" != "" ] ; then
	case $3 in
		squeeze)upgrade2 squeeze;;
		wheezy)	upgrade2 wheezy;;
		sid)	upgrade2 sid;;
		*)	echo "unsupported distro." ; exit 1 ;;
	esac
fi

cleanup_all
trap - INT TERM EXIT

