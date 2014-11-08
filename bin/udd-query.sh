#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# UDD query by Stuart Prescott <stuart@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

#
# have all needed params been supplied?
#
if [ -z "$2" ] ; then
	echo "Need at two params, distro + query_name..."
	exit 1
fi

DISTRO=$1
declare -A SQL_QUERY
QUERY=$2

#
# more to come, hopefully
#
if [ "$QUERY" != "multiarch_versionskew" ] ; then
	echo "unknown query requested, exiting... please provide patches :)"
	exit 1
fi

#
# SQL query for detecting multi-arch version skew
#
SQL_QUERY["multiarch_versionskew"]="
  SELECT DISTINCT source FROM
      (SELECT DISTINCT source, package, version
          FROM packages
          WHERE
              release='$DISTRO' AND
              multi_arch='same' AND
              architecture IN ('amd64', 'arm64', 'armel', 'armhf', 'i386',
                      'kfreebsd-amd64', 'kfreebsd-i386', 'mips', 'mipsel',
                      'powerpc', 'ppc64el', 's390x')
          ORDER BY source) AS all_versions
      GROUP BY source, package
      HAVING count(*) > 1
      ORDER BY source
  ;
"


#
# Actually query UDD
#
echo "$(date) - querying UDD using ${SQL_QUERY[$QUERY]}"
echo
PGPASSWORD=public-udd-mirror \
  psql -U public-udd-mirror \
        -h public-udd-mirror.xvm.mit.edu -p 5432 \
        -t \
        udd -c"${SQL_QUERY[$QUERY]}"

# TODO: turn source package names into links
# TODO: show versions (per arch) too
