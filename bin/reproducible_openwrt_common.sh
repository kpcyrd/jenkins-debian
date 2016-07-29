#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Reiner Herrmann <reiner@reiner-h.de>
#           2016 Alexander Couzens <lynxis@fe80.eu>
# released under the GPLv=2

cleanup_tmpdirs() {
	cd
	# (very simple) check we are deleting the right stuff
	if [ "${TMPDIR:0:26}" != "/srv/reproducible-results/" ] || [ ${#TMPDIR} -le 26 ] || \
	   [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$TMPDIR=$TMPDIR or \$TMPBUILDDIR=$TMPBUILDDIR, exiting instead of doing cleanup."
		exit 1
	fi
	rm -rf $TMPDIR
	rm -rf $TMPBUILDDIR
	rm -f $BANNER_HTML
}

create_results_dirs() {
	local project=$1
	mkdir -p $BASE/$project/dbd
}

# project = openwrt or lede
# postfix = we use the postfix to save difference of the first and second build
save_logs() {
	local project="$1"
	local postfix="$2"

	tar cJf "$BASE/${project}/dbd/logs_${postfix}.tar.xz" logs/
}

# RUN - is b1 or b2. b1 for first run, b2 for second
# save the images and packages under $TMPDIR/$RUN
save_lede_results() {
	RUN=$1

	# first save all images and target specific packages
	pushd bin/targets
	for target in * ; do
		pushd $target || continue
		for subtarget in * ; do
			pushd $subtarget || continue

			# save firmware images
			mkdir -p $TMPDIR/$RUN/targets/$target/$subtarget/
			for image in $(find * -name "*.bin" -o -name "*.squashfs") ; do
				cp -p $image $TMPDIR/$RUN/targets/$target/$subtarget/
			done

			# save subtarget specific packages
			if [ -d packages ] ; then
				pushd packages
				for package in $(find * -name "*.ipk") ; do
					mkdir -p $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package)
					cp -p $package $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package)/
				done
				popd
			fi
			popd
		done
		popd
	done
	popd

	# save all generic packages
	# arch is like mips_34kc_dsp
	pushd bin/packages/
	for arch in * ; do
		pushd $arch || continue
		for feed in * ; do
			pushd $feed || continue
			for package in $(find * -name "*.ipk") ; do
				mkdir -p $TMPDIR/$RUN/packages/$arch/$feed/$(dirname $package)
				cp -p $package $TMPDIR/$RUN/packages/$arch/$feed/$(dirname $package)/
			done
			popd
		done
		popd
	done
	popd
}

# RUN - is b1 or b2. b1 for first run, b2 for second
# save the images and packages under $TMPDIR/$RUN
save_openwrt_results() {
	RUN=$1
	cd bin
	for i in * ; do
		cd $i
		# save images
		mkdir -p $TMPDIR/$RUN/$i
		for j in $(find * -name "*.bin" -o -name "*.squashfs") ; do
			cp -p $j $TMPDIR/$RUN/$i/
		done
		# save packages
		cd packages
		for j in $(find * -name "*.ipk") ; do
			mkdir -p $TMPDIR/$RUN/$i/$(dirname $j)
			cp -p $j $TMPDIR/$RUN/$i/$(dirname $j)/
		done
		cd ../..
	done
	cd ..
}

# apply variations change the environment for
# the subsequent run
# RUN - b1 or b2. b1 for first run, b2 for the second
openwrt_apply_variations() {
	RUN=$1

	if [ "$RUN" = "b1" ] ; then
		export TZ="/usr/share/zoneinfo/Etc/GMT+12"
		export MAKE=make
	else
		export TZ="/usr/share/zoneinfo/Etc/GMT-14"
		export LANG="fr_CH.UTF-8"
		export LC_ALL="fr_CH.UTF-8"
		export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
		export CAPTURE_ENVIRONMENT="I capture the environment"
		umask 0002
		# use allmost all cores for second build
		export NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
		export MAKE="linux64 --uname-2.6 make"
	fi
}


openwrt_config() {
	CONFIG=$1

	printf "$CONFIG" > .config
	printf "CONFIG_ALL=y\n" >> .config
	printf "CONFIG_CLEAN_IPKG=y\n" >> .config
	printf "CONFIG_TARGET_ROOTFS_TARGZ=y\n" >> .config
	make defconfig
}

openwrt_build_toolchain() {
	echo "============================================================================="
	echo "$(date -u) - Building the toolchain."
	echo "============================================================================="

	ionice -c 3 make -j $NUM_CPU tools/install
	ionice -c 3 make -j $NUM_CPU toolchain/install
}

# TYPE - openwrt or lede
# RUN - b1 or b2. b1 means first run, b2 second
# TARGET - a target including subtarget. E.g. ar71xx_generic
openwrt_compile() {
	TYPE=$1
	RUN=$2
	TARGET=$3

	OPTIONS="-j $NUM_CPU IGNORE_ERRORS=ym BUILD_LOG=1"

	# make $RUN more human readable
	[ "$RUN" = "b1" ] && RUN="first"
	[ "$RUN" = "b2" ] && RUN="second"

	echo "============================================================================="
	echo "$(date -u) - Building $TYPE ${OPENWRT_VERSION} ($TARGET) - $RUN build run."
	echo "============================================================================="
	ionice -c 3 $MAKE $OPTIONS target/compile
	ionice -c 3 $MAKE $OPTIONS package/cleanup
	ionice -c 3 $MAKE $OPTIONS package/compile || true # don't let some packages fail the whole build
	ionice -c 3 $MAKE $OPTIONS package/install
	ionice -c 3 $MAKE $OPTIONS target/install V=s || true
	ionice -c 3 $MAKE $OPTIONS package/index || true # don't let some packages fail the whole build
}

openwrt_cleanup() {
	rm build_dir/target-* -rf
	rm staging_dir/target-* -rf
	rm bin/* -rf
	rm logs/* -rf
}

# TARGET a target including subtarget. E.g. ar71xx_generic
# CONFIG - a simple basic .config as string. Use \n to seperate lines
# TYPE - openwrt or lede
# lede has a different output directory than openwrt
build_two_times() {
	TYPE=$1
	TARGET=$2
	CONFIG=$3

	openwrt_config $CONFIG
	openwrt_build_toolchain

	# FIRST BUILD
	openwrt_apply_variations b1
	openwrt_compile "$TYPE" b1 "$TARGET"

	# get banner
	cat $(find build_dir/ -name banner | grep etc/banner|head -1) > $BANNER_HTML

	# save results in b1
	[ "$TYPE" = "lede" ] && save_lede_results b1
	[ "$TYPE" = "openwrt" ] && save_openwrt_results b1

	# copy logs
	save_logs $TYPE b1

	# clean up between builds
	openwrt_cleanup

	# SECOND BUILD
	openwrt_apply_variations b2
	openwrt_compile "$TYPE" b2 "$TARGET"

	# save results in b2
	[ "$TYPE" = "lede" ] && save_lede_results b2
	[ "$TYPE" = "openwrt" ] && save_openwrt_results b2

	# copy logs
	save_logs $TYPE b2

	# reset environment to default values again
	export LANG="en_GB.UTF-8"
	unset LC_ALL
	export TZ="/usr/share/zoneinfo/UTC"
	export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
	umask 0022

	# clean up again
	openwrt_cleanup
}

