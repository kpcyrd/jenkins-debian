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
NAME=$2			# it should be possible to derive $NAME from $JOB_NAME
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

	curlopts="-L"
	if [ -f $file ] ; then
		curlopts="$curlopts -z $file"
	fi
	curl $curlopts -o $file $url
}

cleanup_all() {
	set +x
	set +e
	cd $RESULTS
	echo -n "Last screenshot: "
	if [ -f snapshot_000000.ppm ] ; then
		ls -t1 snapshot_??????.ppm | tail -1
	fi
	#
	# create video
	#
	ffmpeg2theora --videobitrate 700 --no-upscaling snapshot_%06d.ppm --framerate 12 --max_size 800x600 -o g-i-installation-$NAME.ogv
	rm snapshot_??????.ppm
	# rename .bak files back to .ppm
	if find . -name "*.ppm.bak" > /dev/null ; then
		for i in *.ppm.bak ; do
			mv $i $(echo $i | sed -s 's#.ppm.bak#.ppm#')
		done
		# convert to png (less space and better supported in browsers)
		for i in *.ppm ; do
			convert $i ${i%.ppm}.png
			rm $i
		done

	fi
	set -x
	#
	# kill qemu and image
	#
	sudo kill -9 $(ps fax | grep [q]emu-system | grep ${NAME}_preseed.cfg 2>/dev/null | awk '{print $1}') || true
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

bootstrap_system() {
	cd $WORKSPACE
	echo "Creating raw disk image with ${DISKSIZE_IN_GB} GiB now."
	qemu-img create -f raw $NAME.raw ${DISKSIZE_IN_GB}G
	echo "Doing g-i installation test for $NAME now."
	# qemu related variables (incl kernel+initrd)
	if [ -n "$IMAGE" ] ; then
		QEMU_OPTS="-cdrom $IMAGE -boot d"
		QEMU_KERNEL="--kernel $IMAGE_MNT/install.amd/vmlinuz --initrd $IMAGE_MNT/install.amd/gtk/initrd.gz"
	else
		QEMU_KERNEL="--kernel $KERNEL --initrd $INITRD"
	fi
	QEMU_OPTS="$QEMU_OPTS -drive file=$NAME.raw,index=0,media=disk,cache=writeback -m $RAMSIZE"
	QEMU_OPTS="$QEMU_OPTS -display vnc=$DISPLAY -no-shutdown"
	QEMU_WEBSERVER=http://10.0.2.2/
	# preseeding related variables
	PRESEED_PATH=d-i-preseed-cfgs
	PRESEED_URL="url=$QEMU_WEBSERVER/$PRESEED_PATH/${NAME}_preseed.cfg"
	INST_LOCALE="locale=en_US"
	INST_KEYMAP="keymap=us"
	INST_VIDEO="video=vesa:ywrap,mtrr vga=788"
	EXTRA_APPEND=""
	case $JOB_NAME in
		*debian-edu_squeeze-test*)
			INST_KEYMAP="console-keymaps-at/$INST_KEYMAP"
			;;
		*_sid_daily*)
			EXTRA_APPEND="mirror/suite=sid"
			;;
	esac
	case $JOB_NAME in
		*debian_*lxde)
			EXTRA_APPEND="$EXTRA_APPEND desktop=lxde"
			;;
		*debian_*kde)
			EXTRA_APPEND="$EXTRA_APPEND desktop=kde"
			;;
		*debian_*rescue)
			EXTRA_APPEND="$EXTRA_APPEND rescue/enable=true"
			;;
	esac
	APPEND="auto=true priority=critical $EXTRA_APPEND $INST_LOCALE $INST_KEYMAP $PRESEED_URL $INST_VIDEO -- quiet"
	show_preseed $(hostname -f)/$PRESEED_PATH/${NAME}_preseed.cfg
	echo
	echo "Starting QEMU_ now:"
	(sudo qemu-system-x86_64 \
		$QEMU_OPTS \
		$QEMU_KERNEL \
		--append "$APPEND" && touch $RESULTS/qemu_quit ) &
}

boot_system() {
	cd $WORKSPACE
	echo "Booting system installed with g-i installation test for $NAME."
	# qemu related variables (incl kernel+initrd)
	QEMU_OPTS="-drive file=$NAME.raw,index=0,media=disk,cache=writeback -m $RAMSIZE"
	QEMU_OPTS="$QEMU_OPTS -display vnc=$DISPLAY -no-shutdown"
	echo
	echo "Starting QEMU_ now:"
	(sudo qemu-system-x86_64 \
		$QEMU_OPTS && touch $RESULTS/qemu_quit ) &
}


backup_screenshot() {
	cp snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_NR}.ppm.bak
}

do_and_report() {
	vncdo -s $DISPLAY $1 $2
	echo "Sending $1 $2"
	backup_screenshot
}

