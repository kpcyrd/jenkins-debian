#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3 python-apt python3-yaml
#
# Import the content of the notes.git repository into the reproducible database

import apt
import json
import yaml
from apt_pkg import version_compare
from reproducible_common import *
import os

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
    for pkg in original:
        assert isinstance(pkg, str)
        try:
            assert 'version' in original[pkg]
        except AssertionError:
            print_critical_message(pkg + ' did not include a version')
            raise
        query = 'SELECT s.id, s.version, s.suite ' + \
                'FROM results AS r JOIN sources AS s ON r.package_id=s.id' + \
                ' WHERE s.name="{pkg}" AND r.status != ""'
        query = query.format(pkg=pkg)
        result = query_db(query)
        if not result:
            print_critical_message('Warning: This query produces no results: ' + query
                                   + '\nThis means there is no tested ' +
                                   'package with the name ' + pkg)
            irc_msg('There is problem with the note for ' + pkg +
                    ' - please have a look at ' + os.environ['BUILD_URL'])
        else:
            notes[pkg] = []
            for suite in result:
                pkg_details = {}
# https://image-store.slidesharecdn.com/c2c44a06-5e28-4296-8d87-419529750f6b-original.jpeg
                if version_compare(str(original[pkg]['version']),
                                   str(suite[1])) > 0:
                    continue
                pkg_details['suite'] = suite[2]
                pkg_details['version'] = original[pkg]['version']
                pkg_details['comments'] = original[pkg]['comments'] if \
                    'comments' in original[pkg] else None
                pkg_details['bugs'] = original[pkg]['bugs'] if \
                    'bugs' in original[pkg] else []
                pkg_details['issues'] = original[pkg]['issues'] if \
                    'issues' in original[pkg] else []
                pkg_details['id'] = int(suite[0])
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
    query = 'REPLACE INTO issues (name, url, description) ' + \
            'VALUES (?, ?, ?)'
    cursor = conn_db.cursor()
    to_add = []
    for issue in sorted(issues):
        name = issue
        url = issues[name]['url'] if 'url' in issues[name] else ''
        desc = issues[name]['description']
        to_add.append((name, url, desc))
    cursor.executemany(query, to_add)
    conn_db.commit()
    log.debug('Issues saved in the database')


def drop_old_issues():
    old = [x[0] for x in query_db('SELECT name FROM issues')]
    to_drop = [x for x in old if x not in issues]
    if to_drop:
        log.info("I'm about to remove the following issues: " + str(to_drop))
    for issue in to_drop:
        query_db('DELETE FROM issues WHERE name="{}"'.format(issue))


def store_notes():
    log.debug('Removing all notes')
    query_db('DELETE FROM notes')
    query = 'REPLACE INTO notes ' + \
            '(package_id, version, issues, bugs, comments) ' + \
            'VALUES (?, ?, ?, ?, ?)'
    to_add = []
    for entry in [x for y in sorted(notes) for x in notes[y]]:
        pkg_id = entry['id']
        pkg_version = entry['version']
        pkg_issues = json.dumps(entry['issues'])
        pkg_bugs = json.dumps(entry['bugs'])
        pkg_comments = entry['comments']
        pkg = (pkg_id, pkg_version, pkg_issues, pkg_bugs, pkg_comments)
        to_add.append(pkg)
    cursor = conn_db.cursor()
    cursor.executemany(query, to_add)
    conn_db.commit()
    log.info('Saved ' + str(len(to_add)) + ' notes in the database')


if __name__ == '__main__':
    notes = load_notes()
    issues = load_issues()
    store_issues()
    drop_old_issues()
    store_notes()
