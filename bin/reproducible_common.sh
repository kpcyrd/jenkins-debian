#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# included by all reproducible_*.sh scripts
#
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ -f $PACKAGES_DB ] && [ -f $INIT ] ; then
	if [ -f $PACKAGES_DB.lock ] ; then
		for i in $(seq 0 100) ; do
			sleep 15
			if [ ! -f $PACKAGES_DB.lock ] ; then
				break
			fi
		done
		echo "$PACKAGES_DB.lock still exist, exiting."
		exit 1
	fi
elif [ ! -f ${PACKAGES_DB} ] ; then
	echo "Warning: $PACKAGES_DB doesn't exist, creating it now."
	echo 
	# create sqlite db if needed
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE source_packages
		(name TEXT NOT NULL,
		version TEXT NOT NULL,
		status TEXT NOT NULL
		CHECK (status IN ("blacklisted", "FTBFS","reproducible","unreproducible","404", "not for us")),
		build_date TEXT NOT NULL,
		PRIMARY KEY (name))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE sources_scheduled
		(name TEXT NOT NULL,
		date_scheduled TEXT NOT NULL,
		date_build_started TEXT NOT NULL,
		PRIMARY KEY (name))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE sources
		(name TEXT NOT NULL,
		version TEXT NOT NULL)'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_pkg_state
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		untested INTEGER,
		reproducible INTEGER,
		unreproducible INTEGER,
		FTBFS INTEGER,
		other INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_builds_per_day
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		reproducible INTEGER,
		unreproducible INTEGER,
		FTBFS INTEGER,
		other INTEGER,
		PRIMARY KEY (datum))'
	sqlite3 ${PACKAGES_DB} '
		CREATE TABLE stats_builds_age
		(datum TEXT NOT NULL,
		suite TEXT NOT NULL,
		oldest_reproducible REAL,
		oldest_unreproducible REAL,
		oldest_FTBFS REAL,
		PRIMARY KEY (datum))'
	# 60 seconds timeout when trying to get a lock
	cat >/var/lib/jenkins/reproducible.init <<-EOF
.timeout 60000
EOF
fi

