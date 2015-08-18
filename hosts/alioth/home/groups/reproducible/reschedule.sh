#!/bin/bash

SSH_KEY="/home/groups/reproducible/private/jenkins-key"
SSH_KNOWN_HOSTS="/home/groups/reproducible/private/ssh_known_hosts"

# "dummy" is discarded by the server ssh (jenkins.debian.net in this case) and
# it's there because otherwise the client ssh (this) tries to parse the options
# for the remote command

# separate args with NULL and pass them through stdin to avoid ssh screw up
for arg in "$@" ; do
    printf "%s\0" "$arg"
done | LC_USER="$USER" ssh -i "$SSH_KEY" -o GlobalKnownHostsFile="$SSH_KNOWN_HOSTS" jenkins@jenkins.debian.net -- dummy --null
