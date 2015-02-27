#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# support different suites
if [ -z "$1" ] ; then
	SUITE="sid"
else
	SUITE="$1"
fi

#
# create script to configure a pbuilder chroot
#
create_setup_tmpfile() {
	TMPFILE=$1
	shift
	if [ "$1" = "experimental" ] ; then
		EXTRA="echo 'deb $MIRROR experimental main' > /etc/apt/sources.list.d/experimental.list
echo 'deb-src $MIRROR experimental main' >> /etc/apt/sources.list.d/experimental.list"
		shift
	fi
	cat > $TMPFILE <<- EOF
#
# this script is run within the pbuilder environment to further customize it
#
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
echo 'deb http://reproducible.alioth.debian.org/debian/ ./' > /etc/apt/sources.list.d/reproducible.list
$EXTRA
apt-gt update
apt-get install -y $@
echo
dpkg -l
echo
for i in \$(dpkg -l |grep ^ii |awk -F' ' '{print \$2}'); do   apt-cache madison "\$i" | head -1 | grep reproducible.alioth.debian.org || true  ; done
echo
EOF
}


#
# setup pbuilder for reproducible builds
#
setup_pbuilder() {
	SUITE=$1
	shift
	NAME=$1
	shift
	PACKAGES="$@"
	echo "$(date) - creating /var/cache/pbuilder/${NAME}.tgz now..."
	TMPFILE=$(mktemp)
	LOG=$(mktemp)
	if [ "$SUITE" == "experimental" ] ; then
		SUITE=sid
		PACKAGES="experimental $PACKAGES"
	fi
	create_setup_tmpfile ${TMPFILE} "${PACKAGES}"
	sudo pbuilder --create --basetgz /var/cache/pbuilder/${NAME}-new.tgz --distribution $SUITE
	sudo pbuilder --execute --save-after-exec --basetgz /var/cache/pbuilder/${NAME}-new.tgz -- ${TMPFILE} | tee ${LOG}
	echo
	echo "Now let's see whether the correct packages where installed..."
	for PKG in ${PACKAGES} ; do
		grep "http://reproducible.alioth.debian.org/debian/ ./ Packages" ${LOG} \
			| grep -v grep | grep "${PKG} " \
			|| ( echo ; echo "Package ${PKG} is not installed at all or probably rather not in our version, so removing the chroot and exiting now." ; sudo rm -v /var/cache/pbuilder/${NAME}-new.tgz ; exit 1 )
	done
	sudo mv /var/cache/pbuilder/${NAME}-new.tgz /var/cache/pbuilder/${NAME}.tgz
	rm ${TMPFILE}
	echo
}

# FIXME: base-reproducible should be renamed to include the suite
setup_pbuilder $SUITE base-reproducible dpkg dpkg-dev debhelper