rescue_action() {
	# boot in rescue mode
	if [ $TRIGGER_NR -ne 0 ] ; then
		let MY_NR=NR-TRIGGER_NR
		TOKEN=$(printf "%03d" $MY_NR)
		case $TOKEN in
			010)	do_and_report key tab
				;;
			020)	do_and_report key enter
				;;
			110)	do_and_report key tab
				;;
			120)	do_and_report key enter
				;;
			170)	do_and_report type df
				;;
			180)	do_and_report key enter
				;;
			190)	do_and_report type exit
				;;
			230)	do_and_report key enter
				;;
			240)	do_and_report key down
				;;
			250)	do_and_report key enter
				;;
			*)	;;
		esac
	fi
}

normal_action() {
	# normal boot after installation
	if [ $TRIGGER_NR -ne 0 ] ; then
		let MY_NR=NR-TRIGGER_NR
		TOKEN=$(printf "%03d" $MY_NR)
		case $TOKEN in
			010)	do_and_report type jenkins
				;;
			020)	do_and_report key enter
				;;
			030)	do_and_report type insecure
				;;
			040)	do_and_report key enter
				;;
			*)	;;
		esac
	fi
}


monitor_system() {
	MODE=$1
	TRIGGERED=$2
	TRIGGER_NR=0
	cd $RESULTS
	sleep 4
	echo "Taking screenshots every 2 seconds now, until qemu ends for whatever reasons or 6h have passed or if the test seems to hang."
	echo
	let MAX_RUNS=NR+10800
	while [ $NR -lt $MAX_RUNS ] ; do
		set +x
		#
		# break if qemu-system has finished
		#
		PRINTF_NR=$(printf "%06d" $NR)
		vncsnapshot -quiet -allowblank $DISPLAY snapshot_${PRINTF_NR}.jpg 2>/dev/null || touch $RESULTS/qemu_quit
		if [ ! -f $RESULTS/qemu_quit ] ; then
			convert snapshot_${PRINTF_NR}.jpg snapshot_${PRINTF_NR}.ppm
			rm snapshot_${PRINTF_NR}.jpg
		else
			echo "could not take vncsnapshot, no qemu running on $DISPLAY"
			break
		fi
		# give signal we are still running
		if [ $(($NR % 14)) -eq 0 ] ; then
			date
		fi
		if [ $(($NR % 100)) -eq 0 ] ; then
			# press ctrl-key to avoid screensaver kicking in
			vncdo -s $DISPLAY key ctrl
			# take a screenshot for later publishing
			backup_screenshot
		fi
		# let's drive this further
		case $MODE in
			rescue)	rescue_action
				;;
			normal)	normal_action
				;;
			*)	;;
		esac
		# test if this screenshot is the same as the one 400 screenshots ago, and if so, probably stop this...
		if [ $(($NR % 100)) -eq 0 ] && [ $NR -gt 400 ] ; then
			# from help let: "Exit Status: If the last ARG evaluates to 0, let returns 1; let returns 0 otherwise."
			let OLD=NR-400
			PRINTF_OLD=$(printf "%06d" $OLD)
			set -x
			if diff -q snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm ; then
				GOCR=$(mktemp)
				gocr snapshot_${PRINTF_NR}.ppm > $GOCR
				LAST_LINE=$(tail -1 $GOCR |cut -d "]" -f2- || true)
				STACK_LINE=$(egrep "(Call Trace|end trace)" $GOCR || true)
				rm $GOCR
				if [ "$LAST_LINE" = " Power down." ] ; then
					echo "QEMU was powered down, continuing."
					backup_screenshot
					break
				elif [ ! -z $STACK_LINE ] ; then
					echo "WARNING: got a stack-trace, probably on power-down."
					backup_screenshot
					break
				elif [ ! -z $TRIGGERED ] ; then
					echo ERROR snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm match, ending installation.
					ls -la snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm
					figlet "Installation hangs."
					break
				else
					TRIGGERED="true"
					let TRIGGER_NR=NR-1
					echo $TRIGGER_NR
				fi
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
	if [ -f $RESULTS/qemu_quit ] ; then
		let NR=NR-2
		rm $RESULTS/qemu_quit
	else
		let NR=NR-1
	fi
	PRINTF_NR=$(printf "%06d" $NR)
	cp snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_NR}.ppm.bak
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

#
# run g-i
#
NR=0
bootstrap_system
case $JOB_NAME in
	*rescue) 	monitor_system rescue
			;;
	*)		monitor_system install true
			;;
esac
#
# boot up installed system
#
case $JOB_NAME in
	*rescue) 	;;
	*)		#
			# kill qemu and image
			#
			sudo kill -9 $(ps fax | grep [q]emu-system | grep ${NAME}_preseed.cfg 2>/dev/null | awk '{print $1}') || true
			if [ ! -z $IMAGE ] ; then sudo umount -l $IMAGE ; fi
			boot_system
			monitor_system normal
			;;
esac

cleanup_all
trap - INT TERM EXIT

