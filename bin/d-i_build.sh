#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

RESULT_DIR=$(readlink -f ..)
ISO_DIR=/srv/d-i/isos

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
	echo "${PREFIX}${BRANCH#origin/pu/}"
}

iso_target() {
	UI=$1 ; shift
	echo "${ISO_DIR}/mini-${UI}$(replace_origin_pu "-" $PU_GIT_BRANCH).iso"
}

preserve_artifacts() {
	#
	# Check is we're in a pu/* branch, and if so save the udebs
	#
	if PU_BRANCH_DIR=$(replace_origin_pu "/srv/udebs/" $GIT_BRANCH) ; then
		mkdir -p $PU_BRANCH_DIR
		cp ${RESULT_DIR}/*.udeb $PU_BRANCH_DIR

		if [ "$HOSTNAME" = "jenkins" ] ; then
			# FIXME this rsync should probably be in a separate job that the one on pb10 could then depend on -- otherwise race conditions seem to lurk
			rsync -e "ssh -o 'Batchmode = yes'" -r profitbricks-build10-amd64.debian.net:$PU_BRANCH_DIR/ $PU_BRANCH_DIR/
		fi
	fi

	#
	# Alternatively, if we built an images tarball and were triggered by a pu/ branch
	#
	IMAGETAR=${RESULT_DIR}/debian-installer-images_*.tar.gz
	if [ -f $IMAGETAR -a "$PU_GIT_BRANCH" ] ; then
		[ -d ${ISO_DIR} ] || mkdir ${ISO_DIR}

		tar -xvzf $IMAGETAR --no-anchored mini.iso
		sha256sum installer-*/*/images/netboot/gtk/mini.iso installer-*/*/images/netboot/mini.iso
		mv -f installer-*/*/images/netboot/gtk/mini.iso $(iso_target gtk)
		mv -f installer-*/*/images/netboot/mini.iso $(iso_target text)
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
	# if we got a valid PU_GIT_BRANCH passed in as a parameter from the triggering job
	# then grab the generated udebs.  FIXME -- we need to work work out a way of cleaning up old branches
	#
	if PU_BRANCH_DIR=$(replace_origin_pu "/srv/udebs/" $PU_GIT_BRANCH) ; then
		cp $PU_BRANCH_DIR/* build/localudebs
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
