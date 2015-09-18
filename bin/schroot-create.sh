#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
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

if [ "$1" = "backports" ] ; then
	EXTRA_SOURCES[2]="deb $MIRROR ${SUITE}-backports main"
	EXTRA_SOURCES[3]="deb-src $MIRROR ${SUITE}-backports main"
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

TMPLOG=$(mktemp)

declare -a EXTRA_SOURCES
if [ "$SUITE" = "experimental" ] ; then
	# experimental cannot be bootstrapped
	SUITE=sid
	EXTRA_SOURCES[0]="deb $MIRROR experimental main"
	EXTRA_SOURCES[1]="deb-src $MIRROR experimental main"
fi

if [ ! -d "$CHROOT_BASE" ]; then
	echo "Directory $CHROOT_BASE does not exist, aborting."
	exit 1
fi

export CHROOT_TARGET=$(mktemp -d -p $CHROOT_BASE/ schroot-install-$TARGET-XXXX)
if [ -z "$CHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi

#
# create script to add key for reproducible repo
#
add_repokey() {
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
-----END PGP PUBLIC KEY BLOCK-----" | apt-key add -
EOF
}

robust_chroot_apt() {
	set +e
	sudo chroot $CHROOT_TARGET apt-get $@ | tee $TMPLOG
	local RESULT=$(egrep 'Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway)' $TMPLOG)
	set -e
	if [ ! -z "$RESULT" ] ; then
		echo "$(date -u) - 'apt-get $@' failed, sleeping 5min before retrying..."
		sleep 5m
		sudo chroot $CHROOT_TARGET apt-get $@
	fi
	rm -f $TMPLOG
}

bootstrap() {
	mkdir -p "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstraping $SUITE into $CHROOT_TARGET now."
	set +e
	sudo debootstrap $SUITE $CHROOT_TARGET $MIRROR | tee $TMPLOG
	local RESULT=$(egrep "E: (Couldn't download packages|Invalid Release signature)" $TMPLOG)
	set -e
	if [ ! -z "$RESULT" ] ; then
		echo "$(date -u) - initial debootstrap failed, sleeping 5min before retrying..."
		sudo rm -rf --one-file-system $CHROOT_TARGET
		sleep 5m
		sudo debootstrap $SUITE $CHROOT_TARGET $MIRROR
	fi
	rm -f $TMPLOG

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $CHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $CHROOT_TARGET/usr/sbin/policy-rc.d
	if [ ! -z "$http_proxy" ] ; then
		echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee    $CHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	fi
	echo "deb-src $MIRROR $SUITE main"        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list > /dev/null
	for i in $(seq 0 5) ; do
		[ -z "${EXTRA_SOURCES[$i]}" ] || echo "${EXTRA_SOURCES[$i]}"                     | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list >/dev/null
	done

	if $REPRODUCIBLE ; then
		TMPFILE=$(mktemp -u)
		add_repokey $CHROOT_TARGET/$TMPFILE
		sudo chroot $CHROOT_TARGET bash $TMPFILE
		rm $CHROOT_TARGET/$TMPFILE
	fi


	robust_chroot_apt update
	if [ -n "$1" ] ; then
		for d in proc dev dev/pts ; do
			sudo mount --bind /$d $CHROOT_TARGET/$d
		done
		set -x
		robust_chroot_apt update
		# first, (if), install diffoscope with all recommends...
		if [ "$1" = "diffoscope" ] ; then
			robust_chroot_apt install -y --install-recommends diffoscope
		fi
		robust_chroot_apt install -y --no-install-recommends "$@ sudo"
		# always try to use diffoscope from unstable
		if [ "$SUITE" = "testing" ] && [ "$1" = "diffoscope" ] ; then
			echo "deb $MIRROR unstable main"        | sudo tee -a $CHROOT_TARGET/etc/apt/sources.list > /dev/null
			robust_chroot_apt update
			# install diffoscope from unstable without re-adding all recommends...
			sudo chroot $CHROOT_TARGET apt-get install -y -t unstable --no-install-recommends diffoscope || echo "Warning: diffoscope from unstable is uninstallable at the moment."
		fi
		if ! $DEBUG ; then set +x ; fi
		if [ "$1" = "diffoscope" ] ; then
			echo
			sudo chroot $CHROOT_TARGET dpkg -l diffoscope
			echo
		fi
		# umount in reverse order
		for d in dev/pts dev proc ; do
			sudo umount -l $CHROOT_TARGET/$d
		done
		# configure sudo inside just like outside
		echo "jenkins    ALL=NOPASSWD: ALL" | sudo tee -a $CHROOT_TARGET/etc/sudoers.d/jenkins >/dev/null
		sudo chroot $CHROOT_TARGET chown root.root /etc/sudoers.d/jenkins
		sudo chroot $CHROOT_TARGET chmod 700 /etc/sudoers.d/jenkins
	fi
}

cleanup_schroot_sessions() {
	echo
	# FIXME: if this works well, move to _common.sh and use the same function from _maintenance.sh
	local RESULT=""
	for loop in $(seq 0 40) ; do
		ps fax|grep -v grep | grep -v schroot-create.sh |grep schroot || for i in $(schroot --all-sessions -l ) ; do ps fax|grep -v grep |grep -v schroot-create.sh | grep schroot || schroot -e -c $i ; done
		RESULT=$(schroot --all-sessions -l)
		if [ -z "$RESULT" ] ; then
			echo "No schroot sessions in use atm..."
			echo
			break
		fi
		echo "$(date -u) - schroot session cleanup loop $loop"
		sleep 15
	done
	echo
}

cleanup() {
	if [ -d $CHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $CHROOT_TARGET || ( echo "Warning: $CHROOT_TARGET could not be fully removed on forced cleanup." ; ls $CHROOT_TARGET -la )
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
	cleanup_schroot_sessions
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

cleanup_schroot_sessions
echo "$(date -u ) - renaming $CHROOT_TARGET to $SCHROOT_BASE/$TARGET"
set +e
sudo mv $CHROOT_TARGET $SCHROOT_BASE/"$TARGET"
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
