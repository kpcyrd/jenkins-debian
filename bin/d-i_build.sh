#!/bin/bash

# Copyright 2012-2016 Holger Levsen <holger@layer-acht.org>
# 		 2016 Phil Hands <phil@hands.com>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

RESULT_DIR=$(readlink -f ..)
ISO_DIR=/srv/d-i/isos
LVC_HOST=profitbricks-build10-amd64.debian.net

[ -v GIT_BRANCH ] || GIT_BRANCH="$(git branch -r --contains $GIT_COMMIT | tail -1 | cut -c3-)"

clean_workspace() {
	#
	# clean
	#
	cd $WORKSPACE
	cd ..
	rm -fv *.deb *.udeb *.dsc *_*.build *_*.changes *_*.tar.gz *_*.tar.bz2 *_*.tar.xz *_*.buildinfo
	cd $WORKSPACE
	git clean -dfx
	git reset --hard
	#
	# git clone and pull is done by jenkins job
	#
	if [ -d .git ] ; then
		echo "git status:"
		git status
	elif [ -f .svn ] ; then
		echo "svn status:"
		svn status
	fi
	echo
}

replace_origin_pu() {
	PREFIX=$1 ; shift
	BRANCH=$1 ; shift
	expr "$BRANCH" : 'origin/pu/' >/dev/null || return 1
	echo "${PREFIX}pu_${BRANCH#origin/pu/}"
}

iso_target() {
	UI=$1 ; shift
	BRANCH=$1 ; shift
	echo "${ISO_DIR}/mini-${UI}${BRANCH}.iso"
}

preserve_artifacts() {
	#
	# Check is we're in a pu/* branch, and if so save the udebs
	#
	if udeb_dir=$(replace_origin_pu "/srv/udebs/" $GIT_BRANCH) ; then
		mkdir -p $udeb_dir
		cp ${RESULT_DIR}/*.udeb $udeb_dir
		# this is put into env.txt below, so that the variable(s) can be injected into the jenkins environment
		ENV_TO_INJECT="OUR_BRANCH=$GIT_BRANCH"
	fi

	#
	# Alternatively, if we built an images tarball and were triggered by a pu/ branch
	#
	IMAGETAR=${RESULT_DIR}/debian-installer-images_*.tar.gz
	if [ -f $IMAGETAR -a "$TRIGGERING_BRANCH" ] ; then
		[ -d ${ISO_DIR} ] || mkdir ${ISO_DIR}

		echo "untaring the .iso images from $IMAGETAR:"
		tar -xvzf $IMAGETAR --no-anchored mini.iso
		echo "sha256sum of .iso images:"
		sha256sum installer-*/*/images/netboot/gtk/mini.iso installer-*/*/images/netboot/mini.iso
		echo "move them into place..."
		BRANCH=$(replace_origin_pu "-" $TRIGGERING_BRANCH)
		mv -f installer-*/*/images/netboot/gtk/mini.iso $(iso_target gtk $BRANCH)
		mv -f installer-*/*/images/netboot/mini.iso $(iso_target text $BRANCH)
		echo "and see if they are there (listing creation time):"
		ls -ltrc $ISO_DIR

		if [ "$HOSTNAME" = "jenkins" ] ; then
			# FIXME this rsync should probably be in a separate job that the one on pb10 could then depend on -- otherwise race conditions seem to lurk
			echo "and rsync them to the target node ($LVC_HOST):"
			ssh -o 'Batchmode = yes' $LVC_HOST mkdir -p $ISO_DIR
			rsync -v -e "ssh -o 'Batchmode = yes'" -r $ISO_DIR/ $LVC_HOST:$ISO_DIR/
		fi
	fi
}

pdebuild_package() {
	#
	# check if we need to do anything
	#
	if [ ! -f debian/control ] ; then
		# the Warning: will make the build end in status "unstable" but not "failed"
		echo "Warning: A source package without debian/control, so no build will be tried."
		return
	fi
	if [ $(dh_listpackages | sed '/^$/d' | wc -l) -eq 0 ]; then
		echo "This package is not supposed to be built on $(dpkg --print-architecture)"
		grep "Architecture:" debian/control
		return
	fi
	#
	# prepare build
	#
	if [ ! -f /var/cache/pbuilder/base.tgz ] ; then
		sudo pbuilder --create --http-proxy $http_proxy
	else
		ls -la /var/cache/pbuilder/base.tgz
		file /var/cache/pbuilder/base.tgz
		sudo pbuilder --update --http-proxy $http_proxy || ( sudo rm /var/cache/pbuilder/base.tgz ; sudo pbuilder --create )
	fi
	#
	# 3.0 quilt is not happy without an upstream tarball
	#
	if [ "$(cat debian/source/format)" = "3.0 (quilt)" ] ; then
		uscan --download-current-version --symlink
	fi
	#
	#
	# build (binary packages only, as sometimes we cannot get the upstream tarball...)
	#
	SOURCE=$(dpkg-parsechangelog |grep ^Source: | cut -d " " -f2)
	# workaround #767260 (console-setup doesn't support parallel build)
	if [ "$SOURCE" != "console-setup" ] ; then
		NUM_CPU=$(grep -c '^processor' /proc/cpuinfo)
	else
		NUM_CPU=1
	fi
	#
	# if we got a valid TRIGGERING_BRANCH passed in as a parameter from the triggering job
	# then grab the generated udebs.  FIXME -- we need to work work out a way of cleaning up old branches
	#
	if udeb_dir=$(replace_origin_pu "/srv/udebs/" $TRIGGERING_BRANCH) ; then
		cp $udeb_dir/* build/localudebs
	fi
	pdebuild --use-pdebuild-internal --debbuildopts "-j$NUM_CPU -b" --buildresult ${RESULT_DIR} -- --http-proxy $http_proxy
	# cleanup
	echo
	cat ${RESULT_DIR}/${SOURCE}_*changes
	echo
	preserve_artifacts
	sudo dcmd rm ${RESULT_DIR}/${SOURCE}_*changes
}

clean_workspace
#
# if $1 is not given, build the package normally,
# else...
#
if [ "$1" = "" ] ; then
	pdebuild_package
else
	echo do something else ; exit 1
fi
clean_workspace

# write out the environment variable(s) for injection into jenkins job
echo "$ENV_TO_INJECT" > env.txt
