#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# $1 = vnc-display
# $2 = name
# $3 = wget url/jigdo url

if [ "$1" = "" ] || [ "$2" = "" ] || [ "$3" = "" ] ; then
	echo "need three params"
	echo '# $1 = vnc-display'
	echo '# $2 = name'
	echo '# $3 = wget url/jigdo url'
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

#
# init
#
DISPLAY=$1
NAME=$2
URL=$3
if [ "$(basename $URL)" != "amd64" ] ; then
	IMAGE=$(pwd)/$(basename $URL)
	IMAGE_MNT="/media/cd-$NAME.iso"
else
	KERNEL=linux
	INITRD=initrd.gz
fi

#
# define workspace + results
#
rm -rf results
mkdir -p results
WORKSPACE=$(pwd)
RESULTS=$WORKSPACE/results

cleanup_all() {
	set +x
	cd $RESULTS
	echo -n "Last screenshot: "
	ls -t1 *.ppm | head -1
	#
	# create video
	#
	ffmpeg2theora --videobitrate 700 --no-upscaling snapshot_%06d.ppm --framerate 12 --max_size 800x600 -o cd-test-$NAME.ogv
	rm snapshot_??????.ppm
	set -x
	#
	# kill qemu and image
	#
	sudo kill -9 $(ps fax | grep -v grep | grep -v sudo | grep qemu-system | grep ${NAME}-preseed.cfg 2>/dev/null | cut -d " " -f1)
	sleep 0.3s
	rm $WORKSPACE/$NAME.qcow
	#
	# cleanup
	#
	sudo umount $IMAGE_MNT
}

bootstrap() {
	cd $WORKSPACE
	echo "Doing cd tests for $NAME now."
	qemu-img create -f qcow $NAME.qcow 20g
	case $NAME in
		debian-edu-wheezy)
				echo "fire up qemu now..."
				sudo qemu-system-x86_64 -cdrom $IMAGE -hda $NAME.qcow -boot d -m 1024 -display vnc=localhost:$DISPLAY --kernel $IMAGE_MNT/install.amd/vmlinuz --append "auto=true priority=critical locale=en_US keymap=us url=http://10.0.2.2/userContent/${NAME}-preseed.cfg video=vesa:ywrap,mtrr vga=788 initrd=/install.amd/gtk/initrd.gz -- quiet" --initrd $IMAGE_MNT/install.amd/gtk/initrd.gz &
				;;
		lxde-wheezy)
				echo "fire up qemu now..."
				sudo qemu-system-x86_64 -hda $NAME.qcow -boot c -m 1024 -display vnc=localhost:$DISPLAY --kernel $KERNEL --append "auto=true priority=critical desktop=lxde locale=en_US keymap=us url=http://10.0.2.2/userContent/${NAME}-preseed.cfg video=vesa:ywrap,mtrr vga=788 --" --initrd $INITRD &
				# wheezy: qemu-system-x86_64 -cdrom debian-6.0.6-amd64-businesscard.iso -hda debian.qcow -boot d -m 2048 -display vnc=localhost:1 --kernel /mnt/install.amd/vmlinuz --append "auto=true priority=critical url=http://10.0.2.2/userContent/preseed.cfg vga=788 initrd=/install.amd/initrd.gz" --initrd /mnt/install.amd/initrd.gz
				# kernel /install.amd/vmlinuz
				# append desktop=lxde video=vesa:ywrap,mtrr vga=788 initrd=/install.amd/gtk/initrd.gz -- quiet
				;;
		*)		echo "unsupported distro."
				exit 1
				;;
	esac
}

monitor_installation() {
	cd $RESULTS
	sleep 4
	echo "Taking screenshots every 2 secondss now, until the installation is finished (or qemu ends for other reasons) or 5h have passed or if the installation seems to hang."
	echo
	NR=0
	while [ $NR -lt 9000 ] ; do
		set +x
		#
		# break if qemu-system has finished
		#
		if [ $(ps fax | grep -v grep | grep qemu-system | grep ${NAME}-preseed.cfg 2>/dev/null | wc -l) -eq 0 ] ; then
			break
		fi
		vncsnapshot -quiet -allowblank localhost:$DISPLAY snapshot_$(printf "%06d" $NR).jpg 2>/dev/null
		convert snapshot_$(printf "%06d" $NR).jpg snapshot_$(printf "%06d" $NR).ppm 
		rm snapshot_$(printf "%06d" $NR).jpg 
		# give signal we are still running
		if [ $(($NR % 15)) -eq 0 ] ; then
			date
		fi
		# press ctrl-key to avoid screensaver kicking in
		if [ $(($NR % 150)) -eq 0 ] ; then
			vncdo -s localhost:$DISPLAY key ctrl
		fi
		# if this screenshot is the same as the one 400 screenshots ago, let stop this
		if [ $(($NR % 100)) -eq 0 ] && [ $NR -gt 400 ] ; then
			# from help let: "Exit Status: If the last ARG evaluates to 0, let returns 1; let returns 0 otherwise."
			let OLD=NR-400
			set -x
			if diff -q snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $OLD).ppm ; then
				echo Warning: snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $OLD).ppm match, ending installation.
				cp snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $NR).ppm.bak
				cp snapshot_$(printf "%06d" $OLD).ppm snapshot_$(printf "%06d" $OLD).ppm.bak
				ls -la snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $OLD).ppm
				break
			fi
			set +x
		fi
		let NR=NR+1
		sleep 2
	done
	set -x
	if [ $NR -eq 9000 ] ; then
		echo Warning: running for 5h, forceing termination.
	fi
}

trap cleanup_all INT TERM EXIT

#
# if there is a CD image...
#
if [ ! -z $IMAGE ] ; then
	# only download if $IMAGE is older than a week (60*24*7=10080) (+9500 is a bit less than a week)
	if test $(find $IMAGE -mmin +9500) || ! test -f $IMAGE ; then
		curl $URL > $IMAGE
	fi
	sudo mkdir -p $IMAGE_MNT
	mount | grep -v grep | grep $IMAGE_MNT && sudo umount -l $IMAGE_MNT
	sleep 1
	sudo mount -o loop,ro $IMAGE $IMAGE_MNT
else
	#
	# else netboot gtk
	#
	# only download if $KERNEL is older than a week...
	if test $(find $KERNEL -mmin +9500) || ! test -f $KERNEL ; then
		curl $URL/$KERNEL > $KERNEL
		curl $URL/$INITRD > $INITRD
	fi

fi
bootstrap 
monitor_installation

cleanup_all
trap - INT TERM EXIT

