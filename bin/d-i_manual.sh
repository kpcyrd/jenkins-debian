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
	pdebuild --use-pdebuild-internal
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
	FORMAT=$2
	# if $FORMAT is a directoy and it's string length greater or equal then 3 (so not "." or "..")
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
	rmdir $FORMAT || true
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
