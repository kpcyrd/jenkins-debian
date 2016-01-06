#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set +e

# usually called by /srv/jenkins/bin/reproducible_cleanup_nodes.sh
# this script just kills everyone…
sudo killall timeout	# all builds are done using timeout
sudo slay 1111
sudo slay 2222
pgrep -u 1111,2222
# only slay jenkins on the build nodes…
if [ "$HOSTNAME" != "jenkins" ] ; then
	sudo slay jenkins
fi
