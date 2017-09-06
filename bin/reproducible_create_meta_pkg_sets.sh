#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# we only generate the meta pkg sets on amd64
# (else this script would need a lot of changes for little gain)
# but these are source package sets so differences happen only very rarely anyway
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
try:
	with open(sys.argv[1]) as fd:
		manifest = yaml.load(fd)

	seen = set()
	for pkg in (manifest['packages']['binary'] + manifest['packages']['source']):
		pkgname = pkg['package']
		if pkgname not in seen:
			print(pkgname, end='|')
			seen.add(pkgname)
except Exception as exc:
	print("Warning: something went wrong while parsing the build manifest as YAML file: {}".format(exc))
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
	local MESSAGE="$1"
	mv $TMPFILE $TARGET
	echo "$(date -u) - $TARGET ($MESSAGE) updated."
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
				update_target "old: $LENGTH source packages, new: $NEWLEN"
			fi
		else
			# target does not exist, create it
			update_target "newly created"
		fi
	else
		echo "$(date -u) - $TARGET not updated, $TMPFILE is empty."
	fi
}

get_installable_set() {
	set +e
	echo "$(date -u) - Calculating the installable set for ${META_PKGSET[$index]}."
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
	echo "$(date -u) - Checking ${META_PKGSET[$table]}.pkgset for updates in $SUITE."
}

progress_info_end() {
	local table=$1
	echo "$(date -u) - work on ${META_PKGSET[$table]}.pkgset done."
	echo "============================================================================="
}

use_previous_sets_build_depends() {
	local src_set=$index
	let src_set-=1

	for PKG in $(cat $TPATH/${META_PKGSET[$src_set]}.pkgset) ; do
		grep-dctrl -sBuild-Depends -n -X -FPackage $PKG $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
	done
	packages_list_to_deb822
	convert_from_deb822_into_source_packages_only
}

