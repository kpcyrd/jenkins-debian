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
export

#
# init
#
DISPLAY=localhost:$1
NAME=$2			# it should be possible to derive $NAME from $JOB_NAME
DISKSIZE_IN_GB=$3
URL=$4
# $5 and $6 are used below for language setting
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

#
# language
#
if [ -z "$5" ] || [ -z "$6" ] ; then
	DI_LANG="en"
	DI_LOCALE="en_US"
else
	DI_LANG=$5
	DI_LOCALE=$6
fi

fetch_if_newer() {
	url="$2"
	file="$1"

	curlopts="-L"
	if [ -f "$file" ] ; then
		curlopts="$curlopts -z $file"
	fi
	curl $curlopts -o $file $url
}

cleanup_all() {
	set +x
	set +e
	#
	# kill qemu
	#
	sudo kill -9 $(ps fax | grep [q]emu-system | grep vnc=$DISPLAY 2>/dev/null | awk '{print $1}') || true
	sleep 0.3s
	rm $WORKSPACE/$NAME.raw
	#
	# cleanup image mount
	#
	sudo umount -l $IMAGE_MNT &
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
	# qemu related variables (incl kernel+initrd) - display first, as we grep for this in the process list
	QEMU_OPTS="-display vnc=$DISPLAY -no-shutdown"
	if [ -n "$IMAGE" ] ; then
		QEMU_OPTS="$QEMU_OPTS -cdrom $IMAGE -boot d"
		QEMU_KERNEL="--kernel $IMAGE_MNT/install.amd/vmlinuz --initrd $IMAGE_MNT/install.amd/gtk/initrd.gz"
	else
		QEMU_KERNEL="--kernel $KERNEL --initrd $INITRD"
	fi
	QEMU_OPTS="$QEMU_OPTS -drive file=$NAME.raw,index=0,media=disk,cache=writeback -m $RAMSIZE"
	QEMU_WEBSERVER=http://10.0.2.2/
	# preseeding related variables
	PRESEED_PATH=d-i-preseed-cfgs
	PRESEED_URL="url=$QEMU_WEBSERVER/$PRESEED_PATH/${NAME}_preseed.cfg"
	INST_LOCALE="locale=$DI_LOCALE"
	INST_KEYMAP="keymap=us"	# always us!
	INST_VIDEO="video=vesa:ywrap,mtrr vga=788"
	EXTRA_APPEND=""
	case $NAME in
		debian*_squeeze*)
			INST_KEYMAP="console-keymaps-at/$INST_KEYMAP"
			;;
		*_sid_daily*)
			EXTRA_APPEND="mirror/suite=sid"
			;;
		*)	;;
	esac
	case $NAME in
		debian_*_xfce)
			EXTRA_APPEND="$EXTRA_APPEND desktop=xfce"
			;;
		debian_*_lxde)
			EXTRA_APPEND="$EXTRA_APPEND desktop=lxde"
			;;
		debian_*_kde)
			EXTRA_APPEND="$EXTRA_APPEND desktop=kde"
			;;
		debian_*_rescue*)
			EXTRA_APPEND="$EXTRA_APPEND rescue/enable=true"
			;;
		*)	;;
	esac
	case $NAME in
		*_dark_theme)
			EXTRA_APPEND="$EXTRA_APPEND theme=dark"
			;;
		*)	;;
	esac
	APPEND="auto=true priority=critical $EXTRA_APPEND $INST_LOCALE $INST_KEYMAP $PRESEED_URL $INST_VIDEO -- quiet"
	show_preseed $(hostname -f)/$PRESEED_PATH/${NAME}_preseed.cfg
	echo
	echo "Starting QEMU now:"
	set -x
	(sudo qemu-system-x86_64 \
		$QEMU_OPTS \
		$QEMU_KERNEL \
		--append "$APPEND" && touch $RESULTS/qemu_quit ) &
	set +x
}

boot_system() {
	cd $WORKSPACE
	echo "Booting system installed with g-i installation test for $NAME."
	# qemu related variables (incl kernel+initrd) - display first, as we grep for this in the process list
	QEMU_OPTS="-display vnc=$DISPLAY -no-shutdown"
	QEMU_OPTS="$QEMU_OPTS -drive file=$NAME.raw,index=0,media=disk,cache=writeback -m $RAMSIZE"
	echo "Checking $NAME.raw:"
	file $NAME.raw
	# FIXME: exit here if image is not bootable
	echo
	echo "Starting QEMU_ now:"
	set -x
	(sudo qemu-system-x86_64 \
		$QEMU_OPTS && touch $RESULTS/qemu_quit ) &
	set +x
}


