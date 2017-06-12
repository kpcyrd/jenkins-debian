#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
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
		VERSION=$(query_db "SELECT version FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		PKGID=$(query_db "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		cleanup_pkg_files
		RESULTID=$(query_db "SELECT id FROM results WHERE package_id=$PKGID")
		if [ ! -z "$RESULTID" ] ; then
			query_db "UPDATE results set package_id='$PKGID', version='$VERSION', status='blacklisted', build_date='$DATE', job='' WHERE id=$RESULTID;"
		else
			query_db "INSERT into results (package_id, version, status, build_date, job) VALUES ('$PKGID', '$VERSION', 'blacklisted', '$DATE', '');"
		fi
		query_db "DELETE FROM schedule WHERE package_id='$PKGID'"
	done
}

revert_blacklisted_packages() {
	DATE=$(date +'%Y-%m-%d %H:%M')
	for PKG in $PACKAGES ; do
		VERSION=$(query_db "SELECT version FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		PKGID=$(query_db "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
		query_db "DELETE FROM results WHERE package_id='$PKGID' AND status='blacklisted';"
	done
}

check_candidates() {
	PACKAGES=""
	TOTAL=0
	for PKG in $CANDIDATES ; do
		RESULT=$(query_db "SELECT name from sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
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
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "armhf" ] && [ "$ARCH" != "i386" ] && [ "$ARCH" != "arm64" ] ; then
	explain_syntax
	exit 1
fi
SUITE="$1"
shift
case $SUITE in
	sid) 	echo "WARNING: sid has been renamed to unstable."
		SUITE=unstable
		;;
	stretch|unstable|experimental) ;;
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
if ! $REVERT ; then
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
if $REVERT ; then
	/srv/jenkins/bin/reproducible_schedule_on_demand.sh -s $SUITE -a $ARCH $PACKAGES
fi
