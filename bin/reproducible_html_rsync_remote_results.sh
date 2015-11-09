#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# that's all
for PROJECT in coreboot openwrt netbsd ; do
	rsync -r -v -e ssh profitbricks-build4.amd64:$BASE/$PROJECT/ $BASE/$PROJECT/
done