update_pkg_set_specific() {
	#
	# bin/reproducible_pkgsets.csv defines the names of the packages set and their ordering
	#
	case ${META_PKGSET[$index]} in
		essential)
			# the essential package set
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X -FEssential yes > $TMPFILE
			convert_from_deb822_into_source_packages_only
			;;
		required)
			# the required package set
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X -FPriority required > $TMPFILE
			convert_from_deb822_into_source_packages_only
			;;
		build-essential)
			# build-essential
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FBuild-Essential yes --or -FPackage build-essential \) > ${TMPFILE2}
			# here we want the installable set:
			get_installable_set
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
			fi
			;;
		build-essential-depends)
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
			grep-dctrl --exact-match --field Package build-essential "$PACKAGES" \
				| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-latest-version - - \
				| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-bin2src --deb-native-arch="$ARCH" - "$SOURCES" \
				| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-create-graph --deb-drop-b-d-indep --quiet --deb-native-arch="$ARCH" --strongtype --bg "$SOURCES" "$PACKAGES" - \
				| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-buildgraph2packages - "$PACKAGES" \
				| schroot --directory /tmp -c source:jenkins-reproducible-unstable -- botch-bin2src --deb-native-arch="$ARCH" - "$SOURCES" \
				| grep-dctrl --no-field-names --show-field=Package '' > $TMPFILE
			;;
		popcon_top1337-installed-sources)
			# popcon top 1337 installed sources
			SQL_QUERY="SELECT popcon_src.source FROM popcon_src ORDER BY popcon_src.insts DESC LIMIT 1337;"
			PGPASSWORD=public-udd-mirror \
				psql -U public-udd-mirror \
				-h public-udd-mirror.xvm.mit.edu -p 5432 \
				-t \
				udd -c"${SQL_QUERY}" > $TMPFILE
			;;
		key_packages)
			# key packages (same for all suites)
			SQL_QUERY="SELECT source FROM key_packages;"
			PGPASSWORD=public-udd-mirror \
				psql -U public-udd-mirror \
				-h public-udd-mirror.xvm.mit.edu -p 5432 \
				-t \
				udd -c"${SQL_QUERY}" > $TMPFILE
			;;
		installed_on_debian.org)
			# installed on one or more .debian.org machines
			# one day we will get a proper data provider from DSA...
			# currently we get a manual "dpkg --get-selections" from all machines
			cat /srv/jenkins/bin/reproducible_installed_on_debian.org > $TMPFILE
			packages_list_to_deb822
			convert_from_deb822_into_source_packages_only
			;;
		had_a_DSA)
			# packages which had a DSA
			svn export svn://svn.debian.org/svn/secure-testing/data/DSA/list ${TMPFILE2}
			grep "^\[" ${TMPFILE2} | grep "DSA-" | cut -d " " -f5 > $TMPFILE
			;;
		cii-census)
			# packages from the cii-census
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
			rm $CII -r
			convert_from_deb822_into_source_packages_only
			;;
		gnome)	# gnome and everything it depends on
			#
			# The build-depends of X tasks can be solved once dose-ceve is able to read
			# Debian source packages (possible in dose3 git but needs a new dose3 release
			# and upload to unstable)
			#
			# Ignoring parsing issues, the current method is unable to resolve virtual
			# build dependencies
			#
			# The current method also ignores Build-Depends-Indep and Build-Depends-Arch
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage gnome \) > ${TMPFILE2}
			get_installable_set
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
			fi
			;;
		*_build-depends)
			# all build depends of the previous set (as defined in bin/reproducible_pkgsets.csv)
			use_previous_sets_build_depends
			;;
		kde)	# kde and everything it depends on
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage kde-full --or -FPackage kde-standard \) > ${TMPFILE2}
			get_installable_set
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
				# also add the packages maintained by those teams
				# (maybe add the depends of those packages too?)
				grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-qt-kde@lists.debian.org $SOURCES >> $TMPFILE
				grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-kde-extras@lists.alioth.debian.org $SOURCES >> $TMPFILE
			fi
			;;
		mate)	# mate and everything it depends on
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage mate-desktop-environment --or -FPackage mate-desktop-environment-extras \) > ${TMPFILE2}
			get_installable_set
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
				# also add the packages maintained by the team
				# (maybe add the depends of those packages too?)
				grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-mate-team@lists.alioth.debian.org $SOURCES >> $TMPFILE
			fi
			;;
		xfce)	# xfce and everything it depends on
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage xfce4 \) > ${TMPFILE2}
			get_installable_set
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
			fi
			;;
		debian-edu)
			# Debian Edu
			# all recommends of the education-* packages
			# (the Debian Edu metapackages don't use depends but recommends…)
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -n -sRecommends -r -FPackage education-*  |sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u > ${TMPFILE}
			packages_list_to_deb822
			mv $TMPFILE ${TMPFILE3}
			# required and maintained by Debian Edu
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME \( -FPriority required --or -FMaintainer debian-edu@lists.debian.org \) > ${TMPFILE2}
			get_installable_set
			mv $TMPFILE ${TMPFILE2}
			cat ${TMPFILE2} ${TMPFILE3} > $TMPFILE
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
			fi
			;;
		freedombox)
			# freedombox-setup and plinth and everything they depend on
			chdist --data-dir=$CHPATH grep-dctrl-packages $DISTNAME -X \( -FPriority required --or -FPackage freedombox-setup --or -FPackage plinth \) > ${TMPFILE2}
			get_installable_set
			if [ -f $TMPFILE ] ; then
				convert_from_deb822_into_source_packages_only
				# hardcoded list of source packages
				# derived from looking at "@package.required" in $src-plinth/plinth/modules/*py
				# see https://wiki.debian.org/FreedomBox/Manual/Developer#Specifying_module_dependencies
				for PKG in avahi deluge easy-rsa ejabberd ez-ipupdate firewalld ikiwiki jwchat monkeysphere mumble network-manager ntp obfs4proxy openvpn owncloud php-dropbox php5 postgresql-common privoxy python-letsencrypt quassel roundcube shaarli sqlite3 tor torsocks transmission unattended-upgrades ; do
					echo $PKG >> $TMPFILE
				done
			fi
			;;
		grml)	# grml
			URL="http://grml.org/files/grml64-full_latest/dpkg.selections"
			echo "Downloading $URL now."
			curl $URL | cut -f1 > $TMPFILE
			if ! grep '404 Not Found' $TMPFILE ; then
				echo "parsing $TMPFILE now..."
				packages_list_to_deb822
				convert_from_deb822_into_source_packages_only
			else
				rm $TMPFILE
				MESSAGE="Warning: could not download grml's latest dpkg.selections file, skipping pkg set..."
				irc_message debian-reproducible $MESSAGE
				ABORT=true
			fi
			;;
		tails)	# tails
			URL="https://nightly.tails.boum.org/build_Tails_ISO_devel/lastSuccessful/archive/latest.iso.build-manifest"
			echo "Downloading $URL now."
			curl $URL > $TMPFILE
			if ! grep '404 Not Found' $TMPFILE ; then
				echo "parsing $TMPFILE now..."
				tails_build_manifest_to_deb822 "$TMPFILE" "$PACKAGES"
				convert_from_deb822_into_source_packages_only
			else
				rm $TMPFILE
				MESSAGE="Warning: could not download tail's latest packages file(s), skipping tails pkg set..."
				irc_message debian-reproducible $MESSAGE
				ABORT=true
			fi
			;;
		subgraph_OS)
			# installed by Subgraph OS
			# one day we will get a proper data provider from Subgraph OS...
			# (so far it was a manual "dpkg -l")
			cat /srv/jenkins/bin/reproducible_installed_by_subgraphos > $TMPFILE
			packages_list_to_deb822
			convert_from_deb822_into_source_packages_only
			;;
		maint_debian-accessibility)
			# debian-accessibility@l.d.o maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-accessibility@lists.debian.org $SOURCES > $TMPFILE
			;;
		maint_debian-boot)
			# debian-boot@l.d.o maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-boot@lists.debian.org $SOURCES > $TMPFILE
			;;
		maint_debian-lua)
			# lua packages
			grep-dctrl -sPackage -n -FPackage -e ^lua.* $SOURCES > $TMPFILE
			grep-dctrl -sPackage -n -FBuild-Depends dh-lua $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
			;;
		maint_debian-med)
			# Debian Med Packaging Team <debian-med-packaging@lists.alioth.debian.org>
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-med-packaging@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_debian-ocaml)
			# debian-ocaml-maint@l.d.o maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-ocaml-maint@lists.debian.org $SOURCES > $TMPFILE
			;;
		maint_debian-python)
			# debian python maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders python-modules-team@lists.alioth.debian.org $SOURCES > $TMPFILE
			grep-dctrl -sPackage -n -FMaintainer,Uploaders python-apps-team@lists.alioth.debian.org $SOURCES >> $TMPFILE
			;;
		maint_debian-qa)
			# debian-qa maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders packages@qa.debian.org $SOURCES > $TMPFILE
			;;
		maint_debian-science)
			# Debian Science Team
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-science-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_debian-x)
			# debian-x@l.d.o maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders debian-x@lists.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-fonts-devel)
			# pkg-fonts-devel
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-fonts-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-games-devel)
			# pkg-games-devel
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-games-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-golang-maintainers)
			# pkg-golang-maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-golang-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
			grep-dctrl -sPackage -n -FBuild-Depends golang-go $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
			;;
		maint_pkg-grass-devel)
			# pkg-games-devel
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-grass-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-haskell-maintainers)
			# pkg-haskell-maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-haskell-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
			grep-dctrl -sPackage -n -FBuild-Depends ghc $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
			;;
		maint_pkg-java-maintainers)
			# pkg-java-maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-java-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
			grep-dctrl -sPackage -n -FMaintainer,Uploaders openjdk@lists.launchpad.net $SOURCES >> $TMPFILE
			grep-dctrl -sPackage -n -FBuild-Depends default-jdk -o -FBuild-Depends-Indep default-jdk $SOURCES | sed "s#([^()]*)##g ; s#\[[^][]*\]##g ; s#,##g" | sort -u >> $TMPFILE
			;;
		maint_pkg-javascript-devel)
			# pkg-javascript-devel
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-javascript-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-multimedia-maintainers)
			# pkg-multimedia-maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-multimedia-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-perl-maintainers)
			# pkg-perl-maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-perl-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-php-pear)
			# pkg-php-pear
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-php-pear@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-ruby-extras-maintainers)
			# pkg-ruby-extras-maintainers
			grep-dctrl -sPackage -n -FMaintainer,Uploaders pkg-ruby-extras-maintainers@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
		maint_pkg-openstack)
			# pkg-openstack
			grep-dctrl -sPackage -n -FMaintainer,Uploaders openstack-devel@lists.alioth.debian.org $SOURCES > $TMPFILE
			;;
	esac
}

