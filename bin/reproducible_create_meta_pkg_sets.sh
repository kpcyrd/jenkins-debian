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

# helper functions
convert_into_source_packages_only() {
	TMP2=$(mktemp)
	for PKG in $(cat $TMPFILE) ; do
		( grep-dctrl -FBinary -sPackage -n $PKG $SOURCES || echo $PKG ) >> $TMP2
	done
	sort -u $TMP2 > $TMPFILE
	rm $TMP2
}
update_if_similar() {
	# this is mostly done to not accidently overwrite the lists
	# with garbage, eg. when external services are down
	TARGET=/srv/reproducible-results/meta_pkgsets/$1
	LENGTH=$(cat $TARGET | wc -w)
	NEWLEN=$(cat $TMPFILE | wc -w)
	PERCENT=$(echo "$LENGTH*100/$NEWLEN"|bc)
	if [ $PERCENT -gt 107 ] || [ $PERCENT -lt 93 ] ; then
		mv $TMPFILE $TARGET.new
		echo 
		echo diff $TARGET $TARGET.new
		diff $TARGET $TARGET.new
		echo
		echo "Too much difference, aborting. Please investigate and update manually."
		exit 1
	fi
	cp $TMPFILE $TARGET
}


# the required package set
grep-dctrl -FPriority -sPackage -n required $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[1]}.pkgset

# build-essential
grep-dctrl -FBuild-Essential -sPackage -n yes $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[2]}.pkgset

# gnome and everything it depends on
grep-dctrl -FDepends -sPackage -n gnome $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[3]}.pkgset

# all build depends of gnome
grep-dctrl -FBuild-Depends -sPackage -n gnome $SOURCES > $TMPFILE
update_if_similar ${META_PKGSET[4]}.pkgset

# tails
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.binpkgs > $TMPFILE
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.srcpkgs >> $TMPFILE
cat $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[5]}.pkgset

# finally
rm $TMPFILE
echo "All meta package sets created successfully."

