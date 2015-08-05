#!/bin/bash

# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

. /srv/jenkins/bin/reproducible_common.sh

set -e

VERSION=$(git log -1 --pretty='%h')

make html

mkdir -pv "$BASE/howto/"

mv -v html/* "$BASE/howto"

irc_message "$REPRODUCIBLE_URL/howto updated to $VERSION"


