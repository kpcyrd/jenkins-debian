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
	SUITE="unstable"
else
	SUITE="$1"
fi

#
# create script to configure a pbuilder chroot
#
create_setup_tmpfile() {
	TMPFILE=$1
	shift
	cat >> $TMPFILE <<- EOF
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
echo 'deb http://reproducible.alioth.debian.org/debian/ ./' > /etc/apt/sources.list.d/reproducible.list
echo
echo "Configuring APT to ignore the Release file expiration"
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/398future
echo
apt-get update
apt-get -y upgrade
apt-get install -y $@
echo
apt-cache policy
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
	PACKAGES="$@"						# from our repo
	EXTRA_PACKAGES="locales-all fakeroot disorderfs"	# from sid
	echo "$(date -u) - creating /var/cache/pbuilder/${NAME}.tgz now..."
	TMPFILE=$(mktemp --tmpdir=$TEMPDIR pbuilder-XXXXXXXXX)
	LOG=$(mktemp --tmpdir=$TEMPDIR pbuilder-XXXXXXXX)
	if [ "$SUITE" = "experimental" ] ; then
		SUITE=unstable
		echo "echo 'deb $MIRROR experimental main' > /etc/apt/sources.list.d/experimental.list" > ${TMPFILE}
		echo "echo 'deb-src $MIRROR experimental main' >> /etc/apt/sources.list.d/experimental.list" >> ${TMPFILE}
	fi
	# use host apt proxy configuration for pbuilder too
	if [ ! -z "$http_proxy" ] ; then
		echo "echo '$(cat /etc/apt/apt.conf.d/80proxy)' > /etc/apt/apt.conf.d/80proxy" >> ${TMPFILE}
		pbuilder_http_proxy="--http-proxy $http_proxy"
	fi
	# setup base.tgz
	sudo pbuilder --create $pbuilder_http_proxy --basetgz /var/cache/pbuilder/${NAME}-new.tgz --distribution $SUITE --extrapackages "$EXTRA_PACKAGES"
	# apply further customisations, eg. install $PACKAGES from our repo
	create_setup_tmpfile ${TMPFILE} "${PACKAGES}"
	if [ "$DEBUG" = "true" ] ; then
		cat "$TMPFILE"
	fi
	sudo pbuilder --execute $pbuilder_http_proxy --save-after-exec --basetgz /var/cache/pbuilder/${NAME}-new.tgz -- ${TMPFILE} | tee ${LOG}
	# finally, confirm things are as they should be
	echo
	echo "Now let's see whether the correct packages where installed..."
	for PKG in ${PACKAGES} ; do
		egrep "http://reproducible.alioth.debian.org/debian(/|) ./ Packages" ${LOG} \
			| grep -v grep | grep "${PKG} " \
			|| ( echo ; echo "Package ${PKG} is not installed at all or probably rather not in our version, so removing the chroot and exiting now." ; sudo rm -v /var/cache/pbuilder/${NAME}-new.tgz ; rm $TMPFILE $LOG ; exit 1 )
	done
	sudo mv /var/cache/pbuilder/${NAME}-new.tgz /var/cache/pbuilder/${NAME}.tgz
	# create stamp file to record initial creation date minus some hours so the file will be older than 24h when checked in <24h...
	touch -d "$(date -u -d '6 hours ago' '+%Y-%m-%d %H:%M')" /var/log/jenkins/${NAME}.tgz.stamp
	rm ${TMPFILE} ${LOG}
}

#
# main
#
BASETGZ=/var/cache/pbuilder/$SUITE-reproducible-base.tgz
STAMP=/var/log/jenkins/$SUITE-reproducible-base.tgz.stamp
OLDSTAMP=$(find $STAMP -mtime +1 -exec ls -lad {} \; || echo "nostamp")
if [ -n "$OLDSTAMP" ] || [ ! -f $BASETGZ ] || [ ! -f $STAMP ] ; then
	if [ ! -f $BASETGZ ] ; then
		echo "No $BASETGZ exists, creating a new one..."
	else
		echo "$BASETGZ outdated, creating a new one..."
	fi
	setup_pbuilder $SUITE $SUITE-reproducible-base dpkg dpkg-dev
else
	echo "$BASETGZ not old enough, doing nothing..."
fi
echo
