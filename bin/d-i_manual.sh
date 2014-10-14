#!/bin/bash

# Copyright 2012,2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

init_workspace() {
	#
	# clean
	#
	rm -fv *.deb *.dsc *_*.build *_*.changes *_*.tar.gz

	#
	# svn checkout and update is done by jenkins job
	#
	svn status
}

pdebuild_package() {
	#
	# prepare build
	#
	if [ -f /var/cache/pbuilder/base.tgz ] ; then
		sudo pbuilder --create
	else
		sudo pbuilder --update
	fi

	#
	# build
	#
	cd manual
	NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
	pdebuild --use-pdebuild-internal --debbuildopts "-j$NUM_CPU"
	# cleanup
	SOURCE=$(grep "^Source: " debian/control |cut -d " " -f2)
	sudo dcmd rm /var/cache/pbuilder/result/${SOURCE}_*changes
	cd ..
}

po2xml() {
	cd manual
	./scripts/merge_xml en
	./scripts/update_pot
	./scripts/update_po $1
	./scripts/revert_pot
	./scripts/create_xml $1
	cd ..
}

build_language() {
	#
	# this needs apt-get build-dep installation guide installed
	#
	FORMAT=$2
	# if $FORMAT is a directory and it's string length is greater or equal than 3 (so not "." or "..")
	if [ -d "$FORMAT" ] && [ ${#FORMAT} -ge 3 ]; then
		rm -rf $FORMAT
	fi
	mkdir $FORMAT
	cd manual/build
	ARCHS=$(ls arch-options)
	for ARCH in $ARCHS ; do
		# ignore kernel architectures
		if [ "$ARCH" != "hurd" ] && [ "$ARCH" != "kfreebsd" ] && [ "$ARCH" != "linux" ] ; then
			make languages=$1 architectures=$ARCH destination=../../$FORMAT/ formats=$FORMAT
		fi
	done
	cd ../..
	svn revert manual -R
	# remove directories if they are empty and in the case of pdf, leave a empty pdf
	# maybe it is indeed better not to create these jobs in the first place...
	# this is due to "Warning: pdf and ps formats are currently not supported for Chinese, Greek, Japanese and Vietnamese"
	(rmdir $FORMAT/* 2>/dev/null && rmdir $FORMAT 2>/dev/null ) || true
	if [ "$FORMAT" = "pdf" ] && [ ! -d $FORMAT ] ; then
		mkdir -p pdf/dummy
		touch pdf/dummy/dummy.pdf
	fi
}

po_cleanup() {
	echo "Cleanup generated files:"
	rm -rv manual/$1 manual/integrated
}

init_workspace
#
# if $1 is not given, build the whole manual,
# else just the language $1 in format $2
#
# $1 = LANG
# $2 = FORMAT
# $3 if set, manual is translated using po files (else xml files are the default)
if [ "$1" = "" ] ; then
	pdebuild_package
else
	if [ "$2" = "" ] ; then
		echo "Error: need format too."
		exit 1
	fi
	if [ "$3" = "" ] ; then
		build_language $1 $2
	else
		po2xml $1
		build_language $1 $2
		po_cleanup $1
	fi
fi
