#!/bin/bash

# Copyright 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

# this script is maintained upstream and is also run on Guardian
# Project's jenkins box
./jenkins-build-makebuildserver
