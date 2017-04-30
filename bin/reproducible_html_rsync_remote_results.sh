#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# that's all
rsync_remote_results() {
	for PROJECT in coreboot lede openwrt netbsd ; do
		echo "$(date -u) - Starting to rsync results for '$PROJECT'."
		local RESULTS=$(mktemp --tmpdir=$TEMPDIR -d reproducible-rsync-XXXXXXXXX)
		# copy the new results from build node to webserver node
		if rsync -r -v -e "ssh -o 'Batchmode = yes'" profitbricks-build3-amd64.debian.net:$BASE/$PROJECT/ $RESULTS 2>/dev/null ; then
			chmod 775 $RESULTS
			# move old results out of the way
			if [ -d $BASE/$PROJECT ] ; then
				mv $BASE/$PROJECT ${RESULTS}.tmp
				# preserve images and css
				for OBJECT in $(find ${RESULTS}.tmp -name "*css" -o -name "*png" -o -name "*jpg") ; do
					cp -v $OBJECT $RESULTS/
				done
				# delete the old results
				rm ${RESULTS}.tmp -r
			fi
			# make the new results visible
			mv $RESULTS $BASE/$PROJECT
			echo "$(date -u) - $REPRODUCIBLE_URL/$PROJECT has been updated."
		else
			echo "$(date -u) - no new results for '$PROJECT' found."
		fi
	done
}

# main
echo "$(date -u) - Starting to rsync results."
rsync_remote_results
echo "$(date -u) - the end."

