#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2+
#
# Depends: python3 python3-psycopg2
#
# This is included by all reproducible_*.py scripts, it contains common functions

import os
import re
import sys
import sqlite3
import logging
import argparse
import datetime
import psycopg2
from string import Template

DEBUG = False
QUIET = False

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
      Copyright 2014-2015 <a href="mailto:holger@layer-acht.org">Holger Levsen</a>,
      GPL-2 licensed. The weather icons are public domain and have been taken
      from the <a href=http://tango.freedesktop.org/Tango_Icon_Library target=_blank>
      Tango Icon Library</a>.
     </p>
  </body>
</html>""" % (JENKINS_URL))

html_head_page = Template((tab*2).join("""
<header>
  <h2>$page_title</h2>
  <p>$count_total packages have been attempted to be build so far, that's
  $percent_total% of $amount source packages in Debian sid
  currently. Out of these, $count_good packages ($percent_good%)
  <a href="https://wiki.debian.org/ReproducibleBuilds">could be built
  reproducible!</a></p>
  <ul>
    <li>Have a look at:</li>
    <li>
      <a href="/index_reproducible.html" target="_parent">
        <img src="/static/weather-clear.png" alt="reproducible icon" />
      </a>
    </li>
    <li>
      <a href="/index_FTBR.html" target="_parent">
        <img src="/static/weather-showers-scattered.png" alt="FTBR icon" />
      </a>
    </li>
    <li>
      <a href="/index_FTBFS.html" target="_parent">
        <img src="/static/weather-storm.png" alt="FTBFS icon" />
      </a>
    </li>
    <li>
      <a href="/index_404.html" target="_parent">
        <img src="/static/weather-severe-alert.png" alt="404 icon" />
      </a>
    </li>
    <li>
      <a href="/index_not_for_us.html" target="_parent">
        <img src="/static/weather-few-clouds-night.png" alt="not_for_us icon" />
      </a>
    </li>
    <li>
      <a href="/index_blacklisted.html" target="_parent">
        <img src="/static/error.png" alt="blacklisted icon" />
      </a>
    </li>
    <li><a href="/index_issues.html">issues</a></li>
    <li><a href="/index_notes.html">packages with notes</a></li>
    <li><a href="/index_scheduled.html">currently scheduled</a></li>
    <li><a href="/index_last_24h.html">packages tested in the last 24h</a></li>
    <li><a href="/index_last_48h.html">packages tested in the last 48h</a></li>
    <li><a href="/index_all_abc.html">all tested packages (sorted alphabetically)</a></li>
    <li><a href="/index_dd-list.html">maintainers of unreproducible packages</a></li>
    <li><a href="/index_stats.html">stats</a></li>
    <li><a href="/index_pkg_sets.html">package sets stats</a></li>
  </ul>
</header>""".splitlines(True)))

html_foot_page_style_note = Template((tab*2).join("""
<p style="font-size:0.9em;">
  A package name displayed with a bold font is an indication that this
  package has a note. Visited packages are linked in green, those which
  have not been visited are linked in blue.<br />
  A <code>&#35;</code> sign after the name of a package indicates that a bug is
  filed aginst it. Likewise, a <code>&#43;</code> means that there is bug with a
  patch attached. In case of more than one bug, the symbol is repeated.
</p>""".splitlines(True)))


url2html = re.compile(r'((mailto\:|((ht|f)tps?)\://|file\:///){1}\S+)')


def write_html_page(title, body, destfile, noheader=False, style_note=False, noendpage=False):
    now = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
    html = ''
    html += html_header.substitute(page_title=title)
    if not noheader:
        html += html_head_page.substitute(
            page_title=title,
            count_total=count_total,
            amount=amount,
            percent_total=percent_total,
            count_good=count_good,
            percent_good=percent_good)
    html += body
    if style_note:
        html += html_foot_page_style_note.substitute()
    if not noendpage:
        html += html_footer.substitute(date=now)
    else:
        html += '</body>\n</html>'
    os.makedirs(destfile.rsplit('/', 1)[0], exist_ok=True)
    with open(destfile, 'w') as fd:
        fd.write(html)

def start_db_connection():
    return sqlite3.connect(REPRODUCIBLE_DB)

def query_db(query):
    cursor = conn_db.cursor()
    cursor.execute(query)
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
        log.error("Erorr connecting to the UDD database replica")
        raise
    conn.set_client_encoding('utf8')
    return conn

def query_udd(query):
    cursor = conn_udd.cursor()
    cursor.execute(query)
    return cursor.fetchall()

def is_virtual_package(package):
    rows = query_udd("""SELECT source FROM sources WHERE source='%s'""" % package)
    if len(rows) > 0:
            return False
    return True

def bug_has_patch(bug):
    query = """SELECT id FROM bugs_tags WHERE id=%s AND tag='patch'""" % bug
    if len(query_udd(query)) > 0:
        return True
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
        if not package:
            log.error('Could not determinate the real state of package None. '
                      + 'Returning a generic "FTBR"')
            status = 'FTBR'
        else:
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

def pkg_has_buildinfo(package, version=False):
    """
    if there is no version specified it will use the version listed in
    reproducible.db
    """
    if not version:
        query = 'SELECT version FROM source_packages WHERE name="%s"' % package
        version = str(query_db(query)[0][0])
    buildinfo = BUILDINFO_PATH + '/' + package + '_' + \
                strip_epoch(version) + '_amd64.buildinfo'
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

    for bug in rows:
        if bug[1] not in packages:
            packages[bug[1]] = {}
        # bug[0] = bug_id, bug[1] = source_name, bug[2] = who_when_done
        if is_virtual_package(bug[1]):
            continue
        packages[bug[1]][bug[0]] = {'done': False, 'patch': False}
        if bug[2]: # if the bug is done
            packages[bug[1]][bug[0]]['done'] = True
        try:
            if bug_has_patch(bug[0]):
                packages[bug[1]][bug[0]]['patch'] = True
        except KeyError:
            log.error('item: ' + str(bug))
    return packages

# init the databases connections
conn_db = start_db_connection() # the local sqlite3 reproducible db
conn_udd = start_udd_connection()

# do the db querying
amount = int(query_db('SELECT count(name) FROM sources')[0][0])
count_total = int(query_db('SELECT COUNT(name) FROM source_packages')[0][0])
count_good = int(query_db(
 'SELECT COUNT(name) FROM source_packages WHERE status="reproducible"')[0][0])
percent_total = round(((count_total/amount)*100), 1)
percent_good = round(((count_good/count_total)*100), 1)
log.info('Total packages in Sid:\t\t' + str(amount))
log.info('Total tested packages:\t\t' + str(count_total))
log.info('Total reproducible packages:\t' + str(count_good))
log.info('That means that out of the ' + str(percent_total) + '% of ' +
             'the Sid tested packages the ' + str(percent_good) + '% are ' +
             'reproducible!')


