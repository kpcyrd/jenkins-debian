#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

init_workspace() {
	#
	# clean
	#
	cd ..
	rm -fv *.deb *.udeb *.dsc *_*.build *_*.changes *_*.tar.gz *_*.tar.bz2 *_*.tar.xz
	cd workspace
	#
	# git clone and pull is done by jenkins job
	#
	git config -l
	git status
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
		echo "This package is not to be supposed to be build on $(dpkg --print-architecture)"
		grep "Architecture:" debian/control
		return
	fi
	#
	# prepare build
	#
	if [ ! -f /var/cache/pbuilder/base.tgz ] ; then
		sudo pbuilder --create
	else
		ls -la /var/cache/pbuilder/base.tgz
		file /var/cache/pbuilder/base.tgz
		sudo pbuilder --update || ( sudo rm /var/cache/pbuilder/base.tgz ; sudo pbuilder --create )
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
	# FIXME: workaround: #767260 (console-setup doesnt support parallel build)
	if [ "$SOURCE" != "console-setup" ] ; then
		NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
	else
		NUM_CPU=1
	fi
	pdebuild --use-pdebuild-internal --debbuildopts "-j$NUM_CPU -b"
	# cleanup
	echo
	cat /var/cache/pbuilder/result/${SOURCE}_*changes
	echo
	sudo dcmd rm /var/cache/pbuilder/result/${SOURCE}_*changes
}

init_workspace
#
# if $1 is not given, build the package normally,
# else...
#
if [ "$1" = "" ] ; then
	pdebuild_package
else
	echo do something else ; exit 1
fi
