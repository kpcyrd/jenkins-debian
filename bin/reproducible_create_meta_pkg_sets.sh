#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

TPATH=/srv/reproducible-results/meta_pkgsets
mkdir -p $TPATH

ARCH=amd64
SUITE=sid
DISTNAME="$SUITE-$ARCH"

PACKAGES=`echo ~/.chdist/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_binary-${ARCH}_Packages`
SOURCES=`echo ~/.chdist/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_source_Sources`
TMPFILE=$(mktemp)
TMPFILE2=$(mktemp)

# delete possibly existing dist
rm -rf ~/.chdist/$DISTNAME;

# the "[arch=amd64]" is a workaround until #774685 is fixed
chdist --arch=$ARCH create $DISTNAME "[arch=amd64]" $MIRROR $SUITE main
chdist --arch=$ARCH apt-get $DISTNAME update

# helper functions
convert_into_source_packages_only() {
	rm -f ${TMPFILE2}
	for PKG in $(cat $TMPFILE | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" |sort -u ) ; do
		SRC=""
		if [ ! -z "$PKG" ] ; then
			SRC=$(grep-dctrl -X -n -FPackage -sSource $PKG $PACKAGES || true )
			[ ! -z "$SRC" ] || SRC=$(grep-dctrl -X -n -FPackage -sPackage $PKG $PACKAGES || true)
		fi
		[ ! -z "$SRC" ] || SRC=$(echo $PKG )
		echo $SRC >> ${TMPFILE2}
	done
	# grep-dctrl output might include versions (space seperated) and archs (colon seperated)
	# and duplicates
	cut -d " " -f1 ${TMPFILE2} | cut -d ":" -f1 | sort -u > $TMPFILE
	rm ${TMPFILE2}
}

convert_from_deb822_into_source_packages_only() {
	# given a Packages file in deb822 format on standard input, the
	# following perl "oneliner" outputs the associated (unversioned)
	# source package names, one per line
	perl -e 'use Dpkg::Control;while(1){$c=Dpkg::Control->new();' \
		-e 'last if not $c->parse(STDIN);$p=$c->{"Package"};' \
		-e '$s=$c->{"Source"};if (not defined $s){print "$p\n"}' \
		-e 'else{$s=~s/\s*([\S]+)\s+.*/\1/;print "$s\n"}}' \
		> ${TMPFILE2} < $TMPFILE
	sort -u ${TMPFILE2} > $TMPFILE
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
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[1]}.pkgset) ] ; then
	chdist grep-dctrl-packages $DISTNAME -X -FEssential yes > ${TMPFILE2}
	schroot --directory /tmp -c source:jenkins-dpkg-jessie dose-deb-coinstall --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2} > $TMPFILE
	convert_from_deb822_into_source_packages_only
	update_if_similar ${META_PKGSET[1]}.pkgset
fi

# the required package set
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[2]}.pkgset) ] ; then
	chdist grep-dctrl-packages $DISTNAME -X -FPriority required > ${TMPFILE2}
	schroot --directory /tmp -c source:jenkins-dpkg-jessie dose-deb-coinstall --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2} > $TMPFILE
	convert_from_deb822_into_source_packages_only
	update_if_similar ${META_PKGSET[2]}.pkgset
fi

# build-essential
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[3]}.pkgset) ] ; then
	chdist grep-dctrl-packages $DISTNAME -X \( -FBuild-Essential yes --or -FPackage build-essential \) > ${TMPFILE2}
	schroot --directory /tmp -c source:jenkins-dpkg-jessie dose-deb-coinstall --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2} > $TMPFILE
	convert_from_deb822_into_source_packages_only
	update_if_similar ${META_PKGSET[3]}.pkgset
fi

# gnome and everything it depends on
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[4]}.pkgset) ] ; then
	chdist grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage gnome \) > ${TMPFILE2}
	schroot --directory /tmp -c source:jenkins-dpkg-jessie dose-deb-coinstall --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2} > $TMPFILE
	convert_from_deb822_into_source_packages_only
	update_if_similar ${META_PKGSET[4]}.pkgset
fi

# The build-depends of X tasks can be solved once dose-ceve is able to read
# Debian source packages (possible in dose3 git but needs a new dose3 release
# and upload to unstable)
#
# Ignoring parsing issues, the current method is unable to resolve virtual
# build dependencies
#
# The current method also ignores Build-Depends-Indep and Build-Depends-Arch

# all build depends of gnome
rm -f $TMPFILE
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[5]}.pkgset) ] ; then
	for PKG in $(cat $TPATH/${META_PKGSET[4]}.pkgset) ; do
		grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
	done
	convert_into_source_packages_only
	update_if_similar ${META_PKGSET[5]}.pkgset
fi

# tails
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[6]}.pkgset) ] ; then
	curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.binpkgs > $TMPFILE
	curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.srcpkgs >> $TMPFILE
	convert_into_source_packages_only
	update_if_similar ${META_PKGSET[6]}.pkgset
fi

# all build depends of tails
rm -f $TMPFILE
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[7]}.pkgset) ] ; then
	for PKG in $(cat $TPATH/${META_PKGSET[6]}.pkgset) ; do
		grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
	done
	convert_into_source_packages_only
	update_if_similar ${META_PKGSET[7]}.pkgset
fi

# pkg-perl-maintainers
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[8]}.pkgset) ] ; then
	grep-dctrl -sPackage -n -FMaintainer pkg-perl-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
	convert_into_source_packages_only
	update_if_similar ${META_PKGSET[8]}.pkgset
fi

# popcon top 1337 installed sources
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[9]}.pkgset) ] ; then
	SQL_QUERY="SELECT popcon_src.source FROM popcon_src ORDER BY popcon_src.insts DESC LIMIT 1337;"
	PGPASSWORD=public-udd-mirror \
		psql -U public-udd-mirror \
		-h public-udd-mirror.xvm.mit.edu -p 5432 \
		-t \
		udd -c"${SQL_QUERY}" > $TMPFILE
	update_if_similar ${META_PKGSET[9]}.pkgset
fi

# installed on one or more .debian.org machines
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[10]}.pkgset) ] ; then
	# FIXME: get a proper data provider from DSA... 
	# (so far it was a manual "dpkg --get-selections" on all machines
	# converted into a list of source packages...)
	cat /srv/jenkins/bin/reproducible_installed_on_debian.org > $TMPFILE
	update_if_similar ${META_PKGSET[10]}.pkgset
fi

# packages which had a DSA
if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[11]}.pkgset) ] ; then
	svn export svn://svn.debian.org/svn/secure-testing/data/DSA/list ${TMPFILE2}
	grep DSA ${TMPFILE2} | cut -d " " -f5|sort -u > $TMPFILE
	convert_into_source_packages_only
	update_if_similar ${META_PKGSET[11]}.pkgset
fi

# finally
rm -f $TMPFILE ${TMPFILE2}
echo "All meta package sets created successfully."
