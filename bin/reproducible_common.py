#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Based on the reproducible_common.sh by © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3 python3-psycopg2
#
# This is included by all reproducible_*.py scripts, it contains common functions

import os
import re
import sys
import errno
import sqlite3
import logging
import argparse
import datetime
import psycopg2
from traceback import print_exception
from string import Template

DEBUG = False
QUIET = False

# tested suites
SUITES = ['sid', 'experimental']
# tested arches
ARCHES = ['amd64']

BIN_PATH = '/srv/jenkins/bin'
BASE = '/var/lib/jenkins/userContent'

REPRODUCIBLE_JSON = BASE + '/reproducible.json'
REPRODUCIBLE_DB = '/var/lib/jenkins/reproducible.db'

DBD_URI = '/dbd'
NOTES_URI = '/notes'
ISSUES_URI = '/issues'
RB_PKG_URI = '/rb-pkg'
RBUILD_URI = '/rbuild'
BUILDINFO_URI = '/buildinfo'
DBD_PATH = BASE + DBD_URI
NOTES_PATH = BASE + NOTES_URI
ISSUES_PATH = BASE + ISSUES_URI
RB_PKG_PATH = BASE + RB_PKG_URI
RBUILD_PATH = BASE + RBUILD_URI
BUILDINFO_PATH = BASE + BUILDINFO_URI

REPRODUCIBLE_URL = 'https://reproducible.debian.net'
JENKINS_URL = 'https://jenkins.debian.net'

parser = argparse.ArgumentParser()
group = parser.add_mutually_exclusive_group()
group.add_argument("-d", "--debug", action="store_true")
group.add_argument("-q", "--quiet", action="store_true")
args = parser.parse_args()
log_level = logging.INFO
if args.debug or DEBUG:
    log_level = logging.DEBUG
if args.quiet or QUIET:
    log_level = logging.ERROR
log = logging.getLogger(__name__)
log.setLevel(log_level)
sh = logging.StreamHandler()
sh.setFormatter(logging.Formatter('%(levelname)s: %(message)s'))
log.addHandler(sh)


log.debug("BIN_PATH:\t" + BIN_PATH)
log.debug("BASE:\t\t" + BASE)
log.debug("DBD_URI:\t\t" + DBD_URI)
log.debug("DBD_PATH:\t" + DBD_PATH)
log.debug("NOTES_URI:\t" + NOTES_URI)
log.debug("ISSUES_URI:\t" + ISSUES_URI)
log.debug("NOTES_PATH:\t" + NOTES_PATH)
log.debug("ISSUES_PATH:\t" + ISSUES_PATH)
log.debug("RB_PKG_URI:\t" + RB_PKG_URI)
log.debug("RB_PKG_PATH:\t" + RB_PKG_PATH)
log.debug("RBUILD_URI:\t" + RBUILD_URI)
log.debug("RBUILD_PATH:\t" + RBUILD_PATH)
log.debug("BUILDINFO_URI:\t" + BUILDINFO_URI)
log.debug("BUILDINFO_PATH:\t" + BUILDINFO_PATH)
log.debug("REPRODUCIBLE_DB:\t" + REPRODUCIBLE_DB)
log.debug("REPRODUCIBLE_JSON:\t" + REPRODUCIBLE_JSON)
log.debug("JENKINS_URL:\t\t" + JENKINS_URL)
log.debug("REPRODUCIBLE_URL:\t" + REPRODUCIBLE_URL)


tab = '  '

html_header = Template("""<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
      <link href="/static/style.css" type="text/css" rel="stylesheet" />
      <title>$page_title</title>
  </head>
  <body>""")
