#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# $1 = vnc-display, each job should have a unique one, so jobs can run in parallel
# $2 = name
# $3 = disksize in GB
# $4 = wget url/jigdo url
# $5 = d-i lang setting (default is 'en')
# $6 = d-i locale setting (default is 'en_us')

if [ "$1" = "" ] || [ "$2" = "" ] || [ "$3" = "" ] || [ "$4" = "" ] ; then
	echo "need three params"
	echo '# $1 = vnc-display, each job should have a unique one, so jobs can run in parallel'
	echo '# $2 = name'
	echo '# $3 = disksize in GB'
	echo '# $4 = wget url/jigdo url'
	exit 1
fi

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
mkdir -p $RESULTS/log
QEMU_SERIAL_OUT=${RESULTS}/log/serial-out.log

#
# language
#
if [ -z "$5" ] || [ -z "$6" ] ; then
	DI_LANG="en"
	DI_LOCALE="en_US"
	PRESEEDCFG="preseed.cfg"
else
	DI_LANG=$5
	DI_LOCALE=$6
	PRESEEDCFG="${DI_LANG}_preseed.cfg"
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
	sudo kill -9 $(ps fax | grep [q]emu-system | grep "vnc=$DISPLAY " 2>/dev/null | awk '{print $1}') || true
	sleep 0.3s
	rm $WORKSPACE/$NAME.raw
	rm $QEMU_LAUNCHER
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
	ffmpeg2theora --videobitrate $VIDEOBITRATE --no-upscaling snapshot_%06d.ppm --framerate 12 --max_size $VIDEOSIZE -o g-i-installation-$NAME.ogv > /dev/null
	rm snapshot_??????.ppm
	# rename .bak files back to .ppm
	if find . -name "*.ppm.bak" > /dev/null ; then
		for i in $(find * -name "*.ppm.bak") ; do
			mv $i $(echo $i | sed -s 's#.ppm.bak#.ppm#')
		done
		# convert to png (less space and better supported in browsers)
		for i in $(find * -name "*.ppm") ; do
			convert $CONVERTOPTS $i ${i%.ppm}.png
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
	QEMU_OPTS="-display vnc=$DISPLAY -no-shutdown -enable-kvm -cpu host"
	VIDEOBITRATE=1200
	VIDEOSIZE=1024x768	# don't change this (or adjust what needs to be shaved when ocr'ing later)
	CONVERTOPTS="-gravity center -background gray10 -extent $VIDEOSIZE"
	if [ -n "$IMAGE" ] ; then
		QEMU_OPTS="$QEMU_OPTS -cdrom $IMAGE -boot d"
	        case $NAME in
			*_kfreebsd)	;;
			*_hurd*)	QEMU_OPTS="$QEMU_OPTS -vga std"
					gzip -cd $IMAGE_MNT/boot/kernel/gnumach.gz > $WORKSPACE/gnumach
					;;
			*)		QEMU_KERNEL="--kernel $IMAGE_MNT/install.amd/vmlinuz --initrd $IMAGE_MNT/install.amd/gtk/initrd.gz"
					;;
		esac
	else
		QEMU_KERNEL="--kernel $KERNEL --initrd $INITRD"
	fi
	QEMU_OPTS="$QEMU_OPTS -drive file=$NAME.raw,index=0,media=disk,cache=unsafe -m $RAMSIZE -net nic,vlan=0 -net user,vlan=0,host=10.0.2.1,dhcpstart=10.0.2.2,dns=10.0.2.254"
	QEMU_OPTS="$QEMU_OPTS -serial file:${QEMU_SERIAL_OUT}"
	QEMU_WEBSERVER=http://10.0.2.1/
	# preseeding related variables
	PRESEED_PATH=d-i-preseed-cfgs
	PRESEED_URL="url=$QEMU_WEBSERVER/$PRESEED_PATH/${NAME}_$PRESEEDCFG"
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
		debian-edu*-server)
			QEMU_OPTS="$QEMU_OPTS -net nic,vlan=1 -net user,vlan=1"
			EXTRA_APPEND="$EXTRA_APPEND interface=eth0"
			;;
		*)	;;
	esac
	case $NAME in
		*_dark_theme)
			EXTRA_APPEND="$EXTRA_APPEND theme=dark"
			;;
		debian-edu_*_gnome)
			EXTRA_APPEND="$EXTRA_APPEND desktop=gnome"
			GUITERMINAL=xterm
			;;
		debian-edu_*_lxde)
			EXTRA_APPEND="$EXTRA_APPEND desktop=lxde"
			GUITERMINAL=xterm
			;;
		debian-edu_*_xfce)
			EXTRA_APPEND="$EXTRA_APPEND desktop=xfce"
			GUITERMINAL=xterm
			;;
		debian-edu_*)
			EXTRA_APPEND="$EXTRA_APPEND desktop=kde"
			GUITERMINAL=konsole
			;;
		*)	;;
	esac
	case $NAME in
		debian-edu_*)
			EXTRA_APPEND="$EXTRA_APPEND DEBCONF_DEBUG=developer"
			;;
	esac
	case $NAME in
	    debian-edu_*)
		# Debian Edu and tasksel do not work the expected way
		# with priority=critical, so do not set it.
		;;
	    *)
		EXTRA_APPEND="$EXTRA_APPEND priority=critical"
		;;
	esac
	APPEND="auto=true $EXTRA_APPEND $INST_LOCALE $INST_KEYMAP $PRESEED_URL $INST_VIDEO -- quiet"
	show_preseed $(hostname -f)/$PRESEED_PATH/${NAME}_$PRESEEDCFG
	echo
	echo "Starting QEMU now:"
	set -x
	QEMU_LAUNCHER=$(mktemp)
	echo "cd $WORKSPACE" > $QEMU_LAUNCHER
	echo -n "sudo qemu-system-x86_64 $QEMU_OPTS " >> $QEMU_LAUNCHER
	if [ -n "$QEMU_KERNEL" ]; then
		echo -n "$QEMU_KERNEL " >> $QEMU_LAUNCHER
	else # Hurd needs multiboot options jenkins can't escape correctly
		echo -n '--kernel '$WORKSPACE'/gnumach --initrd "'$IMAGE_MNT'/boot/initrd.gz \$(ramdisk-create),'$IMAGE_MNT'/boot/kernel/ext2fs.static --multiboot-command-line=\${kernel-command-line} --host-priv-port=\${host-port} --device-master-port=\${device-port} --exec-server-task=\${exec-task} -T typed gunzip:device:rd0 \$(task-create) \$(task-resume),'$IMAGE_MNT'/boot/kernel/ld.so.1 /hurd/exec \$(exec-task=task-create)" ' >> $QEMU_LAUNCHER
	fi
	echo "--append \"$APPEND\"" >> $QEMU_LAUNCHER
	(bash -x $QEMU_LAUNCHER && touch $RESULTS/qemu_quit ) &
	set +x
}

