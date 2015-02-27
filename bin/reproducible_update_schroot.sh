#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# do the upgrade
schroot --directory /root -u root -c source:jenkins-$1 -- apt-get update
schroot --directory /root -u root -c source:jenkins-$1 -- apt-get -y -u dist-upgrade
schroot --directory /root -u root -c source:jenkins-$1 -- apt-get --purge autoremove
