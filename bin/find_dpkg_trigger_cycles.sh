#!/bin/bash
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
# 
# Running
# =======
# 
# Just start `./find_dpkg_trigger_cycles.sh`. It will do the following:
# 
# 1. download apt sources and apt-file data for the amd64 Debian
#     using $1 as distro and store them in a directory tree rooted at
#    `./debian-sid-amd64`
# 2. go through all binary packages which have a file `DEBIAN/triggers` in their
#    control archive (the list is retrieved from binarycontrol.debian.net)
#    and for each package:
#   1. download and unpack its control archive
#   2. store all interest-await file triggers in the file `interested-file`
#   3. store all interest-await explicit triggers in the file `interested-explicit`
#   4. store all activate-await file triggers in the file `activated-file`
#   5. store all activate-await explicit triggers in the file `activated-explicit`
#   6. remove the downloaded binary package and unpacked control archive
# 3. go through `interested-file` and for each line:
#   1. calculate the dependency closure for the binary package and for
#      each package in the closure:
#     1. use `apt-file` to get all files of the package
#     2. check if the current file trigger matches any file in the package
#     3. store any hits in the file `result-file`
# 4. go through `interested-file` and for each line:
#   1. calculate the dependency closure for the binary package and for
#      each package in the closure:
#     1. check if the package activates the current file trigger
#     2. append any hits to the file `result-file`
# 5. go through `interested-explicit` and for each line:
#   1. calculate the dependency closure for the binary package and for
#      each package in the closure:
#     1. check if the package activate the current explicit trigger
#     2. store any hits in the file `result-explicit`
# 
# Files
# =====
# 
# interested-file
# ---------------
# 
# Associates binary packages to file triggers they are interested in. The first
# column is the binary package, the second column is either `interest` or
# `interest-await` and the last column the path they are interested in.
# 
# interested-explicit
# -------------------
# 
# Associates binary packages to explicit triggers they are interested in. The
# first column is the binary package, the second column is either `interest` or
# `interest-await` and the last column the name of the explicit trigger they are
# interested in.
# 
# activated-file
# --------------
# 
# Associates binary packages to file triggers they activate. The first column is
# the binary package, the second column is either `activate` or `activate-await`
# and the last column the path they activate.
# 
# activate-explicit
# -----------------
# 
# Associates binary packages to explicit triggers they activate. The first column
# is the binary package, the second column is either `activate` or
# `activate-await` and the last column the explicit trigger they activate.
# 
# result-file
# -----------
# 
# Associates binary packages with other binary packages they can form a file
# trigger cycle with. The first column is the binary package containing the file
# trigger, the second column is the file trigger, the third column is a binary
# package providing a path that triggers the binary package in the first column,
# the fourth column is the triggering path of provided by the binary package in
# the third column.
# 
# result-explicit
# ---------------
# 
# Associates binary packages with other binary packages they can form an explicit
# trigger cycle with. The first column is the binary package interested in the
# explicit trigger, the second column is the name of the explicit trigger, the
# third column is the binary package activating the trigger.

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# fail early
set -o pipefail
set -e

ARCH="amd64"
DIST="$1"
DIRECTORY="`pwd`/debian-$DIST-$ARCH"

APT_OPTS="-y"
#APT_OPTS=$APT_OPTS" -o Acquire::Check-Valid-Until=false" # because we use snapshot

mkdir -p $DIRECTORY
mkdir -p $DIRECTORY/etc/apt/
mkdir -p $DIRECTORY/etc/apt/trusted.gpg.d/
mkdir -p $DIRECTORY/etc/apt/apt.conf.d/
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

cat << END > "$DIRECTORY/etc/apt/apt.conf"
Apt::Architecture "$ARCH";
Dir::Etc::TrustedParts "$DIRECTORY/etc/apt/trusted.gpg.d";
Dir::Etc::Trusted "$DIRECTORY/etc/apt/trusted.gpg";
Dir "$DIRECTORY/";
Dir::Etc "$DIRECTORY/etc/apt/";
Dir::Etc::SourceList "$DIRECTORY/etc/apt/sources.list";
Dir::State "$DIRECTORY/var/lib/apt/";
Dir::State::Status "$DIRECTORY/var/lib/dpkg/status";
Dir::Cache "$DIRECTORY/var/cache/apt/";
END

