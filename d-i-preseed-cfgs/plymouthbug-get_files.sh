#!/bin/sh

preseed_fetch plymouthbug-kludge.sh /tmp/plymouthbug-kludge.sh

# drop this in the background so that it can wait for files to edit
sh /tmp/plymouthbug-kludge.sh </dev/null >/dev/null 2>/dev/null &
