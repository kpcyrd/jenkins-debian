#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2016 Valerie Young <spectranaut@riseup.net>
# Licensed under GPL-2
#
# Depends: python3, postgres, reproducible_common

import subprocess
import sys
import os
import argparse

parser = argparse.ArgumentParser(
    description='Create new Postgres database (reproducibledb) from backup.',
    epilog='This script creates a database and populates it with the result'
           ' of a "pg_dump". It will not run if the database already exists.'
           ' Database name and database user are defined in'
           ' reproducible_common.py .')
parser.add_argument("-f", "--backup-file", required=True,
                    help='result of a "pg_dump"')
args, unknown_args = parser.parse_known_args()
BACKUP_FILE = args.backup_file
if not os.access(BACKUP_FILE, os.R_OK):
    log.error("Backup file does not exist.")
    sys.exit(1)

# We skip the database connection because the database
# may not exist yet, but we would like to use the constants
# available in reproducible_common.py
sys.argv.append('--skip-database-connection')
from reproducible_common import *

# Get database defined in reproducible_common.py
# Note: this script will ONLY run on a completely new DB. The backup
# file will be used to re-creates the schema and populate tables. If
# run on a database with existing information, it will error.
DB_NAME = PGDATABASE
DB_USER = 'jenkins';

try:
    # check is the user exists, if not created it
    log.info("Checking if postgres role exists...")
    query = "SELECT 1 FROM pg_roles WHERE rolname='%s';" % DB_USER
    command = ['sudo', '-u', 'postgres', 'psql', '-tAc', query]
    result = subprocess.check_output(command).decode("utf-8").strip()

    if result == '1':
        log.info("user exists.")
    else:
        log.info("Postgres role %s does not exist. Creating role."
                 % DB_USER)
        check_call(['sudo', '-u', 'postgres', 'createuser', '-w', DB_USER])

    # check is the database exists
    log.info("Checking if postgres database exists...")
    query = "SELECT 1 FROM pg_database WHERE datname='%s'" % DB_NAME
    command = ['sudo', '-u', 'postgres', 'psql', '-tAc', query]
    result = subprocess.check_output(command).decode("utf-8").strip()

    if result == '1':
        print_critical_message('Database "%s" already exists. This script can'
            ' only be run on a completely new database. If you are certain you'
            ' want to clone "%s" in "%s", please drop the database "%s" and'
            ' run this script again.' % (DB_NAME, BACKUP_FILE, DB_NAME, DB_NAME))
        sys.exit(1)
    else:
        log.info("Postgres database %s does not exist. Creating database."
                 % DB_NAME)
        check_call(['sudo', '-u', 'postgres', 'createdb', '-O', DB_USER,
                    '-w', DB_NAME])

except FileNotFoundError:
    print_critical_message("Postgres is not installed. Install postgres before continuing.")
    sys.exit(1)

log.info("Copying backup to new database...")
check_call(['psql', '-U', DB_USER, '-d', DB_NAME, '-f', BACKUP_FILE])
