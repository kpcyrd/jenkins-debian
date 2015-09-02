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
TARGET="specs/$(basename $SPEC -spec)"
make $SPEC.html
mkdir -pv "$BASE/$TARGET"
mv -v $SPEC.html "$BASE/$TARGET/index.html"
irc_message "$REPRODUCIBLE_DOT_ORG_URL/$TARGET/ updated to $VERSION"