html_footer = Template("""
    <hr />
    <p style="font-size:0.9em;">
      There is more information <a href="%s/userContent/about.html">about
      jenkins.debian.net</a> and about
      <a href="https://wiki.debian.org/ReproducibleBuilds"> reproducible builds
      of Debian</a> available elsewhere. Last update: $date.
      Copyright 2014-2015 <a href="mailto:holger@layer-acht.org">Holger Levsen</a> and others,
      GPL-2 licensed. The weather icons are public domain and have been taken
      from the <a href=http://tango.freedesktop.org/Tango_Icon_Library target=_blank>
      Tango Icon Library</a>.
     </p>
  </body>
</html>""" % (JENKINS_URL))

html_head_page = Template((tab*2).join("""
<header>
  <h2>$page_title</h2>
  <ul>
    <li>Have a look at:</li>
    <li>
      <a href="index_reproducible.html" target="_parent">
        <img src="/static/weather-clear.png" alt="reproducible icon" />
      </a>
    </li>
    <li>
      <a href="index_FTBR.html" target="_parent">
        <img src="/static/weather-showers-scattered.png" alt="FTBR icon" />
      </a>
    </li>
    <li>
      <a href="index_FTBFS.html" target="_parent">
        <img src="/static/weather-storm.png" alt="FTBFS icon" />
      </a>
    </li>
    <li>
      <a href="index_404.html" target="_parent">
        <img src="/static/weather-severe-alert.png" alt="404 icon" />
      </a>
    </li>
    <li>
      <a href="index_not_for_us.html" target="_parent">
        <img src="/static/weather-few-clouds-night.png" alt="not_for_us icon" />
      </a>
    </li>
    <li>
      <a href="index_blacklisted.html" target="_parent">
        <img src="/static/error.png" alt="blacklisted icon" />
      </a>
    </li>
    <li><a href="/index_issues.html">issues</a></li>
    <li><a href="/index_notes.html">packages with notes</a></li>
    <li><a href="/index_no_notes.html">package without notes</a></li>
    <li><a href="index_scheduled.html">currently scheduled</a></li>
    <li><a href="index_last_24h.html">packages tested in the last 24h</a></li>
    <li><a href="index_last_48h.html">packages tested in the last 48h</a></li>
    <li><a href="index_all_abc.html">all tested packages (sorted alphabetically)</a></li>
    <li><a href="index_dd-list.html">maintainers of unreproducible packages</a></li>
$links
    <li><a href="/index_repo_stats.html">repositories overview</a></li>
    <li><a href="/reproducible.html">reproducible stats</a></li>
    <li><a href="https://wiki.debian.org/ReproducibleBuilds" target="_blank">wiki</a></li>
  </ul>
</header>""".splitlines(True)))

html_foot_page_style_note = Template((tab*2).join("""
<p style="font-size:0.9em;">
  A package name displayed with a bold font is an indication that this
  package has a note. Visited packages are linked in green, those which
  have not been visited are linked in blue.<br />
  A <code>&#35;</code> sign after the name of a package indicates that a bug is
  filed against it. Likewise, a <code>&#43;</code> means that there is bug with a
  patch attached. In case of more than one bug, the symbol is repeated.
</p>""".splitlines(True)))


url2html = re.compile(r'((mailto\:|((ht|f)tps?)\://|file\:///){1}\S+)')


def print_critical_message(msg):
    print('\n\n\n')
    try:
        for line in msg.splitlines():
            log.critical(line)
    except AttributeError:
        log.critical(msg)
    print('\n\n\n')


def _gen_links(suite, arch):
    links = ''
    if suite and suite != 'experimental':
        link += '<li><a href="/' + suite + '/' + arch + \
                '/index_pkg_sets.html">package sets stats</a></li>'
    if suite and suite == 'experimental':
        link += '<li><a href="/sid/' + arch + \
                '/index_pkg_sets.html">package sets stats</a></li>'
    if suite:
        suite_links += '<li><a href="/' + suite +'">suite: ' + suite + '</a></li>'
    for i in SUITES:
           if i != suite:
                suite_links += '<li><a href="/' + i +'">suite: ' + i + '</a></li>'
    return suite_links


