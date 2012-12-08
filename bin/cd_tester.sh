#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# $1 = vnc-display, each job should have a unique one, so jobs can run in parallel
# $2 = name
# $3 = disksize in GB
# $4 = wget url/jigdo url

if [ "$1" = "" ] || [ "$2" = "" ] || [ "$3" = "" ] || [ "$4" = "" ] ; then
	echo "need three params"
	echo '# $1 = vnc-display, each job should have a unique one, so jobs can run in parallel'
	echo '# $2 = name'
	echo '# $3 = disksize in GB'
	echo '# $4 = wget url/jigdo url'
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
DISPLAY=localhost:$1
NAME=$2
DISKSIZE_IN_GB=$3
URL=$4
RAMSIZE=1024
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

fetch_if_newer() {
	url="$2"
	file="$1"

	curlopts=""
	if [ -f $file ] ; then
	    curlopts="-z $file"
	fi
	curl $curlopts -o $file $url
}

cleanup_all() {
	set +x
	set +e
	cd $RESULTS
	echo -n "Last screenshot: "
	(ls -t1 | head -1) || true
	#
	# create video
	#
	ffmpeg2theora --videobitrate 700 --no-upscaling snapshot_%06d.ppm --framerate 12 --max_size 800x600 -o cd-test-$NAME.ogv
	rm snapshot_??????.ppm
	# rename .bak files back to .ppm
	for i in *.bak ; do
		mv $i ${i%.bak}
	done
	set -x
	#
	# kill qemu and image
	#
	sudo kill -9 $(ps fax | grep [q]emu-system | grep ${NAME}-preseed.cfg 2>/dev/null | awk '{print $1}') || true
	sleep 0.3s
	rm $WORKSPACE/$NAME.raw
	#
	# cleanup
	#
	sudo umount $IMAGE_MNT
}

show_preseed() {
	url="$1"
	echo "Preseeding from $url:"
	echo
	curl -s "$url" | grep -v ^# | grep -v "^$"
}

bootstrap() {
	cd $WORKSPACE
	echo "Creating raw disk image with ${DISKSIZE_IN_GB} GiB now."
	qemu-img create -f raw $NAME.raw ${DISKSIZE_IN_GB}G
	echo "Doing cd tests for $NAME now."
	# qemu related variables (incl kernel+initrd)
	if [ -n "IMAGE" ] ; then
		QEMU_OPTS="-cdrom $IMAGE -boot d"
		QEMU_KERNEL="--kernel $IMAGE_MNT/install.amd/vmlinuz --initrd $IMAGE_MNT/install.amd/gtk/initrd.gz"
	else
		QEMU_KERNEL="--kernel $KERNEL --initrd $INITRD"
	fi
	QEMU_OPTS="$QEMU_OPTS -drive file=$NAME.raw,index=0,media=disk,cache=writeback -m $RAMSIZE"
	QEMU_OPTS="$QEMU_OPTS -display vnc=$DISPLAY"
	QEMU_WEBSERVER=http://10.0.2.2/
	# preseeding related variables
	PRESEED_PATH=d-i-preseed-cfgs
	PRESEED_URL="url=$QEMU_WEBSERVER/$PRESEED_PATH/${NAME}-preseed.cfg"
	INST_LOCALE="locale=en_US"
	INST_KEYMAP="keymap=us"
	INST_VIDEO="video=vesa:ywrap,mtrr vga=788"
	case $NAME in
		wheezy-debian-edu-workstation)
			EXTRA_APPEND=""
			;;
		squeeze-test-debian-edu-standalone)
			INST_KEYMAP="console-keymaps-at/$INST_KEYMAP"
			EXTRA_APPEND=""
			;;
		wheezy-lxde)
			EXTRA_APPEND="desktop=lxde"
			;;
		*)		echo "unsupported distro."
				exit 1
				;;
	esac
	APPEND="auto=true priority=critical $EXTRA_APPEND $INST_LOCALE $INST_KEYMAP $PRESEED_URL $INST_VIDEO -- quiet"
	show_preseed $(hostname -f)/$PRESEED_PATH/${NAME}-preseed.cfg
	echo
	echo "Starting QEMU_ now:"
	(sudo qemu-system-x86_64 \
	    $QEMU_OPTS \
	    $QEMU_KERNEL \
	    --append "$APPEND" && touch $RESULTS/qemu_exit_0 ) &
}

monitor_installation() {
	cd $RESULTS
	sleep 4
	echo "Taking screenshots every 2 seconds now, until the installation is finished (or qemu ends for other reasons) or 6h have passed or if the installation seems to hang."
	echo
	NR=0
	MAX_RUNS=10800
	while [ $NR -lt $MAX_RUNS ] ; do
		set +x
		#
		# break if qemu-system has finished
		#
		if [ $(ps fax | grep -v grep | grep qemu-system | grep ${NAME}-preseed.cfg 2>/dev/null | wc -l) -eq 0 ] ; then
			break
		fi
		vncsnapshot -quiet -allowblank $DISPLAY snapshot_$(printf "%06d" $NR).jpg 2>/dev/null || ( echo "could not take vncsnapshot." ; if [ -f $RESULTS/qemu_exit_0 ] ; then break ; fi )
		convert snapshot_$(printf "%06d" $NR).jpg snapshot_$(printf "%06d" $NR).ppm 
		rm snapshot_$(printf "%06d" $NR).jpg 
		# give signal we are still running
		if [ $(($NR % 14)) -eq 0 ] ; then
			date
		fi
		# press ctrl-key to avoid screensaver kicking in
		if [ $(($NR % 150)) -eq 0 ] ; then
			vncdo -s $DISPLAY key ctrl
		fi
		# if this screenshot is the same as the one 400 screenshots ago, let stop this
		if [ $(($NR % 100)) -eq 0 ] && [ $NR -gt 400 ] ; then
			# from help let: "Exit Status: If the last ARG evaluates to 0, let returns 1; let returns 0 otherwise."
			let OLD=NR-400
			set -x
			if diff -q snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $OLD).ppm ; then
				echo ERROR snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $OLD).ppm match, ending installation.
				cp snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $NR).ppm.bak
				cp snapshot_$(printf "%06d" $OLD).ppm snapshot_$(printf "%06d" $OLD).ppm.bak
				ls -la snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $OLD).ppm
				figlet "Installation hangs."
				break
			fi
			set +x
		fi
		let NR=NR+1
		sleep 2
	done
	set -x
	if [ $NR -eq $MAX_RUNS ] ; then
		echo Warning: running for 6h, forceing termination.
	fi
	if [ -f $RESULTS/qemu_exit_0 ] ; then
		let NR=NR-2
		rm $RESULTS/qemu_exit_0
	else
		let NR=NR-1
	fi
	cp snapshot_$(printf "%06d" $NR).ppm snapshot_$(printf "%06d" $NR).ppm.bak
}

trap cleanup_all INT TERM EXIT

#
# if there is a CD image...
#
if [ ! -z $IMAGE ] ; then
	fetch_if_newer "$IMAGE" "$URL"

	sudo mkdir -p $IMAGE_MNT
	grep -q $IMAGE_MNT /proc/mounts && sudo umount -l $IMAGE_MNT
	sleep 1
	sudo mount -o loop,ro $IMAGE $IMAGE_MNT
else
	#
	# else netboot gtk
	#
	fetch_if_newer "$KERNEL" "$URL/$KERNEL"
	fetch_if_newer "$INITRD" "$URL/$INITRD"
fi
bootstrap 
monitor_installation

cleanup_all
trap - INT TERM EXIT

