#!/bin/sh
#
# Copyright 2014 Johannes Schauer <j.schauer@email.de>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

set -e

ARCH="amd64"
DIST="sid"
MIRROR="http://http.debian.net/debian"
#MIRROR="http://snapshot.debian.org/archive/debian/20141211T041251Z/"
DIRECTORY="`pwd`/debian-$DIST-$ARCH"

#FIXME: if the host has more than one arch enabled then those Packages files will be downloaded as well

APT_OPTS="-y"
APT_OPTS=$APT_OPTS" -o Apt::Architecture=$ARCH"
APT_OPTS=$APT_OPTS" -o Dir::Etc::TrustedParts=$DIRECTORY/etc/apt/trusted.gpg.d"
APT_OPTS=$APT_OPTS" -o Dir::Etc::Trusted=$DIRECTORY/etc/apt/trusted.gpg"
APT_OPTS=$APT_OPTS" -o Dir=$DIRECTORY/"
APT_OPTS=$APT_OPTS" -o Dir::Etc=$DIRECTORY/etc/apt/"
APT_OPTS=$APT_OPTS" -o Dir::Etc::SourceList=$DIRECTORY/etc/apt/sources.list"
APT_OPTS=$APT_OPTS" -o Dir::State=$DIRECTORY/var/lib/apt/"
APT_OPTS=$APT_OPTS" -o Dir::State::Status=$DIRECTORY/var/lib/dpkg/status"
APT_OPTS=$APT_OPTS" -o Dir::Cache=$DIRECTORY/var/cache/apt/"
#APT_OPTS=$APT_OPTS" -o Acquire::Check-Valid-Until=false" # because we use snapshot

mkdir -p $DIRECTORY
mkdir -p $DIRECTORY/etc/apt/
mkdir -p $DIRECTORY/etc/apt/trusted.gpg.d/
mkdir -p $DIRECTORY/etc/apt/sources.list.d/
mkdir -p $DIRECTORY/etc/apt/preferences.d/
mkdir -p $DIRECTORY/var/lib/apt/
mkdir -p $DIRECTORY/var/lib/apt/lists/partial/
mkdir -p $DIRECTORY/var/lib/dpkg/
mkdir -p $DIRECTORY/var/cache/apt/
mkdir -p $DIRECTORY/var/cache/apt/apt-file/

cp /etc/apt/trusted.gpg.d/* $DIRECTORY/etc/apt/trusted.gpg.d/

touch $DIRECTORY/var/lib/dpkg/status

echo deb $MIRROR $DIST main > $DIRECTORY/etc/apt/sources.list

apt-get $APT_OPTS update

APT_FILE_OPTS="--architecture $ARCH"
APT_FILE_OPTS=$APT_FILE_OPTS" --cache $DIRECTORY/var/cache/apt/apt-file"
APT_FILE_OPTS=$APT_FILE_OPTS" --sources-list $DIRECTORY/etc/apt/sources.list"

apt-file $APT_FILE_OPTS update

printf "" > interested-file
printf "" > interested-explicit
printf "" > activated-file
printf "" > activated-explicit

# find all binary packages with /triggers$
curl "http://binarycontrol.debian.net/?q=&path=%2Ftriggers%24&format=pkglist" \
	| xargs apt-get $APT_OPTS --print-uris download \
	| sed -ne "s/^'\([^']\+\)'\s\+\([^_]\+\)_.*/\2 \1/p" \
	| sort \
	| while read pkg url; do
	echo "working on $pkg..." >&2
	mkdir DEBIAN
	curl --location --silent "$url" \
		| ./extract_binary_control.py \
		| tar -C "DEBIAN" --exclude=./md5sums -xz
	if [ ! -f DEBIAN/triggers ]; then
		rm -r DEBIAN
		continue
	fi
	# find all triggers that are either interest or interest-await
	# and which are file triggers (start with a slash)
	egrep "^\s*interest(-await)?\s+/" DEBIAN/triggers | while read line; do
		echo "$pkg $line"
	done >> interested-file
	egrep "^\s*interest(-await)?\s+[^/]" DEBIAN/triggers | while read line; do
		echo "$pkg $line"
	done >> interested-explicit
	egrep "^\s*activate(-await)?\s+/" DEBIAN/triggers | while read line; do
		echo "$pkg $line"
	done >> activated-file
	egrep "^\s*activate(-await)?\s+[^/]" DEBIAN/triggers | while read line; do
		echo "$pkg $line"
	done >> activated-explicit
	rm -r DEBIAN
done

printf "" > result-file

# go through those that are interested in a path and check them against the
# files provided by its dependency closure
cat interested-file | while read pkg ttype ipath; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any
	# of the files they ship match one of the interested paths
	dose-ceve -c $pkg -T cudf -t deb \
		$DIRECTORY/var/lib/apt/lists/*_dists_${DIST}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| apt-file $APT_FILE_OPTS show -F --from-file - \
		| sed -ne "s ^\([^:]\+\):\s\+\(${ipath}/.*\) \1\t\2 p" \
		| while read dep cpath; do
			[ "$pkg" != "$dep" ] || continue
			echo "$pkg $ipath $dep $cpath"
		done >> result-file
done

# go through those that are interested in a path and check them against the
# packages in the dependency closure which activate such a path
cat interested-file | while read pkg ttype ipath; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any
	# of them activate a matching path
	dose-ceve -c $pkg -T cudf -t deb \
		$DIRECTORY/var/lib/apt/lists/*_dists_${DIST}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| while read dep; do
			[ "$pkg" != "$dep" ] || continue
			# using the space as sed delimeter because ipath has slashes
			# a space should work because neither package names nor paths have them
			sed -ne "s ^$dep\s\+activate\(-await\)\?\s\+\($ipath.*\) \2 p" activated-file | while read cpath; do
				echo "$pkg $ipath $dep $cpath"
			done
		done >> result-file
done

printf "" > result-explicit

# go through those that are interested in an explicit trigger and check them
# against the packages in their dependency closure which activate it
cat interested-explicit | while read pkg ttype iname; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any of
	# them activate the trigger in which this package is interested
	dose-ceve -c $pkg -T cudf -t deb \
		$DIRECTORY/var/lib/apt/lists/*_dists_${DIST}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| while read dep; do
			[ "$pkg" != "$dep" ] || continue
			if egrep "^$dep\s+activate(-await)?\s+$iname\s*$" activated-explicit > /dev/null; then
				echo "$pkg $iname $dep"
			fi
		done >> result-explicit
done
