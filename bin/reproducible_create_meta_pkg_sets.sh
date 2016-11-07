#!/bin/bash

# Copyright 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# we only generate the meta pkg sets on amd64
# (else this script would need a lot of changes for little gain)
# but these are source package sets so there is a difference only very rarely anyway
ARCH=amd64

# everything should be ok…
WARNING=false
ABORT=false

# helper functions
packages_list_to_deb822() {
	ALL_PKGS=$(cat $TMPFILE | cut -d ":" -f1 | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g ; s# #\n#g"  |sort -u | tr '\n' '|')
	grep-dctrl -F Package -e '^('"$ALL_PKGS"')$' $PACKAGES > $TMPFILE
}

tails_build_manifest_to_deb822() {
	tmpfile="$1"
	packages="$2"
	ALL_PKGS=$(python3 - "$tmpfile" <<EOF
import sys
import yaml
with open(sys.argv[1]) as fd:
	manifest = yaml.load(fd)
	seen = {}
	for pkg in (manifest['packages']['binary'] + manifest['packages']['source']):
		pkgname = pkg['package']
		if not pkgname in seen:
			print(pkgname, end='|')
			seen[pkgname] = True
EOF
)
	grep-dctrl -F Package -e '^('"$ALL_PKGS"')$' $packages > "$tmpfile"
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
	rm -f ${TMPFILE2}
}

update_target() {
	mv $TMPFILE $TARGET
	echo "$(date -u) - $TARGET updated."
	echo "============================================================================="
}

update_if_similar() {
	# this is mostly done to not accidently overwrite the lists
	# with garbage, eg. when external services are down
	if [ -s $TMPFILE ] ; then
		sort -u $TMPFILE > ${TMPFILE2}
		mv ${TMPFILE2} $TMPFILE
		TARGET=$TPATH/$1
		if [ -f $TARGET ] ; then
			LENGTH=$(cat $TARGET | wc -w)
			NEWLEN=$(cat $TMPFILE | wc -w)
			PERCENT=$(echo "$LENGTH*100/$NEWLEN"|bc)
			if [ $PERCENT -gt 110 ] || [ $PERCENT -lt 90 ] ; then
				mv $TMPFILE $TARGET.new
				echo
				echo "Warning: too much difference for $TARGET, aborting. Please investigate and update manually:"
				WARNING=true
				echo
				echo diff -u $TARGET $TARGET.new
				diff -u $TARGET $TARGET.new || true
				echo
				KEEP=$(mktemp --tmpdir=$TEMPDIR pkg-set-check-XXXXXXXXXX)
				mv $TARGET.new $KEEP
				echo "The new pkg-set has been saved as $KEEP for further investigation."
				echo "wc -l $TARGET $KEEP)"
				wc -l $TARGET $KEEP | grep -v " total"
				echo
				echo "To update the package set run:"
				echo "cp $KEEP $TARGET"
				echo
				echo "============================================================================="
			else
				update_target
			fi
		else
			# target does not exist, create it
			update_target
		fi
	else
		echo "$(date -u) - $TARGET not updated, $TMPFILE is empty."
	fi
}

get_installable_set() {
	set +e
	echo "$(date -u) - Calculating the installable set for $1"
	dose-deb-coinstall --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2} > $TMPFILE
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		rm -f $TMPFILE
		MESSAGE="Warning: dose-deb-coinstall cannot calculate the installable set for $1"
		irc_message debian-reproducible $MESSAGE
		dose-deb-coinstall --explain --failures --deb-native-arch=$ARCH --bg=$PACKAGES --fg=${TMPFILE2}
		ABORT=true
	fi
	rm -f ${TMPFILE2}
	set -e
}

progress_info_begin() {
	local table=$1
	echo "$(date -u) - Checking ${META_PKGSET[$table]}.pkgset for updates."
}

progress_info_end() {
	local table=$1
	echo "$(date -u) - Done checking ${META_PKGSET[$table]}.pkgset for updates."
}