backup_screenshot() {
	cp snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_NR}.ppm.bak
}

do_and_report() {
	vncdo -s $DISPLAY $1 "$2"
	echo "At $NR sending $1 $2"
	backup_screenshot
}

rescue_action() {
	# boot in rescue mode
	let MY_NR=NR-TRIGGER_NR
	TOKEN=$(printf "%03d" $MY_NR)
	case $TOKEN in
		010)	do_and_report key tab
			;;
		020)	do_and_report key enter
			;;
		100)	do_and_report key tab
			;;
		110)	do_and_report key enter
			;;
		150)	do_and_report type df
			;;
		160)	do_and_report key enter
			;;
		170)	do_and_report type exit
			;;
		200)	do_and_report key enter
			;;
		210)	do_and_report key down
			;;
		220)	do_and_report key enter
			;;
		*)	;;
	esac
}

normal_action() {
	# normal boot after installation
	let MY_NR=NR-TRIGGER_NR
	TOKEN=$(printf "%03d" $MY_NR)
	#
	# common for all types of install
	#
	case $TOKEN in
		050)	do_and_report type jenkins
			;;
		060)	do_and_report key enter
			;;
		070)	do_and_report type insecure
			;;
		080)	do_and_report key enter
			;;
		*)	;;
	esac
	#
	# actions depending on the type of installation
	#
	case $NAME in
		*xfce)		case $TOKEN in
						200)	do_and_report key enter
							;;
						210)	do_and_report key alt-f2
							;;
						220)	do_and_report type "iceweasel"
							;;
						230)	do_and_report key space
							;;
						240)	do_and_report type "www"
							;;
						250)	do_and_report type "."
							;;
						260)	do_and_report type "debian"
							;;
						270)	do_and_report type "."
							;;
						280)	do_and_report type "org"
							;;
						290)	do_and_report key enter
							;;
						400)	do_and_report key alt-f2
							;;
						410)	do_and_report type xterm
							;;
						420)	do_and_report key enter
							;;
						430)	do_and_report type apt-get
							;;
						440)	do_and_report key space
							;;
						450)	do_and_report type moo
							;;
						500)	do_and_report key enter
							;;
						510)	do_and_report type "su"
							;;
						520)	do_and_report key enter
							;;
						530)	do_and_report type r00tme
							;;
						540)	do_and_report key enter
							;;
						550)	do_and_report type "poweroff"
							;;
						560)	do_and_report key enter
							;;
						*)	;;
				esac
				;;
		*lxde)		case $TOKEN in
						200)	do_and_report key alt-f2
							;;
						210)	do_and_report type "iceweasel"
							;;
						230)	do_and_report key space
							;;
						240)	do_and_report type "www"
							;;
						250)	do_and_report type "."
							;;
						260)	do_and_report type "debian"
							;;
						270)	do_and_report type "."
							;;
						280)	do_and_report type "org"
							;;
						290)	do_and_report key enter
							;;
						400)	do_and_report key alt-f2
							;;
						410)	do_and_report type lxterminal
							;;
						420)	do_and_report key enter
							;;
						430)	do_and_report type apt-get
							;;
						440)	do_and_report key space
							;;
						450)	do_and_report type moo
							;;
						520)	do_and_report key enter
							;;
						530)	do_and_report type "su"
							;;
						540)	do_and_report key enter
							;;
						550)	do_and_report type r00tme
							;;
						560)	do_and_report key enter
							;;
						570)	do_and_report type "poweroff"
							;;
						580)	do_and_report key enter
							;;
						*)	;;
				esac
				;;
		*kde)		case $TOKEN in
						300)	do_and_report key tab
							;;
						310)	do_and_report key enter
							;;
						400)	do_and_report key alt-f2
							;;
						410)	do_and_report type "konqueror"
							;;
						420)	do_and_report key space
							;;
						430)	do_and_report type "www"
							;;
						440)	do_and_report type "."
							;;
						450)	do_and_report type "debian"
							;;
						460)	do_and_report type "."
							;;
						470)	do_and_report type "org"
							;;
						480)	do_and_report key enter
							;;
						600)	do_and_report key alt-f2
							;;
						610)	do_and_report type konsole
							;;
						620)	do_and_report key enter
							;;
						630)	do_and_report type apt-get
							;;
						640)	do_and_report key space
							;;
						650)	do_and_report type moo
							;;
						660)	do_and_report key enter
							;;
						670)	do_and_report type "su"
							;;
						680)	do_and_report key enter
							;;
						690)	do_and_report type r00tme
							;;
						700)	do_and_report key enter
							;;
						710)	do_and_report type "poweroff"
							;;
						720)	do_and_report key enter
							;;
						*)	;;
				esac
				;;
		*gnome)		case $TOKEN in
						200)	do_and_report key alt-f2
							;;
						210)	do_and_report type "iceweasel"
							;;
						230)	do_and_report key space
							;;
						240)	do_and_report type "www"
							;;
						250)	do_and_report type "."
							;;
						260)	do_and_report type "debian"
							;;
						270)	do_and_report type "."
							;;
						280)	do_and_report type "org"
							;;
						290)	do_and_report key enter
							;;
						400)	do_and_report key alt-f2
							;;
						410)	do_and_report type gnome
							;;
						420)	do_and_report type "-"
							;;
						430)	do_and_report type terminal
							;;
						440)	do_and_report key enter
							;;
						450)	do_and_report type apt-get
							;;
						460)	do_and_report key space
							;;
						470)	do_and_report type moo
							;;
						520)	do_and_report key enter
							;;
						530)	do_and_report type "su"
							;;
						540)	do_and_report key enter
							;;
						550)	do_and_report type r00tme
							;;
						560)	do_and_report key enter
							;;
						570)	do_and_report type "poweroff"
							;;
						580)	do_and_report key enter
							;;
						*)	;;
				esac
				;;
		*)		;;
	esac
}


