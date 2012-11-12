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
	rm -fv *.deb *.udeb *.dsc *_*.build *_*.changes *_*.tar.gz

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
	ARCH=$(dpkg --print-architecture)
	EGREP_PATTERN="'( all| any| $ARCH)'"
	if [ ! $(grep Architecture: debian/control | egrep -q $EGREP_PATTERN) ] ; then
		echo "This package is not to be supposed to be build on $ARCH."
		grep Architecture: debian/control
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
	# build
	#
	pdebuild
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
