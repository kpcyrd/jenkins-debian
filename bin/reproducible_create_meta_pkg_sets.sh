#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

ARCH=amd64

# helper functions
convert_into_source_packages_only() {
	rm -f ${TMPFILE2}
	ALL_PKGS=$(cat $TMPFILE | cut -d ":" -f1 | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g ; s# #\n#g"  |sort -u )
	for PKG in $ALL_PKGS ; do
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

update_target() {
	mv $TMPFILE $TARGET
	echo "$(date) - $TARGET updated."
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
				diff $TARGET $TARGET.new || true
				echo
				echo "Warning: too much difference for $TARGET, aborting. Please investigate and update manually."
				KEEP=$(mktemp)
				mv $TARGET.new $KEEP
				echo "The new pkg-set has been saved as $KEEP for further investigation."
			else
				update_target
			fi
		else
			# target does not exist, create it
			update_target
		fi
	else
		echo "$(date) - $TARGET not updated, $TMPFILE is empty."
	fi
}

get_installable_set() {
	set +e
	schroot --directory /tmp -c source:jenkins-dpkg-jessie -- dose-deb-coinstall --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2} > $TMPFILE
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		rm $TMPFILE
		echo "Warning: dose-deb-coinstall cannot calculate the installable set for $1"
	fi
	set -e
}

update_pkg_sets() {
	# the essential package set
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[1]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[3]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X -FEssential yes > $TMPFILE
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[1]}.pkgset
	fi

	# the required package set
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[2]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[2]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X -FPriority required > $TMPFILE
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[2]}.pkgset
	fi

	# build-essential
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[3]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[3]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FBuild-Essential yes --or -FPackage build-essential \) > ${TMPFILE2}
		# here we want the installable set:
		get_installable_set ${META_PKGSET[3]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[3]}.pkgset
		fi
	fi

	# build-essential-depends
	#
	# This set is created using the following procedure:
	#
	#  1. take the binary package build-essential and put it into set S
	#  2. go over every package in S and
	#      2.1. if it is a binary package
	#          2.1.1 add all its Depends and Pre-Depends to S
	#          2.1.2 add the source package it builds from to S
	#      2.2. if it is a source package add all its Build-Depends,
	#           Build-Depends-Indep and Build-Depends-Arch to S
	#  3. if step 2 added new packages, repeat step 2, otherwise exit
	#
	# This set is important because a package can only be trusted if
	# also all its dependencies, all its build dependencies and
	# recursively their own dependencies and build dependencies can be
	# trusted.
	# So making this set reproducible is required to make anything
	# in the essential or build-essential set trusted.
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[4]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[4]}.pkgset ] ; then
		curl http://bootstrap.debian.net/importance_metric_all.txt > $TMPFILE2
		# retrieve the highest number in the third column (packages affect)
		HIGHEST=`sort -n -k 3 $TMPFILE2 | tail -1 | cut -f 3`
		# now get all lines where the third column is equal to this value
		awk '$3 == "'$HIGHEST'" { print $1 }' $TMPFILE2 | cut -d ':' -f 2 > $TMPFILE
		update_if_similar ${META_PKGSET[4]}.pkgset
	fi

	# popcon top 1337 installed sources
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[5]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[5]}.pkgset ] ; then
		SQL_QUERY="SELECT popcon_src.source FROM popcon_src ORDER BY popcon_src.insts DESC LIMIT 1337;"
		PGPASSWORD=public-udd-mirror \
			psql -U public-udd-mirror \
			-h public-udd-mirror.xvm.mit.edu -p 5432 \
			-t \
			udd -c"${SQL_QUERY}" > $TMPFILE
		update_if_similar ${META_PKGSET[5]}.pkgset
	fi

	# key packages (same for all suites)
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[6]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[6]}.pkgset ] ; then
		SQL_QUERY="SELECT source FROM key_packages;"
		PGPASSWORD=public-udd-mirror \
			psql -U public-udd-mirror \
			-h public-udd-mirror.xvm.mit.edu -p 5432 \
			-t \
			udd -c"${SQL_QUERY}" > $TMPFILE
		update_if_similar ${META_PKGSET[6]}.pkgset
	fi

	# installed on one or more .debian.org machines
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[7]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[7]}.pkgset ] ; then
		# one day we will get a proper data provider from DSA...
		# (so far it was a manual "dpkg --get-selections" on all machines
		# converted into a list of source packages...)
		cat /srv/jenkins/bin/reproducible_installed_on_debian.org > $TMPFILE
		update_if_similar ${META_PKGSET[7]}.pkgset
	fi

	# packages which had a DSA
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[8]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[8]}.pkgset ] ; then
		svn export svn://svn.debian.org/svn/secure-testing/data/DSA/list ${TMPFILE2}
		grep "^\[" ${TMPFILE2} | grep "DSA-" | cut -d " " -f5|sort -u > $TMPFILE
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[8]}.pkgset
	fi

	# gnome and everything it depends on
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[9]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[9]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage gnome \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[9]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[9]}.pkgset
		fi
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
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[10]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[10]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[8]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		done
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[10]}.pkgset
	fi

	# kde and everything it depends on
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[11]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[11]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage kde-full \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[11]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[11]}.pkgset
		fi
	fi
	# all build depends of kde
	rm -f $TMPFILE
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[12]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[12]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[11]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		done
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[12]}.pkgset
	fi

	# xfce and everything it depends on
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[13]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[13]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage xfce4 \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[13]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[13]}.pkgset
		fi
	fi
	# all build depends of xfce
	rm -f $TMPFILE
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[14]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[14]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[13]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		done
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[14]}.pkgset
	fi

	# tails
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[15]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[15]}.pkgset ] ; then
		curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.binpkgs > $TMPFILE
		curl http://nightly.tails.boum.org/build_Tails_ISO_feature-jessie/latest.iso.srcpkgs >> $TMPFILE
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[15]}.pkgset
	fi

	# all build depends of tails
	rm -f $TMPFILE
	if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[16]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[16]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[15]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		done
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[16]}.pkgset
	fi

	# grml
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[17]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[17]}.pkgset ] ; then
		curl http://grml.org/files/grml64-full_latest/dpkg.selections | cut -f1 > $TMPFILE
		if ! grep '<title>404 Not Found</title>' $TMPFILE ; then
			convert_into_source_packages_only
			update_if_similar ${META_PKGSET[17]}.pkgset
		else
			echo "Warning: could not download grml's latest dpkg.selections file, skipping pkg set..."
		fi
	fi

	# all build depends of grml
	rm -f $TMPFILE
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[18]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[18]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[17]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		done
		convert_into_source_packages_only
		update_if_similar ${META_PKGSET[18]}.pkgset
	fi

	# pkg-perl-maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[19]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[19]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-perl-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[19]}.pkgset
	fi

	# pkg-java-maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[20]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[20]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-java-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -FDepends -n default-jdk -sPackage $PACKAGES >> $TMPFILE
		update_if_similar ${META_PKGSET[20]}.pkgset
	fi

	# pkg-haskell-maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[21]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[21]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-haskell-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -sBuild-Depends -n -X -FPackage ghc $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		update_if_similar ${META_PKGSET[21]}.pkgset
	fi

	# pkg-ruby-extras-maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[22]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[22]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-ruby-extras-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[22]}.pkgset
	fi

	# pkg-golang-maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[23]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[23]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-golang-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -sBuild-Depends -n -X -FPackage golang $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" >> $TMPFILE
		update_if_similar ${META_PKGSET[23]}.pkgset
	fi

	# debian-boot@l.d.o maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[24]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[24]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-boot@lists.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[24]}.pkgset
	fi

	# debian-ocaml-maint@l.d.o maintainers
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[25]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[25]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-ocaml-maint@lists.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[25]}.pkgset
	fi

}

