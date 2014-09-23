#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

TMPFILE=$(mktemp)
cat > $TMPFILE <<- EOF
echo 'deb http://reproducible.alioth.debian.org/debian/ ./' > /etc/apt/sources.list.d/reproducible.list
apt-get update
echo "Warning: Usage of --force-yes to override the apt authentication warning. Don't do this."
apt-get install --force-yes -y dpkg dpkg-dev debhelper dh-python discount
EOF

sudo pbuilder --create --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid
sudo pbuilder --execute --save-after-exec --basetgz /var/cache/pbuilder/base-reproducible.tgz --
rm $TMPFILE
