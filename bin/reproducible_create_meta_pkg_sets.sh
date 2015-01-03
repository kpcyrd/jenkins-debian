#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

TPATH=/srv/reproducible-results/meta_pkgsets
mkdir -p $TPATH
PACKAGES=/schroots/reproducible-sid/var/lib/apt/lists/*Packages
SOURCES=/schroots/reproducible-sid/var/lib/apt/lists/*Sources
TMPFILE=$(mktemp)

# helper functions
convert_into_source_packages_only() {
	TMP2=$(mktemp)
	for PKG in $(cat $TMPFILE) ; do
		( grep-dctrl -X -FBinary -sPackage -n $PKG $SOURCES || echo $PKG ) >> $TMP2
	done
	sort -u $TMP2 > $TMPFILE
	rm $TMP2
}
update_if_similar() {
	# this is mostly done to not accidently overwrite the lists
	# with garbage, eg. when external services are down
	TARGET=$TPATH/$1
	if [ -f $TARGET ] ; then
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
	fi
	mv $TMPFILE $TARGET
}


# the essential and required package set
grep-dctrl -sPackage -n -X \( -FEssential yes --or -FPriority required \) $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[1]}.pkgset

# build-essential
grep-dctrl -FBuild-Essential -sPackage -n yes $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[2]}.pkgset

# gnome and everything it depends on
grep-dctrl -FDepends -sPackage -n gnome $PACKAGES > $TMPFILE
schroot --directory /tmp -c source:jenkins-reproducible-sid -- apt-get -s install gnome|grep "^Inst "|cut -d " " -f2 > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[3]}.pkgset

# all build depends of gnome
for PKG in $TPATH/${META_PKGSET[3]}.pkgset ; do
	grep-dctrl -sBuild-Depends -n -X -FPackage $PKG  /schroots/sid/var/lib/apt/lists/*Sources | sed "s#([^)]*)##g; s#,##g" >> $TMPFILE
done
update_if_similar ${META_PKGSET[4]}.pkgset

# tails
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.binpkgs > $TMPFILE
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.srcpkgs >> $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[5]}.pkgset

# finally
echo "All meta package sets created successfully."