APT_CONFIG="$DIRECTORY/etc/apt/apt.conf"
export APT_CONFIG

apt-get $APT_OPTS update

APT_FILE_OPTS="--architecture $ARCH"
APT_FILE_OPTS=$APT_FILE_OPTS" --cache $DIRECTORY/var/cache/apt/apt-file"
APT_FILE_OPTS=$APT_FILE_OPTS" --sources-list $DIRECTORY/etc/apt/sources.list"

apt-file $APT_FILE_OPTS update

printf "" > $DIRECTORY/interested-file
printf "" > $DIRECTORY/interested-explicit
printf "" > $DIRECTORY/activated-file
printf "" > $DIRECTORY/activated-explicit

scratch=$(mktemp -d -t tmp.dpkg_trigger_cycles.XXXXXXXXXX)
function finish {
	rm -rf "$scratch"
}
trap finish EXIT

# find all binary packages with /triggers$
#
# We cannot use "apt-get --print-uris download" and use the python module
# instead because the aforementioned command will error out if only one
# of the package names passed to it is not known by apt. This can easily
# happen in unstable where binarycontrol.debian.net still knows about
# a package which was already removed.
curl --retry 3 --retry-delay 10 --globoff "http://binarycontrol.debian.net/?q=&path=${DIST}%2F[^%2F]%2B%2Ftriggers%24&format=pkglist" \
	| xargs python3 -c "import apt,sys;c=apt.Cache();[print(n, c[n].candidate.uri) for n in sys.argv[1:] if n in c]" \
	| sort -u \
	| while read pkg url; do
	echo "working on $pkg..." >&2
	tmpdir=`mktemp -d --tmpdir="$scratch" -t dpkg-trigger-cycles-curl-XXXXXXXX`
	# we use curl as part of a pipeline to dpkg-deb instead of first
	# downloading to a temporary file and then using dpkg-deb on it,
	# because we do not want to download the full .deb (which could be very
	# large) but only the beginning of it until dpkg-deb has the
	# control.tar.gz extracted. After that, dpkg-deb will close the pipe
	# and thus signal curl to stop downloading. Downloading the full
	# binary package would be unnecessarily wasteful thousands of binary
	# packages in terms of bandwidth and disk requirements.
	#
	# curl is allowed to fail with exit status 23 because we want to stop
	# downloading immediately after control.tar.gz has been extracted
	( curl --retry 3 --retry-delay 10 --location --silent "$url" \
			|| { err="$?" && [ "$err" -eq 23 ]; } \
			|| ( echo "curl failed downloading $url for $pkg with exit $err">&2 && exec /srv/jenkins/bin/abort.sh ) ) \
		| dpkg-deb --ctrl-tarfile /dev/stdin \
		| tar -C "$tmpdir" --exclude=./md5sums -x
	if [ ! -f "$tmpdir/triggers" ]; then
		rm -r "$tmpdir"
		continue
	fi
	# find all triggers that are either interest or interest-await
	# and which are file triggers (start with a slash)
	{ egrep "^\s*interest(-await)?\s+/" "$tmpdir/triggers" || [ "$?" -ne 2 ]; } \
		| while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/interested-file
	{ egrep "^\s*interest(-await)?\s+[^/]" "$tmpdir/triggers" || [ "$?" -ne 2 ]; } \
		| while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/interested-explicit
	{ egrep "^\s*activate(-await)?\s+/" "$tmpdir/triggers" || [ "$?" -ne 2 ]; } \
		| while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/activated-file
	{ egrep "^\s*activate(-await)?\s+[^/]" "$tmpdir/triggers" || [ "$?" -ne 2 ]; } \
		| while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/activated-explicit
	rm -r "$tmpdir"
done

printf "" > $DIRECTORY/result-file