update_pkg_sets() {
	# loop through all defined package sets…
	for index in $(seq 1 ${#META_PKGSET[@]}) ; do
		progress_info_begin $index
		if [ ! -z $(find $TPATH -maxdepth 1 -mtime +0 -name ${META_PKGSET[$index]}.pkgset) ] || [ ! -f $TPATH/${META_PKGSET[$index]}.pkgset ] ; then
			update_pkg_set_specific
			update_if_similar ${META_PKGSET[$index]}.pkgset
		fi
		progress_info_end index
		rm -f $TMPFILE ${TMPFILE2} ${TMPFILE3}
	done
}

# define some global variables…
TMPFILE=$(mktemp --tmpdir=$TEMPDIR pkg-sets-XXXXXXXXX)
TMPFILE2=$(mktemp --tmpdir=$TEMPDIR pkg-sets-XXXXXXXXX)
TMPFILE3=$(mktemp --tmpdir=$TEMPDIR pkg-sets-XXXXXXXXX)
index=0

# loop through all suites
for SUITE in $SUITES ; do
	if [ "$SUITE" = "experimental" ] ; then
		# no pkg sets in experimental
		continue
	elif [ "$SUITE" = "stretch" ] ; then
		# let's not update the stretch pkg sets anymore
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
	update_pkg_sets

	echo
	echo "============================================================================="
	echo "$(date -u) - Done updating all meta package sets for $SUITE."
done

echo

# abort the job if there are problems we cannot do anything about (except filing bugs! (but these are unrelated to reproducible builds...))
if "$ABORT" && ! "$WARNING" ; then
	exec /srv/jenkins/bin/abort.sh
fi
# (if there are warnings, we want to see them. aborting a job disables its notifications...)
