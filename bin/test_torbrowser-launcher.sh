#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set -e

cleanup_all() {
	cd
	# delete session if it still exists
	schroot --end-session -c tbb-launcher-$SUITE-$(basename $TMPDIR) > /dev/null 2>&1 || true
	# delete main work dir
	rm $TMPDIR -r
	echo "$(date -u) - $TMPDIR deleted. Cleanup done."
}

first_test() {
	set -x
	local SESSION="tbb-launcher-$SUITE-$(basename $TMPDIR)"
	schroot --begin-session --session-name=$SESSION -c jenkins-torbrowser-launcher-$SUITE
	schroot --run-session -c $SESSION --directory /tmp -u root -- mkdir $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- chown jenkins:jenkins $HOME
	xvfb-run schroot --run-session -c $SESSION -- torbrowser-launcher https://www.debian.org
	schroot --end-session -c $SESSION
	if ! "$DEBUG" ; then set +x ; fi
}

#
# main
#

TMPDIR=$(mktemp -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

SUITE=$1
echo "$(date -u) - testing torbrowser-launcher on $SUITE now."
#
# this is WIP in an early stage (and it won't work as X ain't configured yet)
# - test package build from git (todo)
# - test package from the archive (in progress)
# - test updates (todo)
#
first_test

cd
cleanup_all
trap - INT TERM EXIT
echo "$(date -u) - the end."

