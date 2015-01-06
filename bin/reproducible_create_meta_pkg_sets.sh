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
PACKAGES=/schroots/clean-sid/var/lib/apt/lists/*Packages
SOURCES=/schroots/clean-sid/var/lib/apt/lists/*Sources
TMPFILE=$(mktemp)

# helper functions
convert_into_source_packages_only() {
	TMP2=$(mktemp)
	for PKG in $(cat $TMPFILE) ; do
		[ -z "$PKG" ] || ( grep-dctrl -X -n -FPackage -sSource $PKG $PACKAGES || echo $PKG ) >> $TMP2
	done
	# grep-dctrl outpu might include versions (space seperated) and archs (colon seperated)
	# and duplicates
	cut -d " " -f1 $TMP2 | cut -d ":" -f1 | sort -u > $TMPFILE
	rm $TMP2
}
update_if_similar() {
	# this is mostly done to not accidently overwrite the lists
	# with garbage, eg. when external services are down
	if [ -s $TMPFILE ] ; then
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
		echo "$(date) - $TARGET updated."
	else
		echo "$(date) - $TARGET not updated, $TMPFILE is empty."
	fi
}


#
# main
#

# the essential package set
grep-dctrl -sPackage -n -X -FEssential yes $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[1]}.pkgset

# the required package set
grep-dctrl -sPackage -n -X -FPriority required $PACKAGES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[2]}.pkgset

# build-essential
grep-dctrl -FBuild-Essential -sPackage -n yes $PACKAGES > $TMPFILE
schroot --directory /tmp -c source:jenkins-clean-sid -- apt-get -s install build-essential | grep "^Inst "|cut -d " " -f2 >> $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[3]}.pkgset

# gnome and everything it depends on
schroot --directory /tmp -c source:jenkins-clean-sid -- apt-get -s install gnome | grep "^Inst "|cut -d " " -f2 > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[4]}.pkgset

# all build depends of gnome
for PKG in $(cat $TPATH/${META_PKGSET[4]}.pkgset) ; do
	grep-dctrl -sBuild-Depends -n -X -FPackage $PKG  /schroots/sid/var/lib/apt/lists/*Sources | sed "s#([^)]*)##g; s#,##g" >> $TMPFILE
done
convert_into_source_packages_only
update_if_similar ${META_PKGSET[5]}.pkgset

# tails
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.binpkgs > $TMPFILE
curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.srcpkgs >> $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[6]}.pkgset

# all build depends of tails
for PKG in $(cat $TPATH/${META_PKGSET[6]}.pkgset) ; do
	grep-dctrl -sBuild-Depends -n -X -FPackage $PKG  /schroots/sid/var/lib/apt/lists/*Sources | sed "s#([^)]*)##g; s#,##g" >> $TMPFILE
done
convert_into_source_packages_only
update_if_similar ${META_PKGSET[7]}.pkgset

# pkg-perl-maintainers
grep-dctrl -sPackage -n -FMaintainer pkg-perl-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
convert_into_source_packages_only
update_if_similar ${META_PKGSET[8]}.pkgset

# popcon top 1337 installed sources
SQL_QUERY="SELECT popcon_src.source FROM popcon_src ORDER BY popcon_src.insts DESC LIMIT 1337;"
PGPASSWORD=public-udd-mirror \
	psql -U public-udd-mirror \
	-h public-udd-mirror.xvm.mit.edu -p 5432 \
	-t \
	udd -c"${SQL_QUERY}" > $TMPFILE
update_if_similar ${META_PKGSET[9]}.pkgset


# finally
echo "All meta package sets created successfully."

