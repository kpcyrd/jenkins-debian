#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# Copyright      2014 Joachim Breitner <nomeata@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# bootstraps a new chroot for schroot, and then moves it into the right location

# $1 = schroot name
# $2 = base distro/suite
# $3 $4 ... = extra packages to install

if [ $# -lt 2 ]; then
	echo "usage: $0 TARGET SUITE [backports] CMD [ARG1 ARG2 ...]"
	exit 1
fi
TARGET="$1"
shift
SUITE="$1"
shift

if [ ! -d "$CHROOT_BASE" ]; then
	echo "Directory $CHROOT_BASE does not exist, aborting."
	exit 1
fi

export CHROOT_TARGET=$(mktemp -d -p $CHROOT_BASE/ schroot-install-$TARGET-XXXX)
if [ -z "$CHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi

bootstrap() {
	mkdir -p "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstraping $SUITE into $CHROOT_TARGET now."
	sudo debootstrap $SUITE $CHROOT_TARGET $MIRROR

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $CHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $CHROOT_TARGET/usr/sbin/policy-rc.d
	echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee    $CHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	echo "deb-src $MIRROR $SUITE main"        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list > /dev/null

	sudo chroot $CHROOT_TARGET apt-get update
	if [ -n "$1" ] ; then
		sudo chroot $CHROOT_TARGET apt-get update
		# install debbindiff with all recommends...
		#sudo chroot $CHROOT_TARGET apt-get install -y --no-install-recommends "$@"
		sudo chroot $CHROOT_TARGET apt-get install -y "$@"
	else
		# schroot is used to download sources, so add our repo too
		echo 'deb-src http://reproducible.alioth.debian.org/debian/ ./' > /etc/apt/sources.list.d/reproducible.list
		TMPFILE=$(mktemp)
		cat >> $TMPFILE <<- EOF
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
iQI9BBMBCAAnBQJULMv4AhsDBQkFo5qABQsJCAcDBRUKCQgLBRYDAgEAAh4BAheA
AAoJEF23ymfqWaMfFsMP/3jthq65H9avuM469jHcugcd0C5b7/DS+cGQ5E4NQIGL
6tGsqv5k6Nb0MoMMEAQSmWeXRkbYYxmEkrREMNg8tPlh4NiJimH3neNfI+8fGiHY
89FH7QDrrzGfMF9oJQ9zjWZTOs3bjJ4AfS4fkQiQ6UfO7TeMyz5Cw7kz+rS1m1tu
+RgHxD+6A+XxkIZnw5we1MH0SAFoq4j3boR8QkFUNMZsy97xWYON4QLpYwKCbiwL
Q4y06YTw4A7lp+B2JKLc70yRcjbixeAFlZfbhmGITTNAl3j8+48hRLLkJ+s8eT1r
DS1UkYi2xBSNa6TVtNxbDUwVTzzxDe+b8tW2BfC7TBOX2oq6e6ebRa+ghZFVLNY1
3y+FilXGNMB7IvZ378idHYTNaiJuYXNkrd8UGunwK4NCWdZk05L9GdKeQ6DN380Y
L4QkKpINXSKjneWV7IITMFhvRZCgOVAmoHaq6kaGsl/FwHBA9I8hHXuSyvke8UMP
dmvR8ggv5wiY9NDjW55h7M+UIqEaoXws1algIKB/TWm4/RnQcrxoXBX16wyidzcv
Mb0BawlXZui0MNUSnZtxHMxrjejdvZdqtskHl9srB1QThH0jasmUqbQPxCnxMbf1
4LhIp6XlXJFF1btgfCexNmcPuqeOMMDQ+du6Hqj2Yl5GYo2McWvjpSgkt5VmQfIz
=X8YA
-----END PGP PUBLIC KEY BLOCK-----"
EOF
		cat $TMPFILE | sudo chroot $CHROOT_TARGET apt-key add -
		rm $TMPFILE
		sudo chroot $CHROOT_TARGET apt-get update
	fi
}

cleanup() {
	if [ -d $CHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
	fi
}
trap cleanup INT TERM EXIT
bootstrap $@

trap - INT TERM EXIT

remove_writelock() {
	# remove the lock
	rm $DBDCHROOT_WRITELOCK
}

trap remove_writelock INT TERM EXIT
# aquire a write lock in any case
touch $DBDCHROOT_WRITELOCK
if [ -f $DBDCHROOT_READLOCK ] ; then
	# patiently wait for our users to using the schroot
	for i in $(seq 0 100) ; do
		sleep 15
		echo "sleeping 15s, debbindiff schroot is locked and used."
		if [ ! -f $DBDCHROOT_READLOCK ] ; then
			break
		fi
	done
	if [ -f $DBDCHROOT_READLOCK ] ; then
		echo "Warning: lock $DBDCHROOT_READLOCK still exists, exiting."
		exit 1
	fi
fi

# pivot the new schroot in place
rand=$RANDOM
if [ -d $SCHROOT_BASE/"$TARGET" ]
then
	sudo mv $SCHROOT_BASE/"$TARGET" $SCHROOT_BASE/"$TARGET"-"$rand"
fi

sudo mv $CHROOT_TARGET $SCHROOT_BASE/"$TARGET"

if [ -d $SCHROOT_BASE/"$TARGET"-"$rand" ]
then
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

trap - INT TERM EXIT
remove_writelock
