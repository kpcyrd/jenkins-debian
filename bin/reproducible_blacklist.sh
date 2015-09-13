#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

blacklist_packages() {
	DATE=$(date +'%Y-%m-%d %H:%M')
	for PKG in $PACKAGES ; do
		VERSION=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT version FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		PKGID=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		cleanup_pkg_files
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('$PKGID', '$VERSION', 'blacklisted', '$DATE');"
	done
}

revert_blacklisted_packages() {
	DATE=$(date +'%Y-%m-%d %H:%M')
	for PKG in $PACKAGES ; do
		VERSION=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT version FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		PKGID=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM results WHERE package_id='$PKGID' AND status='blacklisted';"
	done
}

check_candidates() {
	PACKAGES=""
	TOTAL=0
	for PKG in $CANDIDATES ; do
		RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT name from sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		if [ ! -z "$RESULT" ] ; then
			PACKAGES="$PACKAGES $RESULT"
			let "TOTAL+=1"
		fi
	done
}

explain_syntax() {
	echo "$0 has to be called with three or more params:"
	echo "     $0 \$arch \$suite pkg1 pkg2..."
	echo "optionally it's possible to revert like this:"
	echo "     $0 \$arch \$suite --revert pkg1 pkg2..."
	echo
	echo "Changing order of options is not possible and this should be improved."
	echo
}

#
# main
#
set +x
ARCH="$1"
shift
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "armhf" ] ; then
	explain_syntax
	exit 1
fi
SUITE="$1"
shift
case $SUITE in
	sid) 	echo "WARNING: sid has been renamed to unstable."
		SUITE=unstable
		;;
	unstable) ;;
	testing|experimental)	if [ "$ARCH" = "armhf" ] ; then echo "Only unstable is tested for $ARCH, exiting." ; exit 0 ; fi
				;;
	*)	echo "$SUITE is not a valid suite".
		explain_syntax
		exit 1
		;;
esac

if [ "$1" != "--revert" ] ; then
	REVERT=false
	ACTION="blacklisted"
else
	shift
	REVERT=true
	ACTION="removed from blacklist"
fi

CANDIDATES="$@"
check_candidates
PACKAGES=$(echo $PACKAGES)
MESSAGE="$TOTAL package(s) $ACTION in $SUITE/$ARCH: ${PACKAGES}"
if [ $TOTAL -lt 1 ] ; then
	exit 1
fi

# main
if [ "$1" != "--revert" ] ; then
	blacklist_packages
else
	revert_blacklisted_packages
fi

for PACKAGE in "$PACKAGES" ; do
    gen_package_html $PACKAGE
done
echo
# notify
echo "$MESSAGE"
kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
echo
echo "============================================================================="
echo "The following $TOTAL source packages from $SUITE/$ARCH have been $ACTION: $PACKAGES"
echo "============================================================================="
echo
echo "Probably edit notes.git/packages.yml now and enter/remove reasons for blacklisting there."

# finally, let's re-schedule them if the blacklisted was reverted
if [ "$1" = "--revert" ] ; then
	/srv/jenkins/bin/reproducible_schedule_on_demand.sh -s $SUITE -a $ARCH $PACKAGES
fi
