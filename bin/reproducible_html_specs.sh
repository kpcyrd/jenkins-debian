#!/bin/bash

# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015 Holger Levsen <holger@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"
. /srv/jenkins/bin/reproducible_common.sh

# build and publish the html version
VERSION=$(git log -1 --pretty='%h')
SPEC=$1
make $SPEC.html
mkdir -pv "$BASE/specs/$SPEC"
mv -v $SPEC.html "$BASE/specs/$SPEC/index.html"
irc_message "$REPRODUCIBLE_URL/specs/$SPEC/ updated to $VERSION"
