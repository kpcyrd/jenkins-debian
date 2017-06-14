#!/bin/bash

# Copyright 2012-2016 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# Copyright      2014 Joachim Breitner <nomeata@debian.org>
# Copyright      2015 MAttia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# bootstraps a new chroot for schroot, and then moves it into the right location

# $1 = schroot name
# $2 = base distro/suite
# $3 $4 ... = extra packages to install

if [ $# -lt 2 ]; then
	echo "usage: $0 TARGET SUITE [backports] [reproducible] [ARG1 ARG2 ...]"
	exit 1
fi

# initialize vars
declare -a EXTRA_SOURCES
for i in $(seq 0 7) ; do
	EXTRA_SOURCES[$i]=""
done
CONTRIB=""

if [ "$1" = "torbrowser-launcher" ] ; then
	CONTRIB="contrib"
	shift
fi

if [ "$1" = "backports" ] ; then
	EXTRA_SOURCES[2]="deb $MIRROR ${SUITE}-backports main $CONTRIB"
	EXTRA_SOURCES[3]="deb-src $MIRROR ${SUITE}-backports main $CONTRIB"
	shift
fi

if [ "$1" = "reproducible" ] ; then
	EXTRA_SOURCES[4]="deb http://reproducible.alioth.debian.org/debian/ ./"
	EXTRA_SOURCES[5]="deb-src http://reproducible.alioth.debian.org/debian/ ./"
	REPRODUCIBLE=true
	shift
fi


TARGET="$1"
shift
SUITE="$1"
shift

TMPLOG=$(mktemp --tmpdir=$TMPDIR schroot-create-XXXXXXXX)

if [ "$SUITE" = "experimental" ] ; then
	# experimental cannot be bootstrapped
	SUITE=sid
	EXTRA_SOURCES[0]="deb $MIRROR experimental main $CONTRIB"
	EXTRA_SOURCES[1]="deb-src $MIRROR experimental main $CONTRIB"
elif [ "$SUITE" != "unstable" ] && [ "$SUITE" != "sid" ] ; then
	EXTRA_SOURCES[6]="deb http://security.debian.org $SUITE/updates main $CONTRIB"
	EXTRA_SOURCES[7]="deb-src http://security.debian.org $SUITE/updates main $CONTRIB"
fi

export SCHROOT_TARGET=$(mktemp -d -p $SCHROOT_BASE/ schroot-install-$TARGET-XXXX)
if [ -z "$SCHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi

#
# create script to add key for reproducible repo
# and configuring APT to ignore Release file expiration (since the host may
# have the date set far in the future)
#
reproducible_setup() {
	cat > $1 <<- EOF
echo "-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.12 (GNU/Linux)

mQINBFQsy/gBEADKGF55qQpXxpTn7E0Vvqho82/HFB/yT9N2wD8TkrejhJ1I6hfJ
zFXD9fSi8WnNpLc6IjcaepuvvO4cpIQ8620lIuONQZU84sof8nAO0LDoMp/QdN3j
VViXRXQtoUmTAzlOBNpyb8UctAoSzPVgO3jU1Ngr1LWi36hQPvQWSYPNmbsDkGVE
unB0p8DCN88Yq4z2lDdlHgFIy0IDNixuRp/vBouuvKnpe9zyOkijV83Een0XSUsZ
jmoksFzLzjChlS5fAL3FjtLO5XJGng46dibySWwYx2ragsrNUUSkqTTmU7bOVu9a
zlnQNGR09kJRM77UoET5iSXXroK7xQ26UJkhorW2lXE5nQ97QqX7igWp2u0G74RB
e6y3JqH9W8nV+BHuaCVmW0/j+V/l7T3XGAcbjZw1A4w5kj8YGzv3BpztXxqyHQsy
piewXLTBn8dvgDqd1DLXI5gGxC3KGGZbC7v0rQlu2N6OWg2QRbcVKqlE5HeZxmGV
vwGQs/vcChc3BuxJegw/bnP+y0Ys5tsVLw+kkxM5wbpqhWw+hgOlGHKpJLNpmBxn
T+o84iUWTzpvHgHiw6ShJK50AxSbNzDWdbo7p6e0EPHG4Gj41bwO4zVzmQrFz//D
txVBvoATTZYMLF5owdCO+rO6s/xuC3s04pk7GpmDmi/G51oiz7hIhxJyhQARAQAB
tC5EZWJpYW4gUmVwcm9kdWNpYmxlIEJ1aWxkcyBBcmNoaXZlIFNpZ25pbmcgS2V5
iQI9BBMBCAAnAhsDBQsJCAcDBRUKCQgLBRYDAgEAAh4BAheABQJW+pswBQkIcWme
AAoJEF23ymfqWaMfuzcP+QG3oG4gmwvEmiNYSQZZouRCkPyi7VUjZPdY88ZI4l9e
KECfjE/VXMr9W5B4QQXqbWAqXkZGNTRB+OWcwcpwcwdRnCX1PfchC6Rm5hc+OOg1
Wl3pHhsZ+JaztQ9poAy8IRSYdGIH6qsTOWglAR1iPeklimFIzrrfpoUe+pT3fidQ
UoCtq6Y2wrevi9l+6ZCCO2fZGJ+8jQGSWF2XNUGgv43vyS+O/YKYeq7u87hEqxwI
k3gfcvD0AKIqX3ST0f6ABsF9YXy4pfnfJeH7xVDOyMH4A8YemNniKE40LSrZVUbW
QMkJC3VjUF+nSOM+nQSgdSQ2XKfygagv1rWcVqj0etVbcjIMgF+YtQtX5WhXo1de
XTUO1y0rsCyX7mbfEqBDVCGMOvQmwrwk0uLGzzdgzam3/ZTgPoy+n5Adg4x1gU30
nh5rjOKWAyzbLNCt9KXmps+PwuwPSR643q/zr/r4WJTruSyVJAMjwXf8tbYYg8X3
unSrmrxS5T0YA3TfY34ThtHtmjA9d2lzv270ALc3ELv83fTnQ/3Sxkwu+KKIagXQ
KzXCKzHjI89kJT5+7GBHd/nLG1z/3yw/TBzH5zSTgwC+3/EHNMH7WrY2DOzdEZTF
peNsYNcna2Ca8Imozzc5L424lXN3MaiTql7Y1lZJFF5Y/wznbjUQj/5YXj3LVB3W
=5CAZ
-----END PGP PUBLIC KEY BLOCK-----" | apt-key add -
apt-key list
echo
echo "Configuring APT to ignore the Release file expiration"
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/398future
echo "Configuring APT to not download package descriptions"
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/10no-package-descriptions
echo
EOF
}

robust_chroot_apt() {
	set +e
	sudo chroot $SCHROOT_TARGET apt-get $@ | tee $TMPLOG
	local RESULT=$(egrep 'Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable)' $TMPLOG || true)
	set -e
	if [ ! -z "$RESULT" ] ; then
		echo "$(date -u) - 'apt-get $@' failed, sleeping 5min before retrying..."
		sleep 5m
		sudo chroot $SCHROOT_TARGET apt-get $@ || ( echo "$(date -u ) - 2nd 'apt-get $@' failed, giving up..." ; exit 1 )
	fi
	rm -f $TMPLOG
}

bootstrap() {
	mkdir -p "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstraping $SUITE into $SCHROOT_TARGET now."
	set +e
	sudo debootstrap $SUITE $SCHROOT_TARGET $MIRROR | tee $TMPLOG
	local RESULT=$(egrep "E: (Couldn't download packages|Invalid Release signature)" $TMPLOG || true)
	set -e
	if [ ! -z "$RESULT" ] ; then
		echo "$(date -u) - initial debootstrap failed, sleeping 5min before retrying..."
		sudo rm -rf --one-file-system $SCHROOT_TARGET
		sleep 5m
		sudo debootstrap $SUITE $SCHROOT_TARGET $MIRROR || ( echo "$(date -u ) - 2nd debootstrap failed, giving up..." ; exit 1 )
	fi
	rm -f $TMPLOG

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $SCHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $SCHROOT_TARGET/usr/sbin/policy-rc.d
	if [ ! -z "$http_proxy" ] ; then
		echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee    $SCHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	fi
	echo "# generated by $BUILD_URL"              | sudo tee    $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
	echo "deb $MIRROR $SUITE main $CONTRIB"       | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
	echo "deb-src $MIRROR $SUITE main $CONTRIB"   | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
	for i in $(seq 0 7) ; do
		[ -z "${EXTRA_SOURCES[$i]}" ] || echo "${EXTRA_SOURCES[$i]}"                     | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list >/dev/null
	done

	if $REPRODUCIBLE ; then
		TMPFILE=$(mktemp -u)
		reproducible_setup $SCHROOT_TARGET/$TMPFILE
		sudo chroot $SCHROOT_TARGET bash $TMPFILE
		rm $SCHROOT_TARGET/$TMPFILE
	fi


	robust_chroot_apt update
	if [ -n "$1" ] ; then
		for d in proc dev dev/pts ; do
			sudo mount --bind /$d $SCHROOT_TARGET/$d
		done
		set -x
		robust_chroot_apt update
		# first, (if), install diffoscope with all recommends...
		if [ "$1" = "diffoscope" ] ; then
			# we could also use $SCRIPT_HEADER (set in bin/common-functions.sh) in our generated scripts
			# instead of using the next line, maybe we should…
			echo 'debconf debconf/frontend select noninteractive' | sudo chroot $SCHROOT_TARGET debconf-set-selections
			robust_chroot_apt install -y --install-recommends diffoscope
		fi
		robust_chroot_apt install -y --no-install-recommends sudo
		robust_chroot_apt install -y --no-install-recommends $@
		# try to use diffoscope from experimental
		if ([ "$SUITE" = "unstable" ] || [ "$SUITE" = "testing" ] ) && [ "$1" = "diffoscope" ] ; then
			echo "deb $MIRROR experimental main"        | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
			robust_chroot_apt update
			# install diffoscope from experimental without re-adding all recommends...
			sudo chroot $SCHROOT_TARGET apt-get install -y -t experimental --no-install-recommends diffoscope || echo "Warning: diffoscope from experimental is uninstallable at the moment."
		elif [ "$SUITE" = "testing" ] && [ "$1" = "diffoscope" ] ; then
			# always try to use diffoscope from unstable on testing
			echo "deb $MIRROR unstable main"        | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
			robust_chroot_apt update
			# install diffoscope from unstable without re-adding all recommends...
			sudo chroot $SCHROOT_TARGET apt-get install -y -t unstable --no-install-recommends diffoscope || echo "Warning: diffoscope from unstable is uninstallable at the moment."
		fi
		if ! $DEBUG ; then set +x ; fi
		if [ "$1" = "diffoscope" ] ; then
			echo
			sudo chroot $SCHROOT_TARGET dpkg -l diffoscope
			echo
		fi
		# umount in reverse order
		for d in dev/pts dev proc ; do
			sudo umount -l $SCHROOT_TARGET/$d
		done
		# configure sudo inside just like outside
		echo "jenkins    ALL=NOPASSWD: ALL" | sudo tee -a $SCHROOT_TARGET/etc/sudoers.d/jenkins >/dev/null
		sudo chroot $SCHROOT_TARGET chown root.root /etc/sudoers.d/jenkins
		sudo chroot $SCHROOT_TARGET chmod 700 /etc/sudoers.d/jenkins
	fi
}

cleanup() {
	if [ -d $SCHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $SCHROOT_TARGET || ( echo "Warning: $SCHROOT_TARGET could not be fully removed on forced cleanup." ; ls $SCHROOT_TARGET -la )
	fi
	rm -f $TMPLOG
}
trap cleanup INT TERM EXIT
bootstrap $@

trap - INT TERM EXIT

# pivot the new schroot in place
rand=$RANDOM
if [ -d $SCHROOT_BASE/"$TARGET" ]
then
	# no needed for torbrowser-launcher as race conditions are mostly avoided by timings
	if [ "${TARGET:0:19}" != "torbrowser-launcher" ] ; then
		cleanup_schroot_sessions
	fi
	echo "$(date -u ) - $SCHROOT_BASE/$TARGET exists, moving it away to $SCHROOT_BASE/$TARGET-$rand"
	set +e
	sudo mv $SCHROOT_BASE/"$TARGET" $SCHROOT_BASE/"$TARGET"-"$rand"
	RESULT=$?
	set -e
	if [ $RESULT -ne 0 ] ; then
		echo
		ls -R $SCHROOT_BASE/"$TARGET"
		echo
		exit 1
	fi
fi

# no needed for torbrowser-launcher as race conditions are mostly avoided by timings
if [ "${TARGET:0:19}" != "torbrowser-launcher" ] ; then
	cleanup_schroot_sessions
fi
echo "$(date -u ) - renaming $SCHROOT_TARGET to $SCHROOT_BASE/$TARGET"
set +e
sudo mv $SCHROOT_TARGET $SCHROOT_BASE/"$TARGET"
RESULT=$?
set -e
if [ $RESULT -ne 0 ] ; then
	echo
	ls -R $SCHROOT_TARGET
	echo
	exit 1
fi

if [ -d $SCHROOT_BASE/"$TARGET"-"$rand" ] ; then
	sudo rm -rf --one-file-system $SCHROOT_BASE/"$TARGET"-"$rand" || ( echo "Warning: $SCHROOT_BASE/${TARGET}-$rand could not be fully removed." ; ls $SCHROOT_BASE/${TARGET}-$rand -la )
fi

# write the schroot config
echo "Writing configuration"
sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
	[jenkins-$TARGET]
	description=Jenkins schroot $TARGET
	directory=$SCHROOT_BASE/$TARGET
	type=directory
	root-users=jenkins
	source-root-users=jenkins
	union-type=aufs
	__END__

echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
