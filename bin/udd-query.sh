#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# multiarch_versionskew UDD query by Stuart Prescott <stuart@debian.org>
# orphaned_without_o_bug by Johannes Schauer <j.schauer@email.de>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

udd_query() {
	#
	# Actually query UDD and save result in $UDD file
	#
	echo "$(date) - querying UDD using ${SQL_QUERY}"
	echo
	PGPASSWORD=public-udd-mirror \
		psql -U public-udd-mirror \
		-h public-udd-mirror.xvm.mit.edu -p 5432 \
		-t \
		udd -c"${SQL_QUERY}" > $UDD
}

multiarch_versionskew() {
	if [ -z "$1" ] ; then
		echo "Warning: no distro supplied, assuming sid."
		DISTR=sid
	else
		DISTRO=$1
	fi
	#
	# SQL query for detecting multi-arch version skew
	#
	SQL_QUERY="SELECT DISTINCT source FROM
		(SELECT DISTINCT source, package, version
			FROM packages WHERE
				release='$DISTRO' AND
				multi_arch='same' AND
					architecture IN ('amd64', 'arm64', 'armel', 'armhf', 'i386',
					'kfreebsd-amd64', 'kfreebsd-i386', 'mips', 'mipsel',
					'powerpc', 'ppc64el', 's390x')
				ORDER BY source) AS all_versions
				GROUP BY source, package
				HAVING count(*) > 1
			ORDER BY source ;"

	udd_query
	cat $UDD
	# TODO: turn source package names into links
	# TODO: show versions (per arch) too
	rm $UDD
}

orphaned_without_o_bug() {
	WNPPRM=$(mktemp)
	SORTED_UDD=$(mktemp)
	RES1=$(mktemp)

	SQL_QUERY="SELECT DISTINCT source
		FROM sources
		WHERE maintainer LIKE '%packages@qa.debian.org%'
		AND release='sid'
		ORDER BY source ; "

	udd_query
	cat $UDD | tr -d ' ' | sort | uniq > "$SORTED_UDD"

	curl --silent https://qa.debian.org/data/bts/wnpp_rm \
		| cut -d ' ' -f 1 | tr -d ':' | sort | uniq > "$WNPPRM"

	comm -23 "$SORTED_UDD" "$WNPPRM" > "$RES1"

	# $RES1 now contains all packages that have packages@qa.debian.org as the
	# maintainer but do not appear on https://qa.debian.org/data/bts/wnpp_rm
	# (because they are missing a bug)
	# we have to remove all the packages that appear in experimental but do not
	# have packages@qa.debian.org as a maintainer (i.e: they found a new one)

	SQL_QUERY="SELECT DISTINCT source
		FROM sources
		WHERE maintainer NOT LIKE '%packages@qa.debian.org%'
		AND release='experimental'
		ORDER BY source ; "
	udd_query
	cat $UDD | tr -d ' ' | sort | uniq > "$SORTED_UDD"

	echo "The following packages are maintained by packages@qa.debian.org"
	echo "but are missing a wnpp bug according to https://qa.debian.org/data/bts/wnpp_rm"
	echo

	comm -13 "$SORTED_UDD" "$RES1"

	rm -f "$UDD" "$WNPPRM" "$RES1" "$SORTED_UDD"

}

#
# main
#
UDD=$(mktemp)
case QUERY in
	orphaned_without_o_bug)
			orphaned_without_o_bug
			;;
	multiarch_versionskew)
			multiarch_versionskew $2
			;;
	*)
			echo "unknown query requested, exiting... please provide patches :)"
			;;
esac

