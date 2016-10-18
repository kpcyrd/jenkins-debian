#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Reiner Herrmann <reiner@reiner-h.de>
#           2016 Alexander Couzens <lynxis@fe80.eu>
# released under the GPLv=2

# configuration
GENERIC_NODE1=profitbricks-build3-amd64.debian.net
GENERIC_NODE2=profitbricks-build4-amd64.debian.net

# run on jenkins master
node_debug() {
	ls -al "$1" || true
	ls -al "$1/" || true
	ls -al "$1/download" || true
}

# only called direct on a remote build node
node_cleanup_tmpdirs() {
	export TMPDIR=$1
	cd
	# (very simple) check we are deleting the right stuff
	if [ "${TMPDIR:0:26}" != "/srv/reproducible-results/" ] || [ ${#TMPDIR} -le 26 ] ; then
		echo "Something very strange with \$TMPDIR=$TMPDIR exiting instead of doing cleanup."
		exit 1
	fi
	rm -rf $TMPDIR
}

node_create_tmpdirs() {
	export TMPDIR=$1
	# (very simple) check what we are creating
	if [ "${TMPDIR:0:26}" != "/srv/reproducible-results/" ] || [ ${#TMPDIR} -le 26 ] ; then
		echo "Something very strange with \$TMPDIR=$TMPDIR exiting instead of doing create."
		exit 1
	fi
	mkdir -p $TMPDIR/download
}

# called as trap handler and also to cleanup after a success build
master_cleanup_tmpdirs() {
	# we will save the logs in case we got called as trap handler
	# in a success build the logs are saved on a different function
	if [ "$1" != "success" ] ; then
		# job failed
		ssh $GENERIC_NODE1 reproducible_$TYPE node node_save_logs $TMPDIR || true
		ssh $GENERIC_NODE2 reproducible_$TYPE node node_save_logs $TMPDIR || true
		# save failure logs
		mkdir -p $WORKSPACE/results/
		rsync -av $GENERIC_NODE1:$TMPDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b1.tar.xz || true
		rsync -av $GENERIC_NODE2:$TMPDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b2.tar.xz || true
	fi

	ssh $GENERIC_NODE1 reproducible_$TYPE node node_cleanup_tmpdirs $TMPDIR || true
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_cleanup_tmpdirs $TMPDIR || true

	cd
	# (very simple) check we are deleting the right stuff
	if [ "${TMPDIR:0:26}" != "/srv/reproducible-results/" ] || [ ${#TMPDIR} -le 26 ] || \
	   [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$TMPDIR=$TMPDIR or \$TMPBUILDDIR=$TMPBUILDDIR, exiting instead of doing cleanup."
		exit 1
	fi
	rm -rf $TMPDIR
	rm -rf $TMPBUILDDIR
	if [ -f $BANNER_HTML ] ; then
		rm -f $BANNER_HTML
	fi
}

create_results_dirs() {
	local project=$1
	mkdir -p $BASE/$project/dbd
}

# node_save_logs can be called over ssh OR called within openwrt_build
node_save_logs() {
	local tmpdir=$1

	if [ "${tmpdir:0:26}" != "/srv/reproducible-results/" ] || [ ${#tmpdir} -le 26 ] ; then
		echo "Something very strange with \$TMPDIR=$tmpdir exiting instead of doing node_save_logs."
		exit 1
	fi

	if [ ! -d "$tmpdir/build/source/logs" ] ; then
		# we create an empty tar.xz instead of failing
		touch "$tmpdir/build_logs.tar.xz"
	else
		tar cJf "$tmpdir/build_logs.tar.xz" -C "$tmpdir/build/source" ./logs
	fi
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
		# needs to fix openwrt/lede ;)
		# umask 0002

		# use allmost all cores for second build
		export NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
		export MAKE=make
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

	OPTIONS="-j $NUM_CPU IGNORE_ERRORS=ym BUILD_LOG=1"

	ionice -c 3 make $OPTIONS tools/install
	ionice -c 3 make $OPTIONS toolchain/install
}

# TYPE - openwrt or lede
# RUN - b1 or b2. b1 means first run, b2 second
# TARGET - a target including subtarget. E.g. ar71xx_generic
openwrt_compile() {
	local TYPE=$1
	local RUN=$2
	local TARGET=$3

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

# called by openwrt_two_times
# ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_download $TYPE $TARGET $CONFIG $TMPDIR
openwrt_download() {
	local TARGET=$1
	local CONFIG=$2
	local TMPDIR=$3

	cd $TMPDIR/download

	# checkout the repo
	echo "================================================================================"
	echo "$(date -u) - Cloning git repository from $OPENWRT_GIT_REPO $OPENWRT_GIT_BRANCH. "
	echo "================================================================================"
	git clone -b $OPENWRT_GIT_BRANCH $OPENWRT_GIT_REPO source
	cd source

	# update feeds
	#./scripts/feeds update
	#./scripts/feeds install -a

	# configure openwrt because otherwise it wont download everything
	openwrt_config $CONFIG
	make download -j $NUM_CPU IGNORE_ERRORS=ym
}

openwrt_get_banner() {
	TMPDIR=$1
	TYPE=$2
	cd $TMPDIR/build/source
	find build_dir/ -name banner | grep etc/banner|head -1| xargs cat /dev/null
}

# openwrt_build is run on a remote host
# TYPE - openwrt or lede
# RUN - b1 or b2. b1 means first run, b2 second
# TARGET - a target including subtarget. E.g. ar71xx_generic
# CONFIG - a simple basic .config as string. Use \n to seperate lines
# TMPPATH - is a unique path generated with mktmp
# lede has a different output directory than openwrt
openwrt_build() {
	local TYPE=$1
	local RUN=$2
	local TARGET=$3
	local CONFIG=$4
	export TMPDIR=$5
	export TMPBUILDDIR=$TMPDIR/build/

	mv "$TMPDIR/download" "$TMPBUILDDIR"

	# openwrt/lede is checkouted under /download
	cd $TMPBUILDDIR/source

	# set tz, date, core, ..
	openwrt_apply_variations $RUN

	openwrt_build_toolchain
	# build images and packages
	openwrt_compile $TYPE $RUN $TARGET

	# save the results
	[ "$TYPE" = "lede" ] && save_lede_results $RUN
	[ "$TYPE" = "openwrt" ] && save_openwrt_results $RUN

	# copy logs
	node_save_logs "$TMPDIR"
}

# build openwrt/lede on two different hosts
# TARGET a target including subtarget. E.g. ar71xx_generic
# CONFIG - a simple basic .config as string. Use \n to seperate lines
# TYPE - openwrt or lede
# lede has a different output directory than openwrt
build_two_times() {
	TYPE=$1
	TARGET=$2
	CONFIG=$3

	# create openwrt
	ssh $GENERIC_NODE1 reproducible_$TYPE node node_create_tmpdirs $TMPDIR
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_create_tmpdirs $TMPDIR
	mkdir -p $TMPDIR/download/

	# create results directory saved by jenkins as artifacts
	mkdir -p $WORKSPACE/results/

	# download and prepare openwrt on node b1
	ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_download $TARGET $CONFIG $TMPDIR

	echo "== master"
	ls -la "$TMPDIR/download/" || true
	echo "== node1"
	ssh $GENERIC_NODE1 reproducible_$TYPE node node_debug $TMPDIR
	echo "== node2"
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_debug $TMPDIR

	rsync -a $GENERIC_NODE1:$TMPDIR/download/ $TMPDIR/download/
	rsync -a $TMPDIR/download/ $GENERIC_NODE2:$TMPDIR/download/

	## first run
	RUN=b1
	ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_build $TYPE $RUN $TARGET $CONFIG $TMPDIR
	ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_get_banner $TMPDIR $TYPE > $BANNER_HTML

	# rsync back logs and images
	rsync -av $GENERIC_NODE1:$TMPDIR/$RUN/ $TMPDIR/$RUN/
	rsync -av $GENERIC_NODE1:$TMPDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b1.tar.xz
	ssh $GENERIC_NODE1 reproducible_$TYPE node node_cleanup_tmpdirs $TMPDIR

	## second run
	RUN=b2
	ssh $GENERIC_NODE2 reproducible_$TYPE node openwrt_build $TYPE $RUN $TARGET $CONFIG $TMPDIR

	# rsync back logs and images
	rsync -av $GENERIC_NODE2:$TMPDIR/$RUN/ $TMPDIR/$RUN/
	rsync -av $GENERIC_NODE2:$TMPDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b2.tar.xz
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_cleanup_tmpdirs $TMPDIR
}
