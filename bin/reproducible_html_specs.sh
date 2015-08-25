#!/bin/bash

# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015 Holger Levsen <holger@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

. /srv/jenkins/bin/reproducible_common.sh


VERSION=$(git log -1 --pretty='%h')
SPEC=$1

make html

mkdir -pv "$BASE/specs/$1"

mv -v html/* "$BASE/specs/$1"

irc_message "$REPRODUCIBLE_URL/specs/$1 updated to $VERSION"


