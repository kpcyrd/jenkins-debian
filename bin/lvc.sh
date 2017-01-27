#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# Copyright 2016 Philip Hands <phil@hands.com>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# $1 = wget url/jigdo url
URL=$1 ; shift

replace_origin_pu() {
    PREFIX=$1 ; shift
    BRANCH=$1 ; shift
    expr "$BRANCH" : 'origin/pu/' >/dev/null || return 1
    echo "${PREFIX}pu_${BRANCH#origin/pu/}"
}

# if $URL is set to "use_TRIGGERING_BRANCH" then use the contents of $TRIGGERING_BRANCH to work out the locally built ISO name
if [ "use_TRIGGERING_BRANCH" = "$URL" ] ; then
	if PU_ISO="$(replace_origin_pu "/srv/d-i/isos/mini-gtk-" $TRIGGERING_BRANCH).iso" ; then
		[ -f "$PU_ISO" ] || {
			echo "looks like we're meant to be testing '$PU_ISO', but it's missing"
			exit 1
			}
		URL=$PU_ISO
		echo "using locally built ISO image: URL='$URL'"
	else
		echo "URL='$URL' but TRIGGERING_BRANCH='$TRIGGERING_BRANCH' -- aborting"
		exit 1
	fi
fi

cleanup_all() {
        find . -name \*.vlog.png -print0 | xargs -0 -r rm
	#echo "Trying to preserve last screenshot…"
	#LAST_SCREENSHOT=$(ls -t1 $RESULTS/*.png | head -1)
	#if [ -e "$LAST_SCREENSHOT" ] ; then
	#        cp $LAST_SCREENSHOT $WORKSPACE/screenshot.png
	#	convert $WORKSPACE/screenshot.png -adaptive-resize 128x96 $WORKSPACE/screenshot-thumb.png
	#fi
}

fetch_if_newer() {
        url="$2"
        file="$1"
	if [ -f $url ] ; then
		echo "the URL turns out to be a local path ($url) -- linking"
		ln -sf $url $file
		return
        fi
        echo "Downloading $url"
        curlopts="-L -s -S"
        if [ -f "$file" ] ; then
                ls -l $file
                echo "File exists, will only re-download if a newer one is available..."
                curlopts="$curlopts -z $file"
        fi
        curl $curlopts -o $file.new $url
        if [ -e  $file.new ] ; then
          mv -f $file.new $file
        fi
}

discard_snapshots() {
    domain=$1 ; shift
    # if more parameters are provided, discard any snapshot younger than the files/dirs listed
    # otherwise, get rid of all of them (hence the [ -z "$1" ] below)

    sudo /usr/bin/virsh -q snapshot-list $domain | \
        while read snap date time tz state ; do
            if [ -z "$1" ] || [ "$(find "$@" -newermt "$date $time $tz" -print -quit)" ] ; then
                sudo /usr/bin/virsh snapshot-delete $domain $snap
            fi
        done
}

#
# define workspace + results
#
if [ -z "$WORKSPACE" ] ; then
    WORKSPACE=$PWD
fi
RESULTS=$WORKSPACE/results

IMAGE=$WORKSPACE/$(basename $URL)

LIBVIRT_DOMAIN_NAME="lvcVM-$JOB_NAME"

rm -rf $RESULTS $WORKSPACE/screenshot{,-thumb}.png

mkdir -p $RESULTS

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
        if [ $(file -L "$IMAGE" | grep -cE '(ISO 9660|DOS/MBR boot sector)') -eq 1 ] ; then
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

# discard any snapshots to ensure a clean run (we used to do this conditionally here, but that proved confusing)
discard_snapshots $LIBVIRT_DOMAIN_NAME

echo "Debug log available at runtime at https://jenkins.debian.net/view/lvc/job/$JOB_NAME/ws/results/debug.log"

/srv/jenkins/cucumber/bin/run_test_suite --capture-all --keep-snapshots --vnc-server-only --iso $IMAGE --tmpdir $WORKSPACE --old-iso $IMAGE -- --format pretty --format pretty_debug --out $RESULTS/debug.log /srv/jenkins/cucumber/features/step_definitions /srv/jenkins/cucumber/features/support "${@}" || {
  RETVAL=$?
  # it may make sense to keep snapshots on failure, so subsequent tests are quicker -- only if we stop discarding them above though
  discard_snapshots $LIBVIRT_DOMAIN_NAME
  exit $RETVAL
}

# FIXME -- decide here if we need to keep any snapshots, and put them somewhere safe for other jobs to find
discard_snapshots $LIBVIRT_DOMAIN_NAME
cleanup_all

# don't cleanup twice
trap - INT TERM EXIT
