#!/bin/bash

# Copyright © 2015-2017 Holger Levsen (holger@layer-acht.org)
# Copyright © 2017 Hans-Christoph Steiner (hans@guardianproject.info)
# released under the GPLv=2

#
#

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

# define and clean work space (differently than jenkins would normally do as we run via ssh on a different node…)
WORKSPACE=$BASE/fdroid-build
rm $WORKSPACE -rf
mkdir -p $WORKSPACE

cleanup_all() {
	echo "$(date -u) - cleanup in progress..."
	killall VBoxHeadless || true
	sleep 10
	echo "$(date -u) - cleanup done."
}
trap cleanup_all INT TERM EXIT

./jenkins-build

# remove trap
trap - INT TERM EXIT
echo "$(date -u) - the end."
