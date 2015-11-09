#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# that's all
rsync_remote_results() {
	for PROJECT in coreboot openwrt netbsd ; do
		echo "$(date -u) - Starting to rsync results for '$PROJECT'."
		local RESULTS=$(mktemp --tmpdir=$TEMPDIR -d reproducible-rsync-XXXXXXXXX)
		rsync -r -v -e ssh profitbricks-build3-amd64.debian.net:$BASE/$PROJECT/ $RESULTS
		mv $BASE/$PROJECT ${RESULTS}.tmp
		mv $RESULTS $BASE/$PROJECT
		rm ${RESULTS}.tmp -r
		echo "$(date -u) - $REPRODUCIBLE_URL/$PROJECT has been updated."
	done
}

# main
echo "$(date -u) - Starting to rsync results."
rsync_remote_results
echo "$(date -u) - the end."

