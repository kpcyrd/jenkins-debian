#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3 python-apt python3-yaml
#
# Import the content of the notes.git repository into the reproducible database

from reproducible_common import *

import os
import apt
import yaml
import json
from sqlalchemy import sql
from apt_pkg import version_compare

NOTES = 'packages.yml'
ISSUES = 'issues.yml'


def load_notes():
    """
    format:
    { 'package_name': [
        {'suite': 'unstable', 'version': '0.0', 'comments': None,
         'bugs': [1234, 5678], 'issues': ['blalba','auauau']},
        {'suite': 'testing', 'version': None, 'comments': 'strstr',
          'bugs': [], 'issues': []}],
      'package_name':<etc> }
    """
    with open(NOTES) as fd:
        original = yaml.load(fd)
    log.info("notes loaded. There are " + str(len(original)) +
             " packages listed")
    notes = {}
    for pkg in sorted(original):
        assert isinstance(pkg, str)
        try:
            assert 'version' in original[pkg]
        except AssertionError:
            print_critical_message(pkg + ' does not include a version')
            irc_msg('The note for ' + pkg + ' does not include a version.')
        query = 'SELECT s.id, s.version, s.suite ' + \
                'FROM results AS r JOIN sources AS s ON r.package_id=s.id' + \
                ' WHERE s.name="{pkg}" AND r.status != ""'
                #' AND s.architecture="amd64"'
        query = query.format(pkg=pkg)
        result = query_db(query)
        if not result:
            log.info('Warning: This query produces no results: ' + query
                                   + '\nThis means there is no tested ' +
                                   'package with the name ' + pkg)
            try:
                irc_msg("There is problem with the note for {} (it may "
                    "have been removed from the archive). Please check {}".
                    format(pkg, os.environ['BUILD_URL']))
            except KeyError:
                log.error('There is a problem with the note for %s - please '
                          'check.', pkg)
        else:
            notes[pkg] = []
            for suite in result:
                pkg_details = {}
# https://image-store.slidesharecdn.com/c2c44a06-5e28-4296-8d87-419529750f6b-original.jpeg
                try:
                    if version_compare(str(original[pkg]['version']),
                                       str(suite[1])) > 0:
                        continue
                except KeyError:
                    pass
                pkg_details['suite'] = suite[2]
                try:
                    pkg_details['version'] = original[pkg]['version']
                except KeyError:
                    pkg_details['version'] = ''
                pkg_details['comments'] = original[pkg]['comments'] if \
                    'comments' in original[pkg] else None
                pkg_details['bugs'] = original[pkg]['bugs'] if \
                    'bugs' in original[pkg] else []
                pkg_details['issues'] = original[pkg]['issues'] if \
                    'issues' in original[pkg] else []
                pkg_details['id'] = int(suite[0])
                log.debug('adding %s => %s', pkg, pkg_details)
                notes[pkg].append(pkg_details)

    log.info("notes checked. There are " + str(len(notes)) +
             " packages listed")
    return notes


def load_issues():
    """
    format:
    { 'issue_name': {'description': 'blabla', 'url': 'blabla'} }
    """
    with open(ISSUES) as fd:
        issues = yaml.load(fd)
    log.info("Issues loaded. There are " + str(len(issues)) + " issues")
    return issues


def store_issues():
    issues_table = db_table('issues')
    # Get existing issues
    results = conn_db.execute(sql.select([issues_table.c.name]))
    existing_issues = set([row[0] for row in results])
    to_insert = []
    to_update = []
    for name in issues:
        url = issues[name]['url'] if 'url' in issues[name] else ''
        desc = issues[name]['description']
        if name in existing_issues:
            to_update.append({
                'issuename': name,
                'url': url,
                'description': desc
            })
            # remove this package from the set, to know who to delete later
            existing_issues.remove(name)
        else:
            to_insert.append({
                'name': name,
                'url': url,
                'description': desc
            })

    if to_update:
        update_query = issues_table.update().\
                  where(issues_table.c.name == sql.bindparam('issuename'))
        conn_db.execute(update_query, to_update)
        log.debug('Issues updated in the database')
    if to_insert:
        conn_db.execute(issues_table.insert(), to_insert)
        log.debug('Issues added to the database')

    # if there are any existing issues left, delete them.
    if existing_issues:
        to_delete = [{'issuename': name} for name in existing_issues]
        delete_query = issues_table.delete().\
                  where(issues_table.c.name == sql.bindparam('issuename'))
        conn_db.execute(delete_query, to_delete)
        log.info("Removed the following issues: " + str(existing_issues))


def store_notes():
    log.debug('Removing all notes')
    notes_table = db_table('notes')
    conn_db.execute(notes_table.delete())
    to_insert = []
    for entry in [x for y in sorted(notes) for x in notes[y]]:
        pkg_id = entry['id']
        pkg_version = entry['version']
        pkg_issues = json.dumps(entry['issues'])
        pkg_bugs = json.dumps(entry['bugs'])
        pkg_comments = entry['comments']
        to_insert.append({
            'package_id': pkg_id,
            'version': pkg_version,
            'issues': pkg_issues,
            'bugs': pkg_bugs,
            'comments': pkg_comments
        })

    if (len(to_insert)):
        conn_db.execute(notes_table.insert(), to_insert)
        log.info('Saved ' + str(len(to_insert)) + ' notes in the database')


if __name__ == '__main__':
    notes = load_notes()
    issues = load_issues()
    store_issues()
    store_notes()
