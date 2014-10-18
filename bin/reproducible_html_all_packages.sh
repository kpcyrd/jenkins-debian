#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set +x
init_html

#
# attempt to rebuild all package pages
# (will only happen if they don't exist or are older than build date.)
# (should never be needed)
#
PACKAGES=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status != \"\"")
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status != \"\"")
echo "$(date) - processing $COUNT_TOTAL packages... this will take a while."
process_packages ${PACKAGES}