update_pkg_sets() {
	# the essential package set
	progress_info_begin 1
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[1]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[1]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X -FEssential yes > $TMPFILE
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[1]}.pkgset
	fi
	progress_info_end 1

	# the required package set
	progress_info_begin 2
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[2]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[2]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X -FPriority required > $TMPFILE
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[2]}.pkgset
	fi
	progress_info_end 2

	# build-essential
	progress_info_begin 3
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[3]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[3]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FBuild-Essential yes --or -FPackage build-essential \) > ${TMPFILE2}
		# here we want the installable set:
		get_installable_set ${META_PKGSET[3]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[3]}.pkgset
		fi
	fi
	progress_info_end 3

	# build-essential-depends
	#
	# This set is created using the following procedure:
	#
	#  1. take the binary package build-essential and put it into set S
	#  2. go over every package in S and
	#      2.1. if it is a binary package
	#          2.1.1 add all its strong dependencies to S
	#          2.1.2 add the source package it builds from to S
	#      2.2. if it is a source package add all its strong dependencies
	#           to S
	#  3. if step 2 added new packages, repeat step 2, otherwise exit
	#
	# Strong dependencies are those direct or indirect dependencies of
	# a package without which the package cannot be installed.
	#
	# This set is important because a package can only be trusted if
	# also all its dependencies, all its build dependencies and
	# recursively their own dependencies and build dependencies can be
	# trusted.
	# So making this set reproducible is required to make anything
	# in the essential or build-essential set trusted.
	# Since this is only the strong set, it is a minimal set. In reality
	# more packages are needed to build build-essential
	progress_info_begin 4
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[4]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[4]}.pkgset ] ; then
		grep-dctrl --exact-match --field Package build-essential "$PACKAGES" \
			| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-latest-version - - \
			| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-bin2src --deb-native-arch="$ARCH" - "$SOURCES" \
			| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-create-graph --deb-drop-b-d-indep --quiet --deb-native-arch="$ARCH" --strongtype --bg "$SOURCES" "$PACKAGES" - \
			| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-buildgraph2packages - "$PACKAGES" \
			| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-bin2src --deb-native-arch="$ARCH" - "$SOURCES" \
			| grep-dctrl --no-field-names --show-field=Package '' > $TMPFILE
		update_if_similar ${META_PKGSET[4]}.pkgset
	fi
	progress_info_end 4

	# popcon top 1337 installed sources
	progress_info_begin 5
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[5]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[5]}.pkgset ] ; then
		SQL_QUERY="SELECT popcon_src.source FROM popcon_src ORDER BY popcon_src.insts DESC LIMIT 1337;"
		PGPASSWORD=public-udd-mirror \
			psql -U public-udd-mirror \
			-h public-udd-mirror.xvm.mit.edu -p 5432 \
			-t \
			udd -c"${SQL_QUERY}" > $TMPFILE
		update_if_similar ${META_PKGSET[5]}.pkgset
	fi
	progress_info_end 5

	# key packages (same for all suites)
	progress_info_begin 6
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[6]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[6]}.pkgset ] ; then
		SQL_QUERY="SELECT source FROM key_packages;"
		PGPASSWORD=public-udd-mirror \
			psql -U public-udd-mirror \
			-h public-udd-mirror.xvm.mit.edu -p 5432 \
			-t \
			udd -c"${SQL_QUERY}" > $TMPFILE
		update_if_similar ${META_PKGSET[6]}.pkgset
	fi
	progress_info_end 6

	# installed on one or more .debian.org machines
	progress_info_begin 7
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[7]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[7]}.pkgset ] ; then
		# one day we will get a proper data provider from DSA...
		# (so far it was a manual "dpkg --get-selections" on all machines
		# converted into a list of source packages...)
		cat /srv/jenkins/bin/reproducible_installed_on_debian.org > $TMPFILE
		update_if_similar ${META_PKGSET[7]}.pkgset
	fi
	progress_info_end 7

	# packages which had a DSA
	progress_info_begin 8
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[8]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[8]}.pkgset ] ; then
		rm -f ${TMPFILE2}
		svn export svn://svn.debian.org/svn/secure-testing/data/DSA/list ${TMPFILE2}
		grep "^\[" ${TMPFILE2} | grep "DSA-" | cut -d " " -f5 > $TMPFILE
		update_if_similar ${META_PKGSET[8]}.pkgset
	fi
	progress_info_end 8

	# packages from the cii-census
	progress_info_begin 9
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[9]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[9]}.pkgset ] ; then
		CII=$(mktemp --tmpdir=$TEMPDIR pkg-sets-XXXXXXXXX -u)
		git clone --depth 1 https://github.com/linuxfoundation/cii-census.git $CII
		csvtool -t ',' col 1 $CII/results.csv | grep -v "project_name" > $TMPFILE
		MISSES=""
		# convert binary packages into source packages
		for i in $(cat $TMPFILE) ; do
			chdist --data-dir=$CHPATH apt-cache $DISTNAME show $i >> ${TMPFILE2} 2>/dev/null || MISSES="$i $MISSES"
		done
		echo "The following unknown packages have been ignored: $MISSES"
		mv ${TMPFILE2} $TMPFILE
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[9]}.pkgset
		rm $CII -r
	fi
	progress_info_end 9

	# gnome and everything it depends on
	progress_info_begin 10
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[10]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[10]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage gnome \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[10]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[10]}.pkgset
		fi
	fi
	progress_info_end 10

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
	progress_info_begin 11
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[11]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[11]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[10]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[11]}.pkgset
	fi
	progress_info_end 11

	# kde and everything it depends on
	progress_info_begin 12
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[12]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[12]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage kde-full --or -FPackage kde-standard \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[12]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			# also add the packages maintained by those teams
			# (maybe add the depends of those packages too?)
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-qt-kde@lists.debian.org $SOURCES >> $TMPFILE
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-kde-extras@lists.alioth.debian.org $SOURCES >> $TMPFILE
			update_if_similar ${META_PKGSET[12]}.pkgset
		fi
	fi
	progress_info_end 12

	# all build depends of kde
	rm -f $TMPFILE
	progress_info_begin 13
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[13]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[13]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[12]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[13]}.pkgset
	fi
	progress_info_end 13

	# mate and everything it depends on
	progress_info_begin 14
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[14]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[14]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage mate-desktop-environment --or -FPackage mate-desktop-environment-extras \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[14]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			# also add the packages maintained by the team
			# (maybe add the depends of those packages too?)
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-mate-team@lists.alioth.debian.org $SOURCES >> $TMPFILE
			update_if_similar ${META_PKGSET[14]}.pkgset
		fi
	fi
	progress_info_end 14

	# all build depends of mate
	progress_info_begin 15
	rm -f $TMPFILE
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[15]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[15]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[14]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[15]}.pkgset
	fi
	progress_info_end 15

	# xfce and everything it depends on
	progress_info_begin 16
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[16]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[16]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage xfce4 \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[16]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[16]}.pkgset
		fi
	fi
	progress_info_end 16

	# all build depends of xfce
	rm -f $TMPFILE
	progress_info_begin 17
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[17]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[17]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[16]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[17]}.pkgset
	fi
	progress_info_end 17

	# freedombox-setup and plinth and everything they depend on
	progress_info_begin 18
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[18]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[18]}.pkgset ] ; then
		chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage freedombox-setup --or -FPackage plinth \) > ${TMPFILE2}
		get_installable_set ${META_PKGSET[18]}.pkgset
		if [ -f $TMPFILE ] ; then
			convert_from_deb822_into_source_packages_only
			# hardcoded list of source packages
			# derived from looking at "@package.required" in $src-plinth/plinth/modules/*py
			# see https://wiki.debian.org/FreedomBox/Manual/Developer#Specifying_module_dependencies
			for PKG in avahi deluge easy-rsa ejabberd ez-ipupdate firewalld ikiwiki jwchat monkeysphere mumble network-manager ntp obfs4proxy openvpn owncloud php-dropbox php5 postgresql-common privoxy python-letsencrypt quassel roundcube shaarli sqlite3 tor torsocks transmission unattended-upgrades ; do
				echo $PKG >> $TMPFILE
			done
			update_if_similar ${META_PKGSET[18]}.pkgset
		fi
	fi
	progress_info_end 18

	# all build depends of freedombox-setup and plinth
	rm -f $TMPFILE
	progress_info_begin 19
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[19]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[19]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[18]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[19]}.pkgset
	fi
	progress_info_end 19

	# grml
	progress_info_begin 20
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[20]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[20]}.pkgset ] ; then
		curl http://grml.org/files/grml64-full_latest/dpkg.selections | cut -f1 > $TMPFILE
		if ! grep '<title>404 Not Found</title>' $TMPFILE ; then
			echo "parsing $TMPFILE now..."
			packages_list_to_deb822
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[20]}.pkgset
		else
			MESSAGE="Warning: could not download grml's latest dpkg.selections file, skipping pkg set..."
			irc_message debian-reproducible $MESSAGE
			ABORT=true
		fi
	fi
	progress_info_end 20

	# all build depends of grml
	rm -f $TMPFILE
	progress_info_begin 21
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[21]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[21]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[20]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		echo "parsing $TMPFILE now..."
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[21]}.pkgset
	fi
	progress_info_end 21

	# tails
	progress_info_begin 22
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[22]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[22]}.pkgset ] ; then
		curl http://nightly.tails.boum.org/build_Tails_ISO_feature-stretch/lastSuccessful/archive/latest.iso.build-manifest > $TMPFILE
		if ! grep '<title>404 Not Found</title>' $TMPFILE ; then
			echo "parsing $TMPFILE now..."
			tails_build_manifest_to_deb822 "$TMPFILE" "$PACKAGES"
			convert_from_deb822_into_source_packages_only
			update_if_similar ${META_PKGSET[22]}.pkgset
		else
			MESSAGE="Warning: could not download tail's latest packages file(s), skipping tails pkg set..."
			irc_message debian-reproducible $MESSAGE
			ABORT=true
		fi
	fi
	progress_info_end 22

	# all build depends of tails
	rm -f $TMPFILE
	progress_info_begin 23
	if [ -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[23]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[23]}.pkgset ] ; then
		for PKG in $(cat $TPATH/${META_PKGSET[22]}.pkgset) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		echo "parsing $TMPFILE now..."
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[23]}.pkgset
	fi
	progress_info_end 23

	# installed by Subgraph OS
	progress_info_begin 24
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[24]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[24]}.pkgset ] ; then
		# one day we will get a proper data provider from Subgraph OSA...
		# (so far it was a manual "dpkg -l")
		cat /srv/jenkins/bin/reproducible_installed_by_subgraphos > $TMPFILE
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[24]}.pkgset
	fi
	progress_info_end 24

	# all build depends of Subgraph OS
	rm -f $TMPFILE
	progress_info_begin 25
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[25]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[25]}.pkgset ] ; then
		for PKG in $(cat /srv/jenkins/bin/reproducible_installed_by_subgraphos) ; do
			grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		done
		packages_list_to_deb822
		convert_from_deb822_into_source_packages_only
		update_if_similar ${META_PKGSET[25]}.pkgset
	fi
	progress_info_end 25

	# debian-boot@l.d.o maintainers
	progress_info_begin 26
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[26]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[26]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-boot@lists.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[26]}.pkgset
	fi
	progress_info_end 26

	# Debian Med Packaging Team <debian-med-packaging@lists.alioth.debian.org>
	progress_info_begin 27
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[27]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[27]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-med-packaging@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[27]}.pkgset
	fi
	progress_info_end 27

	# debian-ocaml-maint@l.d.o maintainers
	progress_info_begin 28
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[28]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[28]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-ocaml-maint@lists.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[28]}.pkgset
	fi
	progress_info_end 28

	# debian python maintainers
	progress_info_begin 29
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[29]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[29]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders python-modules-team@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -sPackage -n -FMaintainer,Uploaders python-apps-team@lists.alioth.debian.org $SOURCES >> $TMPFILE
		update_if_similar ${META_PKGSET[29]}.pkgset
	fi
	progress_info_end 29

	# debian-qa maintainers
	progress_info_begin 30
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[30]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[30]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders packages@qa.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[30]}.pkgset
	fi
	progress_info_end 30

	# Debian Science Team
	progress_info_begin 31
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[31]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[31]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-science-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[31]}.pkgset
	fi
	progress_info_end 31

	# debian-x@l.d.o maintainers
	progress_info_begin 32
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[32]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[32]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-x@lists.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[32]}.pkgset
	fi
	progress_info_end 32

	# lua packages
	progress_info_begin 33
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[33]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[33]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FPackage -e ^lua.* $SOURCES > $TMPFILE
		grep-dctrl -sPackage -n -FBuild-Depends dh-lua $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		update_if_similar ${META_PKGSET[33]}.pkgset
	fi
	progress_info_end 33

	# pkg-fonts-devel
	progress_info_begin 34
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[34]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[34]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-fonts-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[34]}.pkgset
	fi
	progress_info_end 34

	# pkg-games-devel
	progress_info_begin 35
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[35]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[35]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-games-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[35]}.pkgset
	fi
	progress_info_end 35

	# pkg-golang-maintainers
	progress_info_begin 36
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[36]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[36]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-golang-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -sPackage -n -FBuild-Depends golang-go $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		update_if_similar ${META_PKGSET[36]}.pkgset
	fi
	progress_info_end 36

	# pkg-haskell-maintainers
	progress_info_begin 37
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[37]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[37]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-haskell-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -sPackage -n -FBuild-Depends ghc $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		update_if_similar ${META_PKGSET[37]}.pkgset
	fi
	progress_info_end 37

	# pkg-java-maintainers
	progress_info_begin 38
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[38]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[38]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-java-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		grep-dctrl -sPackage -n -FMaintainer,Uploaders openjdk@lists.launchpad.net $SOURCES >> $TMPFILE
		grep-dctrl -sPackage -n -FBuild-Depends default-jdk -o -FBuild-Depends-Indep default-jdk $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
		update_if_similar ${META_PKGSET[38]}.pkgset
	fi
	progress_info_end 38

	# pkg-javascript-devel
	progress_info_begin 39
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[39]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[39]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-javascript-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[39]}.pkgset
	fi
	progress_info_end 39

	# pkg-multimedia-maintainers
	progress_info_begin 40
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[40]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[40]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-multimedia-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[40]}.pkgset
	fi
	progress_info_end 40

	# pkg-perl-maintainers
	progress_info_begin 41
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[41]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[41]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-perl-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[41]}.pkgset
	fi
	progress_info_end 41

	# pkg-php-pear
	progress_info_begin 42
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[42]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[42]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-php-pear@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[42]}.pkgset
	fi
	progress_info_end 42

	# pkg-ruby-extras-maintainers
	progress_info_begin 43
	if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[43]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[43]}.pkgset ] ; then
		grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-ruby-extras-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
		update_if_similar ${META_PKGSET[43]}.pkgset
	fi
	progress_info_end 43

}

TMPFILE=$(mktemp --tmpdir=$TEMPDIR pkg-sets-XXXXXXXXX)
TMPFILE2=$(mktemp --tmpdir=$TEMPDIR pkg-sets-XXXXXXXXX)
for SUITE in $SUITES ; do
	if [ "$SUITE" = "experimental" ] ; then
		# no pkg sets in experimental
		continue
	fi
	echo "============================================================================="
	echo "$(date -u) - Creating meta package sets for $SUITE now."
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
	echo "============================================================================="
	echo "$(date -u) - Creating meta package sets for $SUITE now."
	echo "============================================================================="
	# finally
	update_pkg_sets
	echo
	echo "============================================================================="
	echo "$(date -u) - Done updating all meta package sets for $SUITE."
done

rm -f $TMPFILE ${TMPFILE2}
echo

# abort the job if there are problems we cannot do anything about (except filing bugs! (but these are unrelated to reproducible builds...))
if "$ABORT" && ! "$WARNING" ; then
	exec /srv/jenkins/bin/abort.sh
fi
# (if there are warnings, we want to see them. aborting a job disables its notifications...)