# go through those that are interested in a path and check them against the
# files provided by its dependency closure
cat $DIRECTORY/interested-file | while read pkg ttype ipath; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any
	# of the files they ship match one of the interested paths
	dose-ceve -c $pkg -T cudf -t deb \
		$DIRECTORY/var/lib/apt/lists/*_dists_${DIST}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| apt-file $APT_FILE_OPTS show -F --from-file - \
		| sed -ne "s ^\([^:]\+\):\s\+\(${ipath}\(\$\|/.*\)\) \1\t\2 p" \
		| while read dep cpath; do
			[ "$pkg" != "$dep" ] || continue
			echo "$pkg $ipath $dep $cpath"
		done >> $DIRECTORY/result-file
done

# go through those that are interested in a path and check them against the
# packages in the dependency closure which activate such a path
cat $DIRECTORY/interested-file | while read pkg ttype ipath; do
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
			sed -ne "s ^$dep\s\+activate\(-await\)\?\s\+\($ipath.*\) \2 p" $DIRECTORY/activated-file | while read cpath; do
				echo "$pkg $ipath $dep $cpath"
			done
		done >> $DIRECTORY/result-file
done

printf "" > $DIRECTORY/result-explicit

# go through those that are interested in an explicit trigger and check them
# against the packages in their dependency closure which activate it
cat $DIRECTORY/interested-explicit | while read pkg ttype iname; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any of
	# them activate the trigger in which this package is interested
	dose-ceve -c $pkg -T cudf -t deb \
		$DIRECTORY/var/lib/apt/lists/*_dists_${DIST}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| while read dep; do
			[ "$pkg" != "$dep" ] || continue
			if egrep "^$dep\s+activate(-await)?\s+$iname\s*$" $DIRECTORY/activated-explicit > /dev/null; then
				echo "$pkg $iname $dep"
			fi
		done >> $DIRECTORY/result-explicit
done

echo "+----------------------------------------------------------+"
echo "|                     result summary                       |"
echo "+----------------------------------------------------------+"
echo ""
echo "number of found file based trigger cycles:"
wc -l < $DIRECTORY/result-file
if [ `wc -l < $DIRECTORY/result-file` -ne 0 ]; then
	echo "Warning: found file based trigger cycles"
	echo "number of packages creating file based trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-file | sort | uniq | wc -l
	echo "unique packages creating file based trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-file | sort | uniq
fi
echo "number of found explicit trigger cycles:"
wc -l < $DIRECTORY/result-explicit
if [ `wc -l < $DIRECTORY/result-explicit` -ne 0 ]; then
	echo "Warning: found explicit trigger cycles"
	echo "number of packages creating explicit trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-explicit | sort | uniq | wc -l
	echo "unique packages creating explicit trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-explicit | sort | uniq
fi
if [ `wc -l < $DIRECTORY/result-file` -ne 0 ]; then
	cat << END
+----------------------------------------------------------+
|               file based trigger cycles                  |
+----------------------------------------------------------+

The following table has four columns A, B, C and D. The first column A shows a
binary package which shows interested in a certain path. The second column B
shows the path that A is interested in. The third column C is a binary package
that A (directly or indirectly) depends on. The fourth column D shows the path
that C provides and which is triggering A through its interest in B.

The cycle is created because when C is put into the triggers-awaited state
(because it triggers A), then it cannot satisfy dependencies until it leaves that
state. But:

 - for C to leave the triggers-awaited state, the trigger has to be resolved
   by A, which cannot happen unless A gets configured
 - to configure A, its dependency on C has to be resolved which cannot happen
   unless C leaves the triggers-awaited state

This creates the cycle if the packages are installed in a fitting order.
END
	cat $DIRECTORY/result-file
fi
if [ `wc -l < $DIRECTORY/result-explicit` -ne 0 ]; then
	cat << END
+----------------------------------------------------------+
|               explicit trigger cycles                    |
+----------------------------------------------------------+

The following table has three columns A, B and C. The first column A shows a
binary package which shows interested in a certain trigger. The second column B
shows the trigger that A is interested in. The third column C is a binary
package that A (directly or indirectly) depends on and which explicitly
activates the trigger from column B.

The cycle is created because when C is put into the triggers-awaited state
(because it triggers A), then it cannot satisfy dependencies until it leaves that
state. But:

 - for C to leave the triggers-awaited state, the trigger has to be resolved
   by A, which cannot happen unless A gets configured
 - to configure A, its dependency on C has to be resolved which cannot happen
   unless C leaves the triggers-awaited state

This creates the cycle if the packages are installed in a fitting order.
END
	cat $DIRECTORY/result-explicit
fi
