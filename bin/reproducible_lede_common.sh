#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
#         © 2015 Reiner Herrmann <reiner@reiner-h.de>
#           2016-2017 Alexander Couzens <lynxis@fe80.eu>
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
	export TMPBUILDDIR=$1
	cd
	# (very simple) check we are deleting the right stuff
	if [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$TMPBUILDDIR=$TMPBUILDDIR exiting instead of doing cleanup."
		exit 1
	fi
	rm -rf $TMPBUILDDIR
}

node_create_tmpdirs() {
	export TMPBUILDDIR=$1
	# (very simple) check what we are creating
	if [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$TMPBUILDDIR=$TMPBUILDDIR exiting instead of doing create."
		exit 1
	fi
	mkdir -p $TMPBUILDDIR/download
}

# called as trap handler and also to cleanup after a success build
master_cleanup_tmpdirs() {
	# we will save the logs in case we got called as trap handler
	# in a success build the logs are saved on a different function
	if [ "$1" != "success" ] ; then
		# job failed
		ssh $GENERIC_NODE1 reproducible_$TYPE node node_save_logs $TMPBUILDDIR || true
		ssh $GENERIC_NODE2 reproducible_$TYPE node node_save_logs $TMPBUILDDIR || true
		# save failure logs
		mkdir -p $WORKSPACE/results/
		rsync -av $GENERIC_NODE1:$RESULTSDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b1.tar.xz || true
		rsync -av $GENERIC_NODE2:$RESULTSDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b2.tar.xz || true
	fi

	ssh $GENERIC_NODE1 reproducible_$TYPE node node_cleanup_tmpdirs $TMPBUILDDIR || true
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_cleanup_tmpdirs $TMPBUILDDIR || true

	cd
	# (very simple) check we are deleting the right stuff
	if [ "${RESULTSDIR:0:26}" != "/srv/reproducible-results/" ] || [ ${#RESULTSDIR} -le 26 ] || \
	   [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$RESULTSDIR=$RESULTSDIR or \$TMPBUILDDIR=$TMPBUILDDIR, exiting instead of doing cleanup."
		exit 1
	fi
	rm -rf $RESULTSDIR
	rm -rf $TMPBUILDDIR
	if [ -f $BANNER_HTML ] ; then
		rm -f $BANNER_HTML
	fi
}

create_results_dirs() {
	local project=$1
	mkdir -p $BASE/$project/dbd
}

node_document_environment() {
	local tmpdir=$1
	local toolchain_html=$tmpdir/toolchain.html

	cd $tmpdir/build/source
	cat /dev/null > $toolchain_html
	echo "     <table><tr><th>git commit built</th></tr><tr><td><code>" >> $toolchain_html
	git log -1 >> $toolchain_html
	echo "     </code></td></tr></table>" >> $toolchain_html

	echo "<table><tr><th>Target toolchains built</th></tr>" >> $toolchain_html
	for i in $(ls -1d staging_dir/toolchain*|cut -d "-" -f2-|xargs echo) ; do
		echo " <tr><td><code>$i</code></td></tr>" >> $toolchain_html
	done
	echo "</table>" >> $toolchain_html
	echo "<table><tr><th>Contents of <code>build_dir/host/</code></th></tr>" >> $toolchain_html
	for i in $(ls -1 build_dir/host/) ; do
		echo " <tr><td>$i</td></tr>" >> $toolchain_html
	done
	echo "</table>" >> $toolchain_html
	echo "<table><tr><th>Downloaded software</th></tr>" >> $toolchain_html
	for i in $(ls -1 dl/) ; do
		echo " <tr><td>$i</td></tr>" >> $toolchain_html
	done
	echo "</table>" >> $toolchain_html
	echo "<table><tr><th>Debian $(cat /etc/debian_version) package on $(dpkg --print-architecture)</th><th>installed version</th></tr>" >> $toolchain_html
	for i in gcc binutils bzip2 flex python perl make findutils grep diffutils unzip gawk util-linux zlib1g-dev libc6-dev git subversion ; do
		echo " <tr><td>$i</td><td>" >> $toolchain_html
		dpkg -s $i|grep '^Version'|cut -d " " -f2 >> $toolchain_html
		echo " </td></tr>" >> $toolchain_html
	done
	echo "</table>" >> $toolchain_html
	cd -
}

# node_save_logs can be called over ssh OR called within openwrt_build
# it's always only run on a remote host.
node_save_logs() {
	local tmpdir=$1

	if [ "${tmpdir:0:23}" != "/srv/workspace/chroots/" ] || [ ${#tmpdir} -le 23 ] ; then
		echo "Something very strange with \$TMPDIR=$tmpdir exiting instead of doing node_save_logs."
		exit 1
	fi

	if [ ! -d "$tmpdir/build/source/logs" ] ; then
		# we create an empty tar.xz instead of failing
		touch "$tmpdir/build_logs.tar.xz"
	else
		tar cJf "$tmpdir/build_logs.tar.xz" -C "$tmpdir/build/source" ./logs
	fi

	node_document_environment $tmpdir
}

# RUN - is b1 or b2. b1 for first run, b2 for second
# save the images and packages under $TMPDIR/$RUN
# run on the master
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
					mkdir -p $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package) || ( echo $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package) ; continue )
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

	printf "$CONFIG\n" | grep '^[^ ]' > .config
	printf "CONFIG_ALL=y\n" >> .config
	printf "CONFIG_AUTOREMOVE=y\n" >> .config
	printf "CONFIG_BUILDBOT=y\n" >> .config
	printf "CONFIG_CLEAN_IPKG=y\n" >> .config
	printf "CONFIG_TARGET_ROOTFS_TARGZ=y\n" >> .config
	printf 'CONFIG_KERNEL_BUILD_USER="lede"\n' >> .config
	printf 'CONFIG_KERNEL_BUILD_DOMAIN="buildhost"\n' >> .config
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
	ionice -c 3 $MAKE $OPTIONS
}

openwrt_create_signing_keys() {
	echo "============================================================================="
	cat <<- EOF
# LEDE signs the release with a signing key, but generate the signing key if not
# present. To have a reproducible release we need to take care of signing keys.

# LEDE will also put the key-build.pub into the resulting image (pkg: base-files)!
# At the end of the build it will use the key-build to sign the Packages repo list.
# Use a workaround this problem:

# key-build.pub contains the pubkey of LEDE buildbot
# key-build     contains our build key

# Meaning only signed files will be different but not the images.
# Packages.sig is unreproducible.

# here is our random signing key
# chosen by fair dice roll.
# guaranteed to be random.

# private key
EOF
	echo -e 'untrusted comment: Local build key\nRWRCSwAAAAB12EzgExgKPrR4LMduadFAw1Z8teYQAbg/EgKaN9SUNrgteVb81/bjFcvfnKF7jS1WU8cDdT2VjWE4Cp4cxoxJNrZoBnlXI+ISUeHMbUaFmOzzBR7B9u/LhX3KAmLsrPc=' | tee key-build
	echo "\n# public key"
	echo -e 'untrusted comment: Local build key\nRWQ/EgKaN9SUNja2aAZ5VyPiElHhzG1GhZjs8wUewfbvy4V9ygJi7Kz3' | tee key-build.pub

	echo "# override the pubkey with 'LEDE usign key for unattended build jobs' to have the same base-files pkg and images"
	echo -e 'untrusted comment: LEDE usign key for unattended build jobs\nRWS1BD5w+adc3j2Hqg9+b66CvLR7NlHbsj7wjNVj0XGt/othDgIAOJS+' | tee key-build.pub
	echo "============================================================================="
}

# called by openwrt_two_times
# ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_download $TYPE $TARGET $CONFIG $TMPDIR
openwrt_download() {
	local TARGET=$1
	local CONFIG=$2
	local TMPBUILDDIR=$3
	local tries=5

	cd $TMPBUILDDIR/download

	# checkout the repo
	echo "================================================================================"
	echo "$(date -u) - Cloning git repository from $OPENWRT_GIT_REPO $OPENWRT_GIT_BRANCH. "
	echo "================================================================================"
	git clone -b $OPENWRT_GIT_BRANCH $OPENWRT_GIT_REPO source
	cd source

	echo "================================================================================"
	echo "$(date -u) - received git version $(git log -1 --pretty=oneline)"
	echo "================================================================================"

	# otherwise LEDE will generate new release keys every build
	openwrt_create_signing_keys

	# update feeds
	./scripts/feeds update
	./scripts/feeds install -a

	# configure openwrt because otherwise it wont download everything
	openwrt_config $CONFIG
	while ! make tools/tar/compile download -j $NUM_CPU IGNORE_ERRORS=ym BUILD_LOG=1 ; do
		tries=$((tries - 1))
		if [ $tries -eq 0 ] ; then
			echo "================================================================================"
			echo "$(date -u) - Failed to download sources"
			echo "================================================================================"
			exit 1
		fi
	done
}

openwrt_get_banner() {
	local TMPDIR=$1
	local TYPE=$2
	cd $TMPDIR/build/source
	echo "===bannerbegin==="
	find staging_dir/ -name banner | grep etc/banner|head -1| xargs cat /dev/null
	echo "===bannerend==="
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
	ssh $GENERIC_NODE1 reproducible_$TYPE node node_create_tmpdirs $TMPBUILDDIR
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_create_tmpdirs $TMPBUILDDIR
	mkdir -p $TMPBUILDDIR/download/

	# create results directory saved by jenkins as artifacts
	mkdir -p $WORKSPACE/results/

	# download and prepare openwrt on node b1
	ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_download $TARGET $CONFIG $TMPBUILDDIR

	echo "== master"
	ls -la "$TMPBUILDDIR/download/" || true
	echo "== node1"
	ssh $GENERIC_NODE1 reproducible_$TYPE node node_debug $TMPBUILDDIR
	echo "== node2"
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_debug $TMPBUILDDIR

	rsync -a $GENERIC_NODE1:$TMPBUILDDIR/download/ $TMPBUILDDIR/download/
	rsync -a $TMPBUILDDIR/download/ $GENERIC_NODE2:$TMPBUILDDIR/download/

	## first run
	RUN=b1
	ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_build $TYPE $RUN $TARGET $CONFIG $TMPBUILDDIR
	ssh $GENERIC_NODE1 reproducible_$TYPE node openwrt_get_banner $TMPBUILDDIR $TYPE > $BANNER_HTML
	# cut away everything before begin and after the end…
	# (thats noise generated by the way we run this via reproducible_common.sh)
	cat $BANNER_HTML | sed '/===bannerend===/,$d' | tac | sed '/===bannerbegin===/,$d' | tac > $BANNER_HTML

	# rsync back logs and images
	rsync -av $GENERIC_NODE1:$TMPBUILDDIR/$RUN/ $RESULTSDIR/$RUN/
	rsync -av $GENERIC_NODE1:$TMPBUILDDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b1.tar.xz
	rsync -av $GENERIC_NODE1:$TMPBUILDDIR/toolchain.html $RESULTSDIR/toolchain.html
	ssh $GENERIC_NODE1 reproducible_$TYPE node node_cleanup_tmpdirs $TMPBUILDDIR

	## second run
	RUN=b2
	ssh $GENERIC_NODE2 reproducible_$TYPE node openwrt_build $TYPE $RUN $TARGET $CONFIG $TMPBUILDDIR

	# rsync back logs and images
	rsync -av $GENERIC_NODE2:$TMPBUILDDIR/$RUN/ $RESULTSDIR/$RUN/
	rsync -av $GENERIC_NODE2:$TMPBUILDDIR/build_logs.tar.xz $WORKSPACE/results/build_logs_b2.tar.xz
	ssh $GENERIC_NODE2 reproducible_$TYPE node node_cleanup_tmpdirs $TMPBUILDDIR
}
