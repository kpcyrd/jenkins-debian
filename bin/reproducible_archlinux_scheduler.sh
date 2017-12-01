#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

set -e

update_archlinux_repositories() {
	local SESSION="archlinux-scheduler-$RANDOM"
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	schroot --run-session -c $SESSION --directory /var/tmp -- sudo pacman -Syu --noconfirm
	# Get a list of unique package bases.  Non-split packages don't have a pkgbase set
	# so we need to use the pkgname for them instead.
	schroot --run-session -c $SESSION --directory /var/tmp -- expac -S '%r %e %n %v' | \
		while read repo pkgbase pkgname version; do
			if [[ "$pkgbase" = "(null)" ]]; then
				printf '%s %s %s\n' "$repo" "$pkgname" "$version"
			else
				printf '%s %s %s\n' "$repo" "$pkgbase" "$version"
			fi
		done | sort -u > "$ARCHLINUX_PKGS"_full_pkgbase_list

	for REPO in $ARCHLINUX_REPOS ; do
		echo "$(date -u ) - updating list of available packages in repository '$REPO'."
		grep "^$REPO" "$ARCHLINUX_PKGS"_full_pkgbase_list | \
			while read repo pkgbase version; do
				printf '%s %s\n' "$pkgbase" "$version"
				VERSION=$(cat $BASE/archlinux/$REPO/$pkgbase/pkg.version 2>/dev/null || echo 0.rb-unknown-1)
				if [ "$VERSION" = "0.rb-unknown-1" ] ; then
					echo "$(date -u ) - we know $REPO/$pkgbase has dummy $VERSION version, but c'est la vie."
				elif [ "$(schroot --run-session -c $SESSION --directory /var/tmp -- vercmp $version $VERSION)" = "1" ] ; then
					echo "$(date -u ) - we know about $REPO/$pkgbase $VERSION, but the repo has $version, so rescheduling."
					touch $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build
				fi
			done > "$ARCHLINUX_PKGS"_"$REPO"
		echo "$(date -u ) - these packages in repository '$REPO' are known to us:"
		cat ${ARCHLINUX_PKGS}_$REPO
	done
	rm "$ARCHLINUX_PKGS"_full_pkgbase_list
	schroot --end-session -c $SESSION
}

echo "$(date -u ) - Updating Arch Linux repositories."
update_archlinux_repositories

# vim: set sw=0 noet :
