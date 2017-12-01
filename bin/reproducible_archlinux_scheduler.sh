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
	echo "$(date -u ) - $(cat ${ARCHLINUX_PKGS}_full_pkgbase_list | wc -l) Arch Linux packages are known in total to us:"

	for REPO in $ARCHLINUX_REPOS ; do
		TMPPKGLIST=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
		echo "$(date -u ) - updating list of available packages in repository '$REPO'."
		grep "^$REPO" "$ARCHLINUX_PKGS"_full_pkgbase_list | \
			while read repo pkgbase version; do
				if [ ! -d $BASE/archlinux/$REPO/$pkgbase ] ; then
					let NEW+=1
					echo "$(date -u ) - scheduling new package $REPO/$pkgbase... "
					mkdir -p $BASE/archlinux/$REPO/$pkgbase
					touch $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build
				else
					VERSION=$(cat $BASE/archlinux/$REPO/$pkgbase/pkg.version 2>/dev/null || echo 0.rb-unknown-1)
					if [ "$VERSION" != "0.rb-unknown-1" ] && [ ! -f $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build ] ; then
						if [ "$(schroot --run-session -c $SESSION --directory /var/tmp -- vercmp $version $VERSION)" = "1" ] ; then
							let UPDATED+=1
							echo "$(date -u ) - we know about $REPO/$pkgbase $VERSION, but the repo has $version, so rescheduling... "
							mkdir -p $BASE/archlinux/$REPO/$pkgbase
							touch $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build
						fi
					fi
				fi
				printf '%s %s\n' "$pkgbase" "$version" >> $TMPPKGLIST
			done
		mv $TMPPKGLIST "$ARCHLINUX_PKGS"_"$REPO"
		echo "$(date -u ) - $(cat ${ARCHLINUX_PKGS}_$REPO | wc -l) packages in repository '$REPO' are known to us:"
	done
	rm "$ARCHLINUX_PKGS"_full_pkgbase_list
	schroot --end-session -c $SESSION
	if [ $NEW -ne 0 ] || [ $UPDATED -ne 0 ] ; then
		irc_message archlinux-reproducible "scheduled $NEW entirely new packages and $UPDATED packages with newer versions."
	fi
	echo "$(date -u ) - scheduled $NEW/$UPDATED packages."
}

echo "$(date -u ) - Updating Arch Linux repositories."
UPDATED=0
NEW=0
update_archlinux_repositories
echo "$(date -u ) - Done updating Arch Linux repositories."

# vim: set sw=0 noet :