TMPFILE=$(mktemp)
TMPFILE2=$(mktemp)
for SUITE in $SUITES ; do
	if [ "$SUITE" = "experimental" ] ; then
		# no pkg sets in experimental
		continue
	fi
	echo
	echo "$(date) - Creating meta package sets for $SUITE now."
	echo

	DISTNAME="$SUITE-$ARCH"
	TPATH=/srv/reproducible-results/meta_pkgsets-$SUITE
	CHPATH=/srv/reproducible-results/chdist-$SUITE
	mkdir -p $TPATH $CHPATH

	# delete possibly existing dist
	cd $CHPATH
	rm -rf $DISTNAME
	cd -

	# the "[arch=$ARCH]" is a workaround until #774685 is fixed
	chdist --data-dir=$CHPATH --arch=$ARCH create $DISTNAME "[arch=$ARCH]" $MIRROR $SUITE main
	chdist --data-dir=$CHPATH --arch=$ARCH apt-get $DISTNAME update

	PACKAGES=$(ls $CHPATH/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_binary-${ARCH}_Packages)
	SOURCES=$(ls $CHPATH/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_source_Sources)

	# finally
	update_pkg_sets
	echo "$(date) - Done updating all meta package sets for $SUITE."
done

rm -f $TMPFILE ${TMPFILE2}
echo
