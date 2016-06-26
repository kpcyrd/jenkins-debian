#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# main
echo "$(date -u) - Starting to rsync results."
rsync -r -v -e "ssh -o 'Batchmode = yes'" $TRIG_HOST:$TRIG_RESULTS/ $TRIG_RESULTS/
chmod 775 $RESULTS
echo "$(date -u) - the end."
