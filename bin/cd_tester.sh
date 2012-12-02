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
rm -f results
mkdir -p results
cd results
DISPLAY=$1
NAME=$2
IMAGE_URL=$3
IMAGE=$(basename $IMAGE_URL)
IMAGE_MNT="/media/cd-$IMAGE.iso"

cleanup_all() {
	#
	# kill qemu
	#
	sudo kill -9 $(ps fax | grep -v grep | grep qemu-system | grep $IMAGE 2>/dev/null | cut -d " " -f1)
	#
	# cleanup
	#
	umount $IMAGE_MNT
	sudo rm $IMAGE $NAME.qcow
	#
	# create video
	#
	ffmpeg2theora --videobitrate 700 --no-upscaling snapshot_%06d.ppm --framerate 12 --max_size 800x600 -o video.ogv
	rm snapshot_??????.ppm
}

bootstrap() {
	echo "Doing cd tests for $NAME now."
	qemu-img create -f qcow $NAME.qcow 20g
	case $NAME in
		debian-edu-wheezy)
				echo "fire up qemu now..."
				sudo qemu-system-x86_64 -cdrom $IMAGE -hda $NAME.qcow -boot d -m 1024 -display vnc=localhost:$DISPLAY --kernel $IMAGE_MNT/install.amd/vmlinuz --append "auto=true priority=critical url=http://10.0.2.2/userContent/$NAME-preseed.cfg video=vesa:ywrap,mtrr vga=788 initrd=/install.amd/gtk/initrd.gz -- quiet" --initrd $IMAGE_MNT/install.amd/gtk/initrd.gz &
				;;
		*)		echo "unsupported distro."
				exit 1
				# wheezy: qemu-system-x86_64 -cdrom debian-6.0.6-amd64-businesscard.iso -hda debian.qcow -boot d -m 2048 -display vnc=localhost:1 --kernel /mnt/install.amd/vmlinuz --append "auto=true priority=critical url=http://10.0.2.2/userContent/preseed.cfg vga=788 initrd=/install.amd/initrd.gz" --initrd /mnt/install.amd/initrd.gz
				# kernel /install.amd/vmlinuz
				# append desktop=lxde video=vesa:ywrap,mtrr vga=788 initrd=/install.amd/gtk/initrd.gz -- quiet
				;;
	esac
}

monitor_installation() {
	echo "Taking screenshots every 2secs now, until the installation is finished or 5h have passed"
	NR=0
	while [ $NR -lt 9000 ] ; do 
		#
		# break if qemu-system has finished
		#
		if [ $(ps fax | grep -v grep | grep qemu-system | grep $IMAGE 2>/dev/null | wc -l) -eq 0 ] ; then
			break
		fi
		vncsnapshot -quiet -allowblank localhost:$DISPLAY snapshot_$(printf "%06d" $NR).jpg 2>/dev/null
		convert snapshot_$(printf "%06d" $NR).jpg snapshot_$(printf "%06d" $NR).ppm 
		rm snapshot_$(printf "%06d" $NR).jpg 
		let NR=NR+1
		sleep 2 
	done 
}

trap cleanup_all INT TERM EXIT

wget $IMAGE_URL
mkdir -p $IMAGE_MNT
mount -o loop $IMAGE $IMAGE_MNT
bootstrap 
monitor_installation

cleanup_all
trap - INT TERM EXIT

