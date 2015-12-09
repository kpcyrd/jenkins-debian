#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set -e

# usually called by /srv/jenkins/bin/reproducible_cleanup_nodes.sh
# this script just kills everyone…
sudo slay -clean 1111
sudo slay -clean 2222
sleep 2
ps fax
# only slay jenkins on the build nodes…
if [ "$HOSTNAME" != "jenkins" ] ; then
	sudo slay -clean jenkins
fi