monitor_system() {
	MODE=$1
	# if TRIGGER_MODE is set to a number, triggered mode will be entered in that many steps - else an image match needs to happen
	TRIGGER_MODE=$2
	TRIGGER_NR=0
	cd $RESULTS
	sleep 4
	echo "Taking screenshots every 2 seconds now, until qemu ends for whatever reasons or 6h have passed or if the test seems to hang."
	echo
	set -x
	let MAX_RUNS=NR+10800
	while [ $NR -lt $MAX_RUNS ] ; do
		#
		# break if qemu-system has finished
		#
		PRINTF_NR=$(printf "%06d" $NR)
		vncsnapshot -quiet -allowblank $DISPLAY snapshot_${PRINTF_NR}.jpg 2>/dev/null || touch $RESULTS/qemu_quit
		if [ ! -f "$RESULTS/qemu_quit" ] ; then
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
			#
			# search for known text ocr of screenshot and break out of this loop if certain content is found
			#
			GOCR=$(mktemp)
			gocr snapshot_${PRINTF_NR}.ppm > $GOCR
			LAST_LINE=$(tail -1 $GOCR |cut -d "]" -f2- || true)
			STACK_LINE=$(egrep "(Call Trace|end trace)" $GOCR || true)
			rm $GOCR
			if [[ "$LAST_LINE" =~ .*Power\ down.* ]] ; then
				echo "QEMU was powered down, continuing."
				break
			elif [ ! -z "$STACK_LINE" ] ; then
				echo "INFO: got a stack-trace, probably on power-down."
				break
			fi
		fi
		# let's drive this further (once/if triggered)
		if [ $TRIGGER_NR -ne 0 ] && [ $TRIGGER_NR -ne $NR ] ; then
			case $MODE in
				rescue)	rescue_action
					;;
				normal)	normal_action
					;;
				*)	;;
			esac
		fi
		# every 100 screenshots, starting from the 400ths one...
		if [ $(($NR % 100)) -eq 0 ] && [ $NR -gt 400 ] ; then
			# from help let: "Exit Status: If the last ARG evaluates to 0, let returns 1; let returns 0 otherwise."
			let OLD=NR-400
			PRINTF_OLD=$(printf "%06d" $OLD)
			# test if this screenshot is basically the same as the one 400 screenshots ago
			# 400 pixels difference between to images is tolerated, to ignore updating clocks
			PIXEL=$(compare -metric AE snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm /dev/null 2>&1 || true )
			# usually this returns an integer, but not always....
			if [[ "$PIXEL" =~ ^[0-9]+$ ]] ; then
				echo "$PIXEL pixel difference between snapshot_${PRINTF_NR}.ppm and snapshot_${PRINTF_OLD}.ppm"
				if [ $PIXEL -lt 400 ] ; then
					# unless TRIGGER_MODE is empty, matching images means its over
					if [ ! -z "$TRIGGER_MODE" ] ; then
						echo "Warning: snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm match, ending installation."
						ls -la snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm
						figlet "Installation hangs."
						break
					else
						# this is only reached once in rescue mode
						# and the next matching screenshots will cause a failure...
						TRIGGER_MODE="already_matched"
						# really kick off trigger:
						let TRIGGER_NR=NR
					fi
				fi
			else
				echo "snapshot_${PRINTF_NR}.ppm and snapshot_${PRINTF_OLD}.ppm have different sizes."
			fi
		fi
		# if TRIGGER_MODE matches NR, we are triggered too
		if [ ! -z "$TRIGGER_MODE" ] && [ "$TRIGGER_MODE" = "$NR" ] ; then
			let TRIGGER_NR=NR
		fi
		let NR=NR+1
		sleep 2
	done
	if [ $NR -eq $MAX_RUNS ] ; then
		echo "Warning: running for 6h, forceing termination."
	fi
	if [ -f "$RESULTS/qemu_quit" ] ; then
		let NR=NR-2
		rm $RESULTS/qemu_quit
	else
		let NR=NR-1
	fi
	PRINTF_NR=$(printf "%06d" $NR)
	cp snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_NR}.ppm.bak
}