def write_html_page(title, body, destfile, suite=None, noheader=False, style_note=False, noendpage=False):
    now = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
    html = ''
    html += html_header.substitute(page_title=title)
    if not noheader:
        links = _gen_links(suite, 'amd64')  # FIXME let's unhardcode amd64...
        html += html_head_page.substitute(
            page_title=title,
            links=links)
    html += body
    if style_note:
        html += html_foot_page_style_note.substitute()
    if not noendpage:
        html += html_footer.substitute(date=now)
    else:
        html += '</body>\n</html>'
    try:
        os.makedirs(destfile.rsplit('/', 1)[0], exist_ok=True)
    except OSError as e:
        if e.errno != errno.EEXIST:  # that's 'File exists' error (errno 17)
            raise
    with open(destfile, 'w') as fd:
        fd.write(html)

def start_db_connection():
    return sqlite3.connect(REPRODUCIBLE_DB)

def query_db(query):
    cursor = conn_db.cursor()
    try:
        cursor.execute(query)
    except:
        print_critical_message('Error execting this query:\n' + query)
        raise
    conn_db.commit()
    return cursor.fetchall()

def start_udd_connection():
    username = "public-udd-mirror"
    password = "public-udd-mirror"
    host = "public-udd-mirror.xvm.mit.edu"
    port = 5432
    db = "udd"
    try:
        log.debug("Starting connection to the UDD database")
        conn = psycopg2.connect("dbname=" + db +
                               " user=" + username +
                               " host=" + host +
                               " password=" + password)
    except:
        log.error('Erorr connecting to the UDD database replica.' +
                  'The full error is:')
        exc_type, exc_value, exc_traceback = sys.exc_info()
        print_exception(exc_type, exc_value, exc_traceback)
        log.error('Failing nicely anyway, all queries will return an empty ' +
                  'response.')
        return None
    conn.set_client_encoding('utf8')
    return conn

def query_udd(query):
    if not conn_udd:
        log.error('There has been an error connecting to the UDD database. ' +
                  'Please look for a previous error for more information.')
        log.error('Failing nicely anyway, returning an empty response.')
        return []
    cursor = conn_udd.cursor()
    try:
        cursor.execute(query)
    except:
        log.error('The UDD server encountered a issue while executing the ' +
                  'query. The full error is:')
        exc_type, exc_value, exc_traceback = sys.exc_info()
        print_exception(exc_type, exc_value, exc_traceback)
        log.error('Failing nicely anyway, returning an empty response.')
        return []
    return cursor.fetchall()

def is_virtual_package(package):
    rows = query_udd("""SELECT source FROM sources WHERE source='%s'""" % package)
    if len(rows) > 0:
            return False
    return True


def are_virtual_packages(packages):
    pkgs = "source='" + "' OR source='".join(packages) + "'"
    query = 'SELECT source FROM sources WHERE %s' % pkgs
    rows = query_udd(query)
    result = {x: False for x in packages if (x,) in rows}
    result.update({x: True for x in packages if (x,) not in rows})
    return result


def bug_has_patch(bug):
    query = """SELECT id FROM bugs_tags WHERE id=%s AND tag='patch'""" % bug
    if len(query_udd(query)) > 0:
        return True
    return False


def bugs_have_patches(bugs):
    '''
    This returns a list of tuples where every tuple has a bug with patch
    '''
    bugs = 'id=' + ' OR id='.join(bugs)
    query = """SELECT id FROM bugs_tags WHERE (%s) AND tag='patch'""" % bugs
    return query_udd(query)


def package_has_notes(package):
    # not a really serious check, it'd be better to check the yaml file
    path = NOTES_PATH + '/' + package + '_note.html'
    if os.access(path, os.R_OK):
        return True
    else:
        return False


