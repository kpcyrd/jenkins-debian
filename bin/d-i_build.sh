#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# default settings
#
set -x
set -e
export LC_ALL=C
export MIRROR=http://ftp.de.debian.org/debian
export http_proxy="http://localhost:3128"
export

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
	ARCH=$(dpkg --print-architecture)
	EGREP_PATTERN="( all| any| $ARCH)"
	if [ ! $(grep "Architecture:" debian/control | egrep "$EGREP_PATTERN" | wc -l ) -gt 0 ] ; then
		echo "This package is not to be supposed to be build on $ARCH:"
		grep "Architecture:" debian/control
		return
	fi
	#
	# prepare build
	#
	if [ ! -f /var/cache/pbuilder/base.tgz ] ; then
		sudo pbuilder --create
	else
		sudo pbuilder --update
	fi
	#
	# 3.0 quilt is not happy without an upstream tarball
	#
	if [ "$(cat debian/source/format)" = "3.0 (quilt)" ] ; then
		uscan --download-current-version
	fi
	#
	#
	# build
	#
	NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
	pdebuild --use-pdebuild-internal --debbuildopts "-j$NUM_CPU"
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