boot_system() {
	cd $WORKSPACE
	echo "Booting system installed with g-i installation test for $NAME."
	# qemu related variables (incl kernel+initrd) - display first, as we grep for this in the process list
	QEMU_OPTS="-display vnc=$DISPLAY -no-shutdown -enable-kvm -cpu host"
	QEMU_OPTS="$QEMU_OPTS -drive file=$NAME.raw,index=0,media=disk,cache=unsafe -m $RAMSIZE -net nic,vlan=0 -net user,vlan=0,host=10.0.2.1,dhcpstart=10.0.2.2,dns=10.0.2.254"
	echo "Checking $NAME.raw:"
	FILE=$(file $NAME.raw)
	if [ $(echo $FILE | grep -E '(x86 boot sector|DOS/MBR boot sector)' | wc -l) -eq 0 ] ; then
		echo "ERROR: no x86 boot sector found in $NAME.raw - it's filetype is $FILE."
		exit 1
	fi
	case $NAME in
		debian-edu*-server)
				QEMU_OPTS="$QEMU_OPTS -net nic,vlan=1 -net user,vlan=1"
				;;
		*)		;;
	esac
	QEMU_OPTS="$QEMU_OPTS -serial file:${QEMU_SERIAL_OUT}"
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
	echo "At $NR (token: $TOKEN) sending $@"
	vncdo -s $DISPLAY $@
	backup_screenshot
}