def join_status_icon(status, package=None, version=None):
    table = {'reproducible' : 'weather-clear.png',
             'FTBFS': 'weather-storm.png',
             'FTBR' : 'weather-showers-scattered.png',
             '404': 'weather-severe-alert.png',
             'not for us': 'weather-few-clouds-night.png',
             'not_for_us': 'weather-few-clouds-night.png',
             'blacklisted': 'error.png'}
    if status == 'unreproducible':
            status = 'FTBR'
    log.debug('Linking status ⇔ icon. package: ' + str(package) + ' @ ' +
              str(version) + ' status: ' + status)
    try:
        return (status, table[status])
    except KeyError:
        log.error('Status of package ' + package + ' (' + status +
                  ') not recognized')
        return (status, '')

def strip_epoch(version):
    """
    Stip the epoch out of the version string. Some file (e.g. buildlogs, debs)
    do not have epoch in their filenames.
    This recognize a epoch if there is a colon in the second or third character
    of the version.
    """
    try:
        if version[1] == ':' or version[2] == ':':
            return version.split(':', 1)[1]
        else:
            return version
    except IndexError:
        return version

def pkg_has_buildinfo(package, version=False, suite='sid', arch='amd64'):
    """
    if there is no version specified it will use the version listed in
    reproducible.db
    """
    if not version:
        query = 'SELECT r.version ' + \
                'FROM results AS r JOIN sources AS s on r.package_id=s.id ' + \
                'WHERE s.name="{}" AND s.suite="{}" AND s.architecture="{}"'
        query = query.format(package, suite, arch)
        version = str(query_db(query)[0][0])
    buildinfo = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + package + \
                '_' + strip_epoch(version) + '_amd64.buildinfo'
    if os.access(buildinfo, os.R_OK):
        return True
    else:
        return False

def get_bugs():
    """
    This function returns a dict:
    { "package_name": {
        bug1: {patch: True, done: False},
        bug2: {patch: False, done: False},
       }
    }
    """
    query = """
        SELECT bugs.id, bugs.source, bugs.done
        FROM bugs JOIN bugs_tags on bugs.id = bugs_tags.id
                  JOIN bugs_usertags on bugs_tags.id = bugs_usertags.id
        WHERE bugs_usertags.email = 'reproducible-builds@lists.alioth.debian.org'
        AND bugs.id NOT IN (
            SELECT id
            FROM bugs_usertags
            WHERE email = 'reproducible-builds@lists.alioth.debian.org'
            AND (
                bugs_usertags.tag = 'toolchain'
                OR bugs_usertags.tag = 'infrastructure')
            )
    """
    # returns a list of tuples [(id, source, done)]
    rows = query_udd(query)
    log.info("finding out which usertagged bugs have been closed or at least have patches")
    packages = {}

    bugs = [str(x[0]) for x in rows]
    bugs_patches = bugs_have_patches(bugs)

    pkgs = [str(x[1]) for x in rows]
    pkgs_real = are_virtual_packages(pkgs)

    for bug in rows:
        if bug[1] not in packages:
            packages[bug[1]] = {}
        # bug[0] = bug_id, bug[1] = source_name, bug[2] = who_when_done
        if pkgs_real[str(bug[1])]:
            continue  # package is virtual, I don't care about virtual pkgs
        packages[bug[1]][bug[0]] = {'done': False, 'patch': False}
        if bug[2]: # if the bug is done
            packages[bug[1]][bug[0]]['done'] = True
        try:
            if (bug[0],) in bugs_patches:
                packages[bug[1]][bug[0]]['patch'] = True
        except KeyError:
            log.error('item: ' + str(bug))
    return packages

def get_trailing_icon(package, bugs):
    html = ''
    if package in bugs:
        for bug in bugs[package]:
            html += '<span class="'
            if bugs[package][bug]['done']:
                html += 'bug-done" title="#' + str(bug) + ', done">#</span>'
            elif bugs[package][bug]['patch']:
                html += 'bug-patch" title="#' + str(bug) + ', with patch">+</span>'
            else:
                html += '" title="#' + str(bug) + '">#</span>'
    return html


# init the databases connections
conn_db = start_db_connection() # the local sqlite3 reproducible db
conn_udd = start_udd_connection()