save_logs() {
	#
	# get logs and other files from the installed system
	#
	# remove set +e & -x once the code has proven its good
	set -x
	cd $WORKSPACE
	SYSTEM_MNT=/media/$NAME
	sudo mkdir -p $SYSTEM_MNT
	# FIXME: bugreport guestmount: -o uid doesnt work:
	# "sudo guestmount -o uid=$(id -u) -o gid=$(id -g)" would be nicer, bt it doesnt work: as root, the files seem to belong to jenkins, but as jenkins they cannot be accessed
	case $NAME in
		debian-edu_*_workstation)	sudo guestmount -a $NAME.raw -m /dev/vg_system/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/vg_system/root" ; figlet "fail" )
						;;
		debian-edu_*)			sudo guestmount -a $NAME.raw -m /dev/vg_system/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/vg_system/root" ; figlet "fail" )
						sudo guestmount -a $NAME.raw -m /dev/vg_system/var -o nonempty --ro $SYSTEM_MNT/var || ( echo "Warning: cannot mount /dev/vg_system/var" ; figlet "fail" )
						;;
		*)				sudo guestmount -a $NAME.raw -m /dev/debian/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/debian/root" ; figlet "fail" ) 
						;;
	esac
	#
	# copy logs (and continue if some logs cannot be copied)
	#
	set +e
	mkdir -p $RESULTS/log
	sudo cp -r $SYSTEM_MNT/var/log/installer $RESULTS/log/
	sudo chown -R jenkins:jenkins $RESULTS/log/
	#
	# get list of installed packages
	#
	sudo chroot $SYSTEM_MNT dpkg -l > $RESULTS/log/dpkg-l
	#
	# umount guests
	#
	sync
	case $NAME in
		debian-edu_*_workstation)	;;
		debian-edu_*)			sudo umount -l $SYSTEM_MNT/var || ( echo "Warning: cannot un-mount $SYSTEM_MNT/var" ; figlet "fail" )
						;;
		*)				;;
	esac
	sudo umount -l $SYSTEM_MNT || ( echo "Warning: cannot un-mount $SYSTEM_MNT" ; figlet "fail" )
}

trap cleanup_all INT TERM EXIT

#
# if there is a CD image...
#
if [ ! -z "$IMAGE" ] ; then
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
set +x
case $NAME in
	*_rescue*) 	monitor_system rescue
			;;
	*)		monitor_system install wait4match
			;;
esac
#
# boot up installed system
#
case $NAME in
	*_rescue*)	# so there are some artifacts to publish
			mkdir -p $RESULTS/log/installer
			touch $RESULTS/log/dummy $RESULTS/log/installer/dummy
			;;
	*)		#
			# kill qemu and image
			#
			sudo kill -9 $(ps fax | grep [q]emu-system | grep vnc=$DISPLAY 2>/dev/null | awk '{print $1}') || true
			if [ ! -z "$IMAGE" ] ; then
				sudo umount -l $IMAGE_MNT || true
			fi
			echo "Sleeping 15 seconds."
			sleep 15
			boot_system
			let START_TRIGGER=NR+500
			monitor_system normal $START_TRIGGER
			save_logs
			;;
esac
cleanup_all

# don't cleanup twice
trap - INT TERM EXIT