rescue_boot() {
	# boot in rescue mode
	let MY_NR=NR-TRIGGER_NR
	TOKEN=$(printf "%04d" $MY_NR)
	case $TOKEN in
		0010)	do_and_report key tab
			;;
		0020)	do_and_report key enter
			;;
		0100)	do_and_report key tab
			;;
		0110)	do_and_report key enter
			;;
		0150)	do_and_report type df
			;;
		0160)	do_and_report key enter
			;;
		0170)	do_and_report type exit
			;;
		0200)	do_and_report key enter
			;;
		0210)	do_and_report key down
			;;
		0220)	do_and_report key enter
			;;
		*)	;;
	esac
}

post_install_boot() {
	# normal boot after installation
	let MY_NR=NR-TRIGGER_NR
	TOKEN=$(printf "%04d" $MY_NR)
	#
	# login as jenkins or root
	#
	case $NAME in
		debian_*)	case $TOKEN in
			0050)	do_and_report type jenkins
				;;
			0060)	do_and_report key enter
				;;
			0070)	do_and_report type insecure
				;;
			0080)	do_and_report key enter
				;;
			*)	;;
		esac
		;;
		# debian-edu installations differ too much, login individually
		*)	;;
	esac
	# Debian Edu -test images usually show a screen with known problems
	# search for EDUTESTMODE in the code to understand how the next 2 lines are used
	EDUTESTMODE=false
	[[ "$NAME" =~ ^debian-edu_.*-test.*$ ]] && EDUTESTMODE=true
	#
	# actions depending on the type of installation
	#
	case $NAME in
		debian_*xfce)		case $TOKEN in
					0200)	do_and_report key enter
						;;
					0210)	do_and_report key alt-f2
						;;
					0220)	do_and_report type "iceweasel"
						;;
					0230)	do_and_report key space
						;;
					0240)	do_and_report type "www"
						;;
					0250)	do_and_report type "."
						;;
					0260)	do_and_report type "debian"
						;;
					0270)	do_and_report type "."
						;;
					0280)	do_and_report type "org"
						;;
					0290)	do_and_report key enter
						;;
					0400)	do_and_report key alt-f2
						;;
					0410)	do_and_report type xterm
						;;
					0420)	do_and_report key enter
						;;
					0430)	do_and_report type apt-get
						;;
					0440)	do_and_report key space
						;;
					0450)	do_and_report type moo
						;;
					0500)	do_and_report key enter
						;;
					0510)	do_and_report type "su"
						;;
					0520)	do_and_report key enter
						;;
					0530)	do_and_report type r00tme
						;;
					0540)	do_and_report key enter
						;;
					0550)	do_and_report type "poweroff"
						;;
					0560)	do_and_report key enter
						;;
					*)	;;
				esac
				;;
		debian_*lxde)		case $TOKEN in
					0200)	do_and_report key alt-f2
						;;
					0210)	do_and_report type "iceweasel"
						;;
					0230)	do_and_report key space
						;;
					0240)	do_and_report type "www"
						;;
					0250)	do_and_report type "."
						;;
					0260)	do_and_report type "debian"
						;;
					0270)	do_and_report type "."
						;;
					0280)	do_and_report type "org"
						;;
					0290)	do_and_report key enter
						;;
					0400)	do_and_report key alt-f2
						;;
					0410)	do_and_report type lxterminal
						;;
					0420)	do_and_report key enter
						;;
					0430)	do_and_report type apt-get
						;;
					0440)	do_and_report key space
						;;
					0450)	do_and_report type moo
						;;
					0520)	do_and_report key enter
						;;
					0530)	do_and_report type "su"
						;;
					0540)	do_and_report key enter
						;;
					0550)	do_and_report type r00tme
						;;
					0560)	do_and_report key enter
						;;
					0570)	case $NAME in
							*_hurd*)
								do_and_report type "echo 'In tight loop: hit ctl-alt-del to reboot' >/dev/com0"
							;;
							*)
								do_and_report type "poweroff"
							;;
						esac
						;;
					0580)	do_and_report key enter
						;;
					*)	;;
				esac
				;;
		debian_*kde)		case $TOKEN in
					0300)	do_and_report key tab
						;;
					0310)	do_and_report key enter
						;;
					0400)	do_and_report key alt-f2
						;;
					0410)	do_and_report type "konqueror"
						;;
					0420)	do_and_report key space
						;;
					0430)	do_and_report type "www"
						;;
					0440)	do_and_report type "."
						;;
					0450)	do_and_report type "debian"
						;;
					0460)	do_and_report type "."
						;;
					0470)	do_and_report type "org"
						;;
					0480)	do_and_report key enter
						;;
					0600)	do_and_report key alt-f2
						;;
					0610)	do_and_report type konsole
						;;
					0620)	do_and_report key enter
						;;
					0700)	do_and_report type apt-get
						;;
					0710)	do_and_report key space
						;;
					0720)	do_and_report type moo
						;;
					0730)	do_and_report key enter
						;;
					0740)	do_and_report type "su"
						;;
					0750)	do_and_report key enter
						;;
					0760)	do_and_report type r00tme
						;;
					0770)	do_and_report key enter
						;;
					0780)	do_and_report type "poweroff"
						;;
					0790)	do_and_report key enter
						;;
					*)	;;
				esac
				;;
		debian_*gnome)		case $TOKEN in
					0150)	do_and_report move 530 420 click 1
						;;
					0200)	do_and_report key alt-f2
						;;
					0210)	do_and_report type "iceweasel"
						;;
					0230)	do_and_report key space
						;;
					0240)	do_and_report type "www"
						;;
					0250)	do_and_report type "."
						;;
					0260)	do_and_report type "debian"
						;;
					0270)	do_and_report type "."
						;;
					0280)	do_and_report type "org"
						;;
					0290)	do_and_report key enter
						;;
					0400)	do_and_report key alt-f2
						;;
					0410)	do_and_report type gnome
						;;
					0420)	do_and_report type "-"
						;;
					0430)	do_and_report type terminal
						;;
					0440)	do_and_report key enter
						;;
					0450)	do_and_report type apt-get
						;;
					0460)	do_and_report key space
						;;
					0470)	do_and_report type moo
						;;
					0520)	do_and_report key enter
						;;
					0530)	do_and_report type "su"
						;;
					0540)	do_and_report key enter
						;;
					0550)	do_and_report type r00tme
						;;
					0560)	do_and_report key enter
						;;
					0570)	do_and_report type "poweroff"
						;;
					0580)	do_and_report key enter
						;;
					*)	;;
				esac
				;;
		debian-edu*minimal)	case $TOKEN in
						# debian-edu*minimal installations result in text mode, thus needing an extra tab
						0030)	$EDUTESTMODE && do_and_report key tab
							;;
						0040)	$EDUTESTMODE && do_and_report key enter
							;;
						0050)	do_and_report type root
							;;
						0060)	do_and_report key enter
							;;
						0070)	do_and_report type r00tme
							;;
						0080)	do_and_report key enter
							;;
						0100)	do_and_report type ps
							;;
						0110)	do_and_report key space
							;;
						0120)	do_and_report type fax
							;;
						0130)	do_and_report key enter
							;;
						0140)	do_and_report type df
							;;
						0150)	do_and_report key enter
							;;
						0160)	do_and_report type apt-get
							;;
						0170)	do_and_report key space
							;;
						0180)	do_and_report type moo
							;;
						0200)	do_and_report key enter
							;;
						0300)	do_and_report type poweroff
							;;
						0400)	do_and_report key enter
							;;
						*)	;;
					esac
					;;
		debian-edu*-server)	case $TOKEN in
						# debian-edu*minimal installations result in text mode, thus needing an extra tab
						0500)	$EDUTESTMODE && do_and_report key enter		# dummy keypress
							;;
						0900)	$EDUTESTMODE && do_and_report key enter		# dummy keypress
							;;
						1100)	do_and_report key tab
							;;
						1150)	do_and_report key enter
							;;
						1170)	do_and_report type root
							;;
						1180)	do_and_report key enter
							;;
						1190)	do_and_report type r00tme
							;;
						1200)	do_and_report key enter
							;;
						1250)	do_and_report type ps
							;;
						1260)	do_and_report key space
							;;
						1270)	do_and_report type fax
							;;
						1280)	do_and_report key enter
							;;
						1290)	do_and_report type df
							;;
						1300)	do_and_report key enter
							;;
						1310)	do_and_report type apt-get 	# apt-get moo
							;;
						1320)	do_and_report key space
							;;
						1330)	do_and_report type moo
							;;
						1340)	do_and_report key enter
							;;
						1350)	do_and_report type apt-get 	# apt-get install w3m
							;;
						1360)	do_and_report key space
							;;
						1370)	do_and_report type "-y"
							;;
						1380)	do_and_report key space
							;;
						1390)	do_and_report type install
							;;
						1400)	do_and_report key space
							;;
						1410)	do_and_report type w3m
							;;
						1420)	do_and_report key enter
							;;
						1500)	do_and_report type w3m 		# check nagios
							;;
						1510)	do_and_report key space
							;;
						1520)	do_and_report type https
							;;
						1525)	do_and_report key ":"
							;;
						1530)	do_and_report type "//www"
							;;
						1540)	do_and_report type "/nagios"
							;;
						1550)	do_and_report key enter
							;;
						1600)	do_and_report type q
							;;
						1620)	do_and_report key enter
							;;
						1750)	do_and_report type w3m		# check cups
							;;
						1760)	do_and_report key space
							;;
						1770)	do_and_report type https
							;;
						1775)	do_and_report key ":"
							;;
						1780)	do_and_report type "//www"
							;;
						1785)	do_and_report key ":"
							;;
						1790)	do_and_report type "631"
							;;
						1800)	do_and_report key enter
							;;
						1900)	do_and_report type q
							;;
						1920)	do_and_report key enter
							;;
						2000)	do_and_report type poweroff	# poweroff
							;;
						2010)	do_and_report key enter
							;;
						*)	;;
					esac
					;;
		debian-edu*workstation)	case $TOKEN in
					# debian-edu installations report error found during installation, go forward
					0100)	$EDUTESTMODE && do_and_report key enter
						;;
					0110)	do_and_report type jenkins
						;;
					0120)	do_and_report key enter
						;;
					0130)	do_and_report type insecure
						;;
					0140)	do_and_report key enter
						;;
					*)	;;
				esac
				;;
		debian-edu*standalone*)	case $TOKEN in
					# debian-edu installations report error found during installation, go forward
					0100)	$EDUTESTMODE && do_and_report key enter
						;;
					0110)	do_and_report type jenkins
						;;
					0120)	do_and_report key enter
						;;
					0130)	do_and_report type insecure
						;;
					0140)	do_and_report key enter
						;;
					0300)	do_and_report key tab
						;;
					0310)	do_and_report key enter
						;;
					0400)	do_and_report key alt-f2
						;;
					0410)	do_and_report type "iceweasel"
						;;
					0420)	do_and_report key space
						;;
					0430)	do_and_report type "www"
						;;
					0440)	do_and_report type "."
						;;
					0450)	do_and_report type "debian"
						;;
					0460)	do_and_report type "."
						;;
					0470)	do_and_report type "org"
						;;
					0480)	do_and_report key enter
						;;
					0600)	do_and_report key alt-f2
						;;
					0610)	do_and_report type $GUITERMINAL
						;;
					0620)	do_and_report key enter
						;;
					0700)	do_and_report type apt-get
						;;
					0710)	do_and_report key space
						;;
					0720)	do_and_report type moo
						;;
					0730)	do_and_report key enter
						;;
					0740)	do_and_report type "su"
						;;
					0750)	do_and_report key enter
						;;
					0760)	do_and_report type r00tme
						;;
					0770)	do_and_report key enter
						;;
					0780)	do_and_report type "poweroff"
						;;
					0790)	do_and_report key enter
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
	# use default valule for timeout if none given
	if [ -z "$3" ] ; then
		TIMEOUT=600
	else
		TIMEOUT=$3
	fi
	cd $RESULTS
	sleep 8	# chosen by fair dice roll
	hourlimit=16 # hours
	echo "Taking screenshots every 2 seconds now, until qemu ends for whatever reasons or $hourlimit hours have passed or if the test seems to hang."
	echo
	timelimit=$(( $hourlimit * 60 * 60 / 2 ))
	let MAX_RUNS=NR+$timelimit
	while [ $NR -lt $MAX_RUNS ] ; do
		#
		# break if qemu-system has finished
		#
		if ! ps fax | grep [q]emu-system | grep vnc=$DISPLAY >/dev/null; then
			touch $RESULTS/qemu_quit
			break
		fi
		PRINTF_NR=$(printf "%06d" $NR)
		vncsnapshot -quiet -allowblank $DISPLAY snapshot_${PRINTF_NR}.jpg 2>/dev/null || true
		if [ -f snapshot_${PRINTF_NR}.jpg ]; then
			convert $CONVERTOPTS snapshot_${PRINTF_NR}.jpg snapshot_${PRINTF_NR}.ppm
			rm snapshot_${PRINTF_NR}.jpg
		else
			echo "could not take vncsnapshot from $DISPLAY, lets try again..."
			let NR=NR-1
			PRINTF_NR=$(printf "%06d" $NR)
			echo "$PRINTF_NR: $(date)"
		fi
		# give signal we are still running
		if [ $(($NR % 14)) -eq 0 ] ; then
			echo "$PRINTF_NR: $(date)"
		fi
		if [ $(($NR % 100)) -eq 0 ] ; then
			# press ctrl-key regularily to avoid screensaver kicking in
			vncdo -s $DISPLAY key ctrl || true
			# preserve a screenshot for later publishing
			backup_screenshot
			#
			# search for known text using ocr of screenshot and break out of this loop if certain content is found
			#
			GOCR=$(mktemp)
			# shave 112 pixels on the sides and 84 on top+bottom
			# so that 1024x768 becomes 800x600
			convert -shave 112x84 snapshot_${PRINTF_NR}.ppm $GOCR.ppm
			gocr $GOCR.ppm > $GOCR
			LAST_LINE=$(tail -1 $GOCR |cut -d "]" -f2- || true)
			STACK_LINE=$(egrep "(Call Trace|end trace)" $GOCR || true)
			INVALID_SIG_LINE=$(egrep "(Invalid Release signature)" $GOCR || true)
			CDROM_PROBLEM=$(grep "There was a problem reading data from the CD-ROM" $GOCR || true)
			SOFTWARE_PROBLEM=$(grep "The failing step is: Select and install software" $GOCR || true)
			rm $GOCR $GOCR.ppm
			if [[ "$LAST_LINE" =~ .*Power\ down.* ]] ; then
				echo "QEMU was powered down, continuing."
				break
			elif [ ! -z "$STACK_LINE" ] ; then
				echo "INFO: got a stack-trace, probably on power-down."
				break
			elif [ ! -z "$INVALID_SIG_LINE" ] ; then
				echo "ERROR: Invalid Release signature found, aborting."
				exit 1
			elif [ ! -z "$CDROM_PROBLEM" ] ; then
				echo "ERROR: Loading installer components from CDROM failed, aborting."
				exit 1
			elif [ ! -z "$SOFTWARE_PROBLEM" ] ; then
				echo "ERROR: The failing step is: Select and install software."
				exit 1
			fi
		fi
		# every 100 screenshots, starting from the $TIMEOUTth one...
		if [ $(($NR % 100)) -eq 0 ] && [ $NR -gt $TIMEOUT ] ; then
			# from help let: "Exit Status: If the last ARG evaluates to 0, let returns 1; let returns 0 otherwise."
			let OLD=NR-$TIMEOUT
			PRINTF_OLD=$(printf "%06d" $OLD)
			# test if this screenshot is basically the same as the one $TIMEOUT screenshots ago
			# 400 pixels difference between to images is tolerated, to ignore updating clocks
			PIXEL=$(compare -metric AE snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm /dev/null 2>&1 || true )
			# usually this returns an integer, but not always....
			if [[ "$PIXEL" =~ ^[0-9]+$ ]] ; then
				echo "$PIXEL pixel difference between snapshot_${PRINTF_NR}.ppm and snapshot_${PRINTF_OLD}.ppm"
				if [ $PIXEL -lt 400 ] ; then
					# unless TRIGGER_MODE is empty, matching images means its over
					if [ ! -z "$TRIGGER_MODE" ] ; then
						echo "Warning: snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm match or almost match, ending installation."
						ls -la snapshot_${PRINTF_NR}.ppm snapshot_${PRINTF_OLD}.ppm
						if [ "$MODE" = "install" ] ; then
							echo "System in $MODE mode is hanging, let's end this."
							# hanging install = broken install
							exit 1
						fi
						echo "System in $MODE mode is hanging, moving on."
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
		# let's drive this further (once/if triggered)
		if [ $TRIGGER_NR -ne 0 ] && [ $TRIGGER_NR -ne $NR ] ; then
			case $MODE in
				rescue)	rescue_boot
					;;
				post_install)	post_install_boot
					;;
				*)	;;
			esac
		fi
		# if TRIGGER_MODE matches NR, we are triggered too
		if [ ! -z "$TRIGGER_MODE" ] && [ "$TRIGGER_MODE" = "$NR" ] ; then
			let TRIGGER_NR=NR
		fi
		let NR=NR+1
		sleep 2

		# Hurd can't poweroff itself
		case $NAME in
			*_hurd*)
				if grep "In tight loop: hit ctl-alt-del to reboot" $QEMU_SERIAL_OUT >/dev/null; then
					echo "Powering off Hurd VM ..."
					sleep 10
					sudo kill -9 $(ps fax | grep [q]emu-system | grep vnc=$DISPLAY 2>/dev/null | awk '{print $1}')
				fi
				;;
			*)	;;
		esac
	done
	if [ $NR -eq $MAX_RUNS ] ; then
		echo "Warning: running for ${hourlimit}h, forcing termination."
	fi
	if [ -f "$RESULTS/qemu_quit" ] ; then
		rm $RESULTS/qemu_quit
	fi
	if [ ! -f snapshot_${PRINTF_NR}.ppm ] ; then
		let NR=NR-1
		PRINTF_NR=$(printf "%06d" $NR)
	fi
	backup_screenshot
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
	# "sudo guestmount -o uid=$(id -u) -o gid=$(id -g)" would be nicer, but it doesnt work: as root, the files seem to belong to jenkins, but as jenkins they cannot be accessed
	case $NAME in
		debian-edu_*_workstation)	sudo guestmount -a $NAME.raw -m /dev/vg_system/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/vg_system/root" ; figlet "fail" )
						;;
		debian-edu_*-server|debian-edu_*minimal)
						sudo guestmount -a $NAME.raw -m /dev/vg_system/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/vg_system/root" ; figlet "fail" )
						sudo guestmount -a $NAME.raw -m /dev/vg_system/var -o nonempty --ro $SYSTEM_MNT/var || ( echo "Warning: cannot mount /dev/vg_system/var" ; figlet "fail" )
						sudo guestmount -a $NAME.raw -m /dev/vg_system/usr -o nonempty --ro $SYSTEM_MNT/usr || ( echo "Warning: cannot mount /dev/vg_system/usr" ; figlet "fail" )
						;;
		debian-edu_*)			sudo guestmount -a $NAME.raw -m /dev/vg_system/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/vg_system/root" ; figlet "fail" )
						sudo guestmount -a $NAME.raw -m /dev/vg_system/var -o nonempty --ro $SYSTEM_MNT/var || ( echo "Warning: cannot mount /dev/vg_system/var" ; figlet "fail" )
						;;
		debian_wheezy_*)		sudo guestmount -a $NAME.raw -m /dev/debian/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/debian/root" ; figlet "fail" )
						;;
		*)				sudo guestmount -a $NAME.raw -m /dev/debian-vg/root --ro $SYSTEM_MNT || ( echo "Warning: cannot mount /dev/debian-vg/root" ; figlet "fail" ) 
						;;
	esac
	#
	# copy logs (and continue if some logs cannot be copied)
	#
	set +e
	sudo cp -r $SYSTEM_MNT/var/log/installer $SYSTEM_MNT/etc/fstab $RESULTS/log/
	#
	# get list of installed packages
	#
	sudo chroot $SYSTEM_MNT dpkg -l > $RESULTS/log/dpkg-l || ( echo "Warning: cannot run dpkg inside the installed system." ; sudo ls -la $SYSTEM_MNT ; figlet "fail" )
	#
	# only on combi-servers:
	#	mount /opt
	#	copy LTSP logs and package list
	#	unmount /opt
	#
	case $NAME in
		debian-edu_*combi-server)	sudo guestmount -a $NAME.raw -m /dev/vg_system/opt -o nonempty --ro $SYSTEM_MNT/opt || ( echo "Warning: cannot mount /dev/vg_system/opt" ; figlet "fail" )
						mkdir -p $RESULTS/log/opt
						if [ -d $SYSTEM_MNT/opt/ltsp/amd64 ] ; then
							LTSPARCH="amd64"
						elif [ -d $SYSTEM_MNT/opt/ltsp/i386 ] ; then
							LTSPARCH="i386"
						else
							echo "Warning: no LTSP chroot found."
						fi
						if [ ! -z "$LTSPARCH" ] ; then
							sudo cp -r $SYSTEM_MNT/opt/ltsp/$LTSPARCH/var/log $RESULTS/log/opt/
							sudo chroot $SYSTEM_MNT/opt/ltsp/$LTSPARCH dpkg -l > $RESULTS/log/opt/dpkg-l || ( echo "Warning: cannot run dpkg inside the ltsp chroot." ; sudo ls -la $SYSTEM_MNT/opt/ltsp/$LTSPARCH ; figlet "fail" )
						fi
						sudo umount -l $SYSTEM_MNT/opt || ( echo "Warning: cannot un-mount $SYSTEM_MNT/opt" ; figlet "fail" )
						;;
		*)				;;
	esac
	#
	# make sure we can read everything after installation
	#
	sudo chown -R jenkins:jenkins $RESULTS/log/
	#
	# umount guests
	#
	sync
	case $NAME in
		debian-edu_*_workstation)	;;
		debian-edu_*-server|debian-edu_*minimal)
						sudo umount -l $SYSTEM_MNT/var || ( echo "Warning: cannot un-mount $SYSTEM_MNT/var" ; figlet "fail" )
						sudo umount -l $SYSTEM_MNT/usr || ( echo "Warning: cannot un-mount $SYSTEM_MNT/usr" ; figlet "fail" )
						;;
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
	# is this really an .iso?
	if [ $(file "$IMAGE" | grep -cE '(ISO 9660|DOS/MBR boot sector)') -eq 1 ] ; then
		# yes, so let's mount it
		sudo mkdir -p $IMAGE_MNT
		grep -q $IMAGE_MNT /proc/mounts && sudo umount -l $IMAGE_MNT
		sleep 1
		sudo mount -o loop,ro $IMAGE $IMAGE_MNT
	else
		# something went wrong
		figlet "no .iso"
		echo "ERROR: no valid .iso found"
		if [ $(file "$IMAGE" | grep -c "HTML document") -eq 1 ] ; then
			mv "$IMAGE" "$IMAGE.html"
			lynx --dump "$IMAGE.html"
			rm "$IMAGE.html"
		fi
		exit 1
	fi
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
	debian-edu_*combi-server)		monitor_system install wait4match 3000
			;;
	*)		monitor_system install wait4match
			;;
esac
#
# boot up installed system
#
let NR=NR+1
case $NAME in
	*_rescue*)	# so there are some artifacts to publish
			mkdir -p $RESULTS/log/installer
			touch $RESULTS/log/dummy $RESULTS/log/installer/dummy
			;;
	*)		#
			# kill qemu and image
			#
			sudo kill -9 $(ps fax | grep [q]emu-system | grep "vnc=$DISPLAY " 2>/dev/null | awk '{print $1}') || true
			if [ ! -z "$IMAGE" ] ; then
				sudo umount -l $IMAGE_MNT || true
			fi
			echo "Sleeping 15 seconds."
			sleep 15
			boot_system
			let START_TRIGGER=NR+100
			monitor_system post_install $START_TRIGGER
			save_logs
			;;
esac
cleanup_all

# don't cleanup twice
trap - INT TERM EXIT

