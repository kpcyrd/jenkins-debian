#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

cleanup_all() {
	sudo rm -rf --one-file-system $TMPDIR
}

TMPDIR=$(mktemp --tmpdir=/srv/live-build -d)
cd $TMPDIR
trap cleanup_all INT TERM EXIT

# $1 is used for the hostname and username
# $2 is used for the suite
# $3 is choosing the flavor
lb config --distribution $2 --bootappend-live "boot=live config hostname=$1 username=$1"
cp -rv /srv/jenkins/live/config .
case "$3" in
	standalone)	echo education-standalone >> config/package-lists/live.list.chroot
			echo education-desktop-xfce >> config/package-lists/live.list.chroot
			echo education-laptop >> config/package-lists/live.list.chroot
			;;
	workstation)	echo education-workstation >> config/package-lists/live.list.chroot
			echo education-desktop-xfce >> config/package-lists/live.list.chroot
			echo education-laptop >> config/package-lists/live.list.chroot
			;;
	gnome)		echo task-gnome-desktop >> config/package-lists/live.list.chroot
			;;
	xfce)		echo task-xfce-desktop >> config/package-lists/live.list.chroot
			;;
	*)		;;
esac
sudo lb build
mkdir -p /srv/live-build/results
sudo cp -v live-image-amd64.hybrid.iso /srv/live-build/results/$1_$2_$3_live_amd64.iso
echo
echo "$(date) - live image created:"
ls -lh /srv/live-build/results/$1_$2_$3_live_amd64.iso
echo

cleanup_all
trap - INT TERM EXIT

