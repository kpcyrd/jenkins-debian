#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

mkdir -p /srv/reproducible-results/meta_pkgsets
TMPFILE=$(mktemp)
PACKAGES=/schroots/reproducible-sid/var/lib/apt/lists/*Packages
SOURCES=/schroots/reproducible-sid/var/lib/apt/lists/*Sources

# helper function
turn_tmpfile_into_sources_list() {
	TMP2=$(mktemp)
	for PKG in $(cat $TMPFILE) ; do
		( grep-dctrl -FBinary -sPackage -n $PKG $SOURCES || echo $PKG ) >> $TMP2
	done
	mv $TMP2 $TMPFILE
}

# the required package set
grep-dctrl -FPriority -sPackage -n required $PACKAGES | sort -u > $TMPFILE
turn_tmpfile_into_sources_list
cp $TMPFILE /srv/reproducible-results/meta_pkgsets/${META_PKGSET[1]}.pkgset

# build-essential
grep-dctrl -FBuild-Essential -sPackage -n yes $PACKAGES | sort -u > $TMPFILE
turn_tmpfile_into_sources_list
cp $TMPFILE /srv/reproducible-results/meta_pkgsets/${META_PKGSET[2]}.pkgset

# gnome and everything it depends on
grep-dctrl -FDepends -sPackage -n gnome $PACKAGES | sort -u > $TMPFILE
turn_tmpfile_into_sources_list
cp $TMPFILE /srv/reproducible-results/meta_pkgsets/${META_PKGSET[3]}.pkgset

# all build depends of gnome
grep-dctrl -FBuild-Depends -sPackage -n gnome $SOURCES | sort -u > /srv/reproducible-results/meta_pkgsets/${META_PKGSET[4]}.pkgset

# tails
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.binpkgs > $TMPFILE
curl wget http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.srcpkgs >> $TMPFILE
turn_tmpfile_into_sources_list
cp $TMPFILE /srv/reproducible-results/meta_pkgsets/${META_PKGSET[5]}.pkgset

# finally
rm $TMPFILE
echo "All meta package sets created successfully."

