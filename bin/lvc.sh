#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# Copyright 2016 Philip Hands <phil@hands.com>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# $1 = wget url/jigdo url
URL=$1 ; shift

IMAGE=$PWD/$(basename $URL)

cleanup_all() {
    find . -name \*.vlog.png -print0 | xargs -0 -r rm
}

fetch_if_newer() {
        url="$2"
        file="$1"
        echo "Downloading $url"
        curlopts="-L -s -S"
        if [ -f "$file" ] ; then
                ls -l $file
                echo "File exists, will only re-download if a newer one is available..."
                curlopts="$curlopts -z $file"
        fi
        curl $curlopts -o $file $url
}

discard_snapshots() {
        domain=$1
        for snap in $(sudo /usr/bin/virsh snapshot-list $domain --name) ; do
                sudo /usr/bin/virsh snapshot-delete $domain $snap
        done
}

#
# define workspace + results
#
rm -rf results screenshot.png screenshot-thumb.png

if [ -z "$WORKSPACE" ] ; then
    WORKSPACE=$PWD
fi
RESULTS=$WORKSPACE/results
mkdir -p $RESULTS

mkdir -p $WORKSPACE/DebianToasterStorage

# FIXME this should discover the 'target' bit of the path, probably via: virsh vol-list
if [ ! -e "$WORKSPACE/DebianToasterStorage/target" ] ; then
        discard_snapshots DebianToaster
fi

trap cleanup_all INT TERM EXIT

#
# install image preparation
#
if [ ! -z "$NETBOOT" ] ; then
        #
        # if there is a netboot installer tarball...
        #
        fetch_if_newer "$NETBOOT" "$URL"
        sha256sum "$NETBOOT"
        # try to extract, otherwise clean up and abort
        if ! tar -zxvf "$NETBOOT" ; then
                echo "tarball seems corrupt;  deleting it"
                rm -f "$NETBOOT"
                exit 1
        fi
elif [ ! -z "$IMAGE" ] ; then
        #
        # if there is a CD image...
        #
        fetch_if_newer "$IMAGE" "$URL"
        # is this really an .iso?
        if [ $(file "$IMAGE" | grep -cE '(ISO 9660|DOS/MBR boot sector)') -eq 1 ] ; then
                # yes, so let's md5sum and mount it
                md5sum $IMAGE
#                sudo mkdir -p $IMAGE_MNT
#                grep -q $IMAGE_MNT /proc/mounts && sudo umount -l $IMAGE_MNT
#                sleep 1
#                sudo mount -o loop,ro $IMAGE $IMAGE_MNT
        else
                # something went wrong
                figlet "no .iso"
                echo "ERROR: no valid .iso found"
                if [ $(file "$IMAGE" | grep -c "HTML document") -eq 1 ] ; then
                        mv "$IMAGE" "$IMAGE.html"
                        lynx --dump "$IMAGE.html"
                        rm "$IMAGE.html"
                fi
                exit 1
        fi
else
        #
        # else netboot gtk
        #
        fetch_if_newer "$KERNEL" "$URL/$KERNEL"
        fetch_if_newer "$INITRD" "$URL/$INITRD"
fi

#  --keep-snapshots -- keeps the VM snapshots -- let's make life simple and not do that until we're using them to pass on state to the next jenkins job

/srv/jenkins/cucumber/bin/run_test_suite --vnc-server-only --capture-all --iso $IMAGE --tmpdir $PWD --old-iso $IMAGE -- --format pretty --format pretty_debug --out $PWD/results/debug.log /srv/jenkins/cucumber/features/step_definitions /srv/jenkins/cucumber/features/support "${@}"

LAST_SCREENSHOT=$(ls -t1 results/*.png | head -1)
if [ -e "$LAST_SCREENSHOT" ] ; then
        cp $LAST_SCREENSHOT $WORKSPACE/screenshot.png
fi

cleanup_all

# don't cleanup twice
trap - INT TERM EXIT
