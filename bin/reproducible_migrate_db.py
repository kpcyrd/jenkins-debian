#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2016 Valerie Young <spectranaut@riseup.net>
# Licensed under GPL-2
#
# Depends: sqlalchemy, reproducible_common

from sqlalchemy import *
from sqlalchemy.schema import *
import sqlalchemy.util
from pprint import pprint
import subprocess
import sys
import os
import csv

# We skip the database connection because the database
# may not exist yet, but we would like to use the constants
# available in reproducible_common.py
sys.argv.append('--skip-database-connection')
from reproducible_common import *

# Database defined in reproducible_common.py
DEST_DB_NAME = PGDATABASE
DEST_DB_USER = os.environ['USER']

# Old SQLite database
SOURCE_DB_NAME = '/var/lib/jenkins/reproducible.db'

try:
    # check is the user exists, if not created it
    log.info("Checking if postgres role exists...")
    query = "SELECT 1 FROM pg_roles WHERE rolname='%s';" % DEST_DB_USER
    command = ['sudo', '-u', 'postgres', 'psql', '-tAc', query]
    result = subprocess.check_output(command).decode("utf-8").strip()

    if result == '1':
        log.info("user exists.")
    else:
        log.info("Postgres role %s does not exist. Creating role."
                 % DEST_DB_USER)
        check_call(['sudo', '-u', 'postgres', 'createuser', '-w', DEST_DB_USER])

    # check is the database exists, if not created it
    log.info("Checking if postgres database exists...")
    query = "SELECT 1 FROM pg_database WHERE datname='%s'" % DEST_DB_NAME
    command = ['sudo', '-u', 'postgres', 'psql', '-tAc', query]
    result = subprocess.check_output(command).decode("utf-8").strip()

    if result == '1':
        log.info("database exists.")
    else:
        log.info("Postgres database %s does not exist. Creating database."
                 % DEST_DB_NAME)
        check_call(['sudo', '-u', 'postgres', 'createdb', '-O', DEST_DB_USER,
                    '-w', DEST_DB_NAME])

except FileNotFoundError:
    print_critical_message("Postgres is not installed. Install postgres before continuing.")
    sys.exit(1)

# Run reproducible_db_maintenance. This will create the appropriate schema.
db_maintenance = os.path.join(BIN_PATH, "reproducible_db_maintenance.py")
check_call([db_maintenance])

# Connect to both databases
dest_engine = create_engine("postgresql:///%s" % DEST_DB_NAME)
dest_conn = dest_engine.connect()
source_engine = create_engine("sqlite:///%s" % SOURCE_DB_NAME)
source_conn = source_engine.connect()

# Load all table definitions for both databases. They should be identical
# (both up to date according to reproducible_db_maintenance.py)
source_metadata = MetaData(source_engine)
source_metadata.reflect()
dest_metadata = MetaData(dest_engine)
dest_metadata.reflect()

# The order in which we will copy the table
all_tables = ['sources', 'issues', 'notes', 'removed_packages', 'results',
              'stats_bugs', 'stats_build', 'stats_builds_age', 'stats_notes',
              'stats_issues', 'stats_meta_pkg_state', 'stats_builds_per_day',
              'stats_pkg_state']

# Get all table definitions in source and destination. If the table doesn't
# exist in one of these two places, an error will occur.
dest_tables = {t: Table(t, dest_metadata, autoload=True) for t in all_tables}
source_tables = {t: Table(t, source_metadata, autoload=True) for t in all_tables}

for table in all_tables:
    log.info("Copying table: "  + table)
    dest_table = dest_tables[table]
    dest_columns = dest_table.columns.keys()
    source_table = source_tables[table]
    source_columns = source_table.columns.keys()

    if table in ['notes', 'results']:
        sources = Table('sources', source_metadata, autoload=True)
        # only select rows with correct foreign references to the SOURCES table
        query = sql.select(source_table.c).select_from(
            source_table.join(sources))

        # save rows with incorrect foreign references to the SOURCES table
        ignored_query = select(source_table.c).select_from(source_table).where(
            source_table.c.package_id.notin_(select([sources.c.id])))
        ignored_results = source_conn.execute(ignored_query).fetchall()
        if len(ignored_results):
            log.info('Ignoring bad foreign keys in %s. Dumping rows to '
                     'ignored_rows_%s.csv' % (table, table))
            with open('ignored_rows_' + table + '.csv', 'w') as f:
                writer = csv.DictWriter(f, fieldnames=ignored_results[0].keys())
                writer.writeheader()
                for row in ignored_results:
                    writer.writerow(dict(row))
    else:
        query = "select * from %s" % table

    # Perform each table copy in a single transaction
    transaction = dest_conn.begin()
    try:
        for record in source_conn.execute(query):
            data = {}
            for c in source_columns:
                col = c.lower()
                value = getattr(record, c)
                if str(dest_table.c[col].type) == 'INTEGER' and value == "":
                    # there exist empty string values in the sqlite database
                    # for integers. This will result in an error if we try to
                    # write these values to the postgres db.
                    log.info("column %s has empty string/null value" % col)
                else:
                    data[col] = value

            try:
                dest_conn.execute(dest_table.insert(), [data])
            except:
                log.critical("Could not insert: %s" % data)
                raise

        # Commit the whole table at once
        transaction.commit()
    except:
        transaction.rollback()
        log.error("Transaction rolled back")
        raise

# For the autoincrementing columns to work correctly, we must set the next
# value of the sequence to be the next highest available ID.
table_sequences = {t : t + "_id_seq" for t in ['sources', 'results']}

for table in table_sequences:
    query = "select setval('%s', (select max(id)+1 from %s))"
    dest_conn.execute(query % (table_sequences[table], table))
