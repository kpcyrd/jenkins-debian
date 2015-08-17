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
import json
import errno
import atexit
import sqlite3
import logging
import argparse
import psycopg2
import html as HTML
from string import Template
from subprocess import call
from traceback import print_exception
from datetime import datetime, timedelta

DEBUG = False
QUIET = False

# tested suites
SUITES = ['testing', 'unstable', 'experimental']
# tested architectures
ARCHS = ['amd64']
# defaults
defaultsuite = 'unstable'
defaultarch = 'amd64'

BIN_PATH = '/srv/jenkins/bin'
BASE = '/var/lib/jenkins/userContent/reproducible'

REPRODUCIBLE_JSON = BASE + '/reproducible.json'
REPRODUCIBLE_TRACKER_JSON = BASE + '/reproducible-tracker.json'
REPRODUCIBLE_DB = '/var/lib/jenkins/reproducible.db'

DBD_URI = '/dbd'
DBDTXT_URI = '/dbdtxt'
LOGS_URI = '/logs'
DIFFS_URI = '/logdiffs'
NOTES_URI = '/notes'
ISSUES_URI = '/issues'
RB_PKG_URI = '/rb-pkg'
RBUILD_URI = '/rbuild'
BUILDINFO_URI = '/buildinfo'
DBD_PATH = BASE + DBD_URI
DBDTXT_PATH = BASE + DBDTXT_URI
LOGS_PATH = BASE + LOGS_URI
DIFFS_PATH = BASE + DIFFS_URI
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
parser.add_argument("--ignore-missing-files", action="store_true",
                    help="useful for local testing, where you don't have all the build logs, etc..")
args, unknown_args = parser.parse_known_args()
log_level = logging.INFO
if args.debug or DEBUG:
    DEBUG = True
    log_level = logging.DEBUG
if args.quiet or QUIET:
    log_level = logging.ERROR
log = logging.getLogger(__name__)
log.setLevel(log_level)
sh = logging.StreamHandler()
sh.setFormatter(logging.Formatter('%(levelname)s: %(message)s'))
log.addHandler(sh)

started_at = datetime.now()
log.info('Starting at %s', started_at)

log.debug("BIN_PATH:\t" + BIN_PATH)
log.debug("BASE:\t\t" + BASE)
log.debug("DBD_URI:\t\t" + DBD_URI)
log.debug("DBD_PATH:\t" + DBD_PATH)
log.debug("DBDTXT_URI:\t" + DBDTXT_URI)
log.debug("DBDTXT_PATH:\t" + DBDTXT_PATH)
log.debug("LOGS_URI:\t" + LOGS_URI)
log.debug("LOGS_PATH:\t" + LOGS_PATH)
log.debug("DIFFS_URI:\t" + DIFFS_URI)
log.debug("DIFFS_PATH:\t" + DIFFS_PATH)
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

if args.ignore_missing_files:
    log.warning("Missing files will be ignored!")

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
      <a href="/$suite/$arch/index_reproducible.html" target="_parent">
        <img src="/static/weather-clear.png" alt="reproducible icon" />
      </a>
    </li>
    <li>
      <a href="/$suite/$arch/index_FTBR.html" target="_parent">
        <img src="/static/weather-showers-scattered.png" alt="FTBR icon" />
      </a>
    </li>
    <li>
      <a href="/$suite/$arch/index_FTBFS.html" target="_parent">
        <img src="/static/weather-storm.png" alt="FTBFS icon" />
      </a>
    </li>
    <li>
      <a href="/$suite/$arch/index_depwait.html" target="_parent">
        <img src="/static/weather-snow.png" alt="depwait icon" />
      </a>
    </li>
    <li>
      <a href="/$suite/$arch/index_not_for_us.html" target="_parent">
        <img src="/static/weather-few-clouds-night.png" alt="not_for_us icon" />
      </a>
    </li>
    <li>
      <a href="/$suite/$arch/index_404.html" target="_parent">
        <img src="/static/weather-severe-alert.png" alt="404 icon" />
      </a>
    </li>
    <li>
      <a href="/$suite/$arch/index_blacklisted.html" target="_parent">
        <img src="/static/error.png" alt="blacklisted icon" />
      </a>
    </li>
    <li><a href="/index_issues.html">issues</a></li>
    <li><a href="/$suite/$arch/index_notes.html">packages with notes</a></li>
    <li><a href="/$suite/$arch/index_no_notes.html">packages without notes</a></li>
    <li><a href="/index_scheduled.html">currently scheduled</a></li>
$links
    <li><a href="/index_repositories.html">repositories overview</a></li>
    <li><a href="/reproducible.html">reproducible stats</a></li>
    <li><a href="https://wiki.debian.org/ReproducibleBuilds" target="_blank">wiki</a></li>
  </ul>
</header>""".splitlines(True)))


html_foot_page_style_note = Template((tab*2).join("""
<p style="font-size:0.9em;">
  A package name displayed with a bold font is an indication that this
  package has a note. Visited packages are linked in green, those which
  have not been visited are linked in blue.<br />
  A <code><span class="bug">&#35;</span></code> sign after the name of a
  package indicates that a bug is filed against it. Likewise, a
  <code><span class="bug-patch">&#43;</span></code> sign indicates there is
  a patch available, a <code><span class="bug-pending">P</span></code> means a
  pending bug while <code><span class="bug-done">&#35;</span></code>
  indicates a closed bug. In cases of several bugs, the symbol is repeated.
</p>""".splitlines(True)))


url2html = re.compile(r'((mailto\:|((ht|f)tps?)\://|file\:///){1}\S+)')

# filter used on the index_FTBFS pages and for the reproducible.json
filtered_issues = (
    'bad_handling_of_extra_warnings',
    'ftbfs_wdatetime',
    'ftbfs_wdatetime_due_to_swig',
    'ftbfs_pbuilder_malformed_dsc',
    'ftbfs_in_jenkins_setup',
    'ftbfs_build_depends_not_available_on_amd64',
    'ftbfs_due_to_root_username',
    'ftbfs_due_to_virtual_dependencies')
filter_query = ''
for issue in filtered_issues:
    if filter_query == '':
        filter_query = 'n.issues LIKE "%' + issue + '%"'
        filter_html = '<a href="' + REPRODUCIBLE_URL + ISSUES_URI + '/$suite/' + issue + '_issue.html">' + issue + '</a>'
    else:
        filter_query += ' OR n.issues LIKE "%' + issue + '%"'
        filter_html += ' or <a href="' + REPRODUCIBLE_URL + ISSUES_URI + '/$suite/' + issue + '_issue.html">' + issue + '</a>'


@atexit.register
def print_time():
    log.info('Finished at %s, took: %s', datetime.now(),
             datetime.now()-started_at)


def print_critical_message(msg):
    print('\n\n\n')
    try:
        for line in msg.splitlines():
            log.critical(line)
    except AttributeError:
        log.critical(msg)
    print('\n\n\n')


class bcolors:
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    RED = '\033[91m'
    GOOD = '\033[92m'
    WARN = '\033[93m' + UNDERLINE
    FAIL = RED + BOLD + UNDERLINE
    ENDC = '\033[0m'


def _gen_links(suite, arch):
    links = [
        ('last_24h', '<li><a href="/{suite}/{arch}/index_last_24h.html">packages tested in the last 24h</a></li>'),
        ('last_48h', '<li><a href="/{suite}/{arch}/index_last_48h.html">packages tested in the last 48h</a></li>'),
        ('all_abc', '<li><a href="/{suite}/{arch}/index_all_abc.html">all tested packages (sorted alphabetically)</a></li>'),
        ('notify', '<li><a href="/index_notify.html" title="notify icon">⚑</a></li>'),
        ('dd-list', '<li><a href="/{suite}/index_dd-list.html">maintainers of unreproducible packages</a></li>'),
        ('pkg_sets', '<li><a href="/{suite}/{arch}/index_pkg_sets.html">package sets stats</a></li>')
    ]
    html = ''
    for link in links:
        if link[0] == 'pkg_sets' and suite == 'experimental':
            html += link[1].format(suite=defaultsuite, arch=arch) + '\n'
            continue
        html += link[1].format(suite=suite, arch=arch) + '\n'
    for i in SUITES:  # suite links
            html += '<li><a href="/' + i +'">suite: ' + i + '</a></li>'
    return html


def write_html_page(title, body, destfile, suite=defaultsuite, arch=defaultarch, noheader=False, style_note=False, noendpage=False):
    now = datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
    html = ''
    html += html_header.substitute(page_title=title)
    if not noheader:
        links = _gen_links(suite, arch)
        html += html_head_page.substitute(
            page_title=title,
            suite=suite,
            arch=arch,
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
    with open(destfile, 'w', encoding='UTF-8') as fd:
        fd.write(html)

def start_db_connection():
    return sqlite3.connect(REPRODUCIBLE_DB, timeout=60)

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
        conn = psycopg2.connect(
            database=db,
            user=username,
            host=host,
            password=password,
            connect_timeout=5,
        )
    except psycopg2.OperationalError as err:
        if str(err) == 'timeout expired\n':
            log.error('Connection to the UDD database replice timed out. '
                      'Probably the machine is offline or just unavailable.')
            log.error('Failing nicely anyway, all queries will return an '
                      'empty response.')
            return None
        else:
            raise
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


def package_has_notes(package):
    # not a really serious check, it'd be better to check the yaml file
    path = NOTES_PATH + '/' + package + '_note.html'
    if os.access(path, os.R_OK):
        return True
    else:
        return False


def link_package(package, suite, arch, bugs={}):
    url = RB_PKG_URI + '/' + suite + '/' + arch + '/' + package + '.html'
    query = 'SELECT n.issues, n.bugs, n.comments ' + \
            'FROM notes AS n JOIN sources AS s ON s.id=n.package_id ' + \
            'WHERE s.name="{pkg}" AND s.suite="{suite}" ' + \
            'AND s.architecture="{arch}"'
    try:
        notes = query_db(query.format(pkg=package, suite=suite, arch=arch))[0]
    except IndexError:  # no notes for this package
        html = '<a href="' + url + '" class="package">' + package  + '</a>'
    else:
        title = ''
        for issue in json.loads(notes[0]):
            title += issue + '\n'
        for bug in json.loads(notes[1]):
            title += '#' + str(bug) + '\n'
        if notes[2]:
            title += notes[2]
        title = HTML.escape(title.strip())
        html = '<a href="' + url + '" class="noted" title="' + title + \
               '">' + package + '</a>'
    finally:
        html += get_trailing_icon(package, bugs) + '\n'
    return html


def link_packages(packages, suite, arch):
    bugs = get_bugs()
    html = ''
    for pkg in packages:
        html += link_package(pkg, suite, arch, bugs)
    return html


def join_status_icon(status, package=None, version=None):
    table = {'reproducible' : 'weather-clear.png',
             'FTBFS': 'weather-storm.png',
             'FTBR' : 'weather-showers-scattered.png',
             '404': 'weather-severe-alert.png',
             'depwait': 'weather-snow.png',
             'not for us': 'weather-few-clouds-night.png',
             'not_for_us': 'weather-few-clouds-night.png',
             'untested': 'weather-clear-night.png',
             'blacklisted': 'error.png'}
    if status == 'unreproducible':
            status = 'FTBR'
    elif status == 'not for us':
            status = 'not_for_us'
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
    """
    try:
        return version.split(':', 1)[1]
    except IndexError:
        return version

def pkg_has_buildinfo(package, version=False, suite=defaultsuite, arch=defaultarch):
    """
    if there is no version specified it will use the version listed in
    reproducible.db
    """
    if not version:
        query = 'SELECT r.version ' + \
                'FROM results AS r JOIN sources AS s ON r.package_id=s.id ' + \
                'WHERE s.name="{}" AND s.suite="{}" AND s.architecture="{}"'
        query = query.format(package, suite, arch)
        version = str(query_db(query)[0][0])
    buildinfo = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + package + \
                '_' + strip_epoch(version) + '_amd64.buildinfo'
    if os.access(buildinfo, os.R_OK):
        return True
    else:
        return False


def pkg_has_rbuild(package, version=False, suite=defaultsuite, arch=defaultarch):
    if not version:
        query = 'SELECT r.version ' + \
                'FROM results AS r JOIN sources AS s ON r.package_id=s.id ' + \
                'WHERE s.name="{}" AND s.suite="{}" AND s.architecture="{}"'
        query = query.format(package, suite, arch)
        version = str(query_db(query)[0][0])
    rbuild = RBUILD_PATH + '/' + suite + '/' + arch + '/' + package + '_' + \
             strip_epoch(version) + '.rbuild.log'
    if os.access(rbuild, os.R_OK):
        return (rbuild, os.stat(rbuild).st_size)
    elif os.access(rbuild+'.gz', os.R_OK):
        return (rbuild+'.gz', os.stat(rbuild+'.gz').st_size)
    else:
        return ()


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
        SELECT bugs.id, bugs.source, bugs.done, ARRAY_AGG(tags.tag)
        FROM bugs JOIN bugs_tags ON bugs.id = bugs_tags.id
                  JOIN bugs_usertags ON bugs_tags.id = bugs_usertags.id
                  JOIN sources ON bugs.source=sources.source
                  LEFT JOIN (
                    SELECT id, tag FROM bugs_tags
                    WHERE tag='patch' OR tag='pending'
                  ) AS tags ON bugs.id = tags.id
        WHERE bugs_usertags.email = 'reproducible-builds@lists.alioth.debian.org'
        AND bugs.id NOT IN (
            SELECT id
            FROM bugs_usertags
            WHERE email = 'reproducible-builds@lists.alioth.debian.org'
            AND (
                bugs_usertags.tag = 'toolchain'
                OR bugs_usertags.tag = 'infrastructure')
            )
        GROUP BY bugs.id, bugs.source, bugs.done
    """
    # returns a list of tuples [(id, source, done)]
    global conn_udd
    if not conn_udd:
        conn_udd = start_udd_connection()
    global bugs
    if bugs:
        return bugs
    rows = query_udd(query)
    log.info("finding out which usertagged bugs have been closed or at least have patches")
    packages = {}

    for bug in rows:
        if bug[1] not in packages:
            packages[bug[1]] = {}
        # bug[0] = bug_id, bug[1] = source_name, bug[2] = who_when_done,
        # bug[3] = tag (patch or pending)
        packages[bug[1]][bug[0]] = {
            'done': False, 'patch': False, 'pending': False
        }
        if bug[2]:  # if the bug is done
            packages[bug[1]][bug[0]]['done'] = True
        if 'patch' in bug[3]:  # the bug is patched
            packages[bug[1]][bug[0]]['patch'] = True
        if 'pending' in bug[3]:  # the bug is pending
            packages[bug[1]][bug[0]]['pending'] = True
    return packages


def get_trailing_icon(package, bugs):
    html = ''
    if package in bugs:
        for bug in bugs[package]:
            html += '<span class="'
            if bugs[package][bug]['done']:
                html += 'bug-done" title="#' + str(bug) + ', done">#</span>'
            elif bugs[package][bug]['pending']:
                html += 'bug-pending" title="#' + str(bug) + ', pending">P</span>'
            elif bugs[package][bug]['patch']:
                html += 'bug-patch" title="#' + str(bug) + ', with patch">+</span>'
            else:
                html += 'bug" title="#' + str(bug) + '">#</span>'
    return html


def get_trailing_bug_icon(bug, bugs, package=None):
    html = ''
    if not package:
        for pkg in bugs.keys():
            if get_trailing_bug_icon(bug, bugs, pkg):
                return get_trailing_bug_icon(bug, bugs, pkg)
    else:
        try:
            if bug in bugs[package].keys():
                html += '<span class="'
                if bugs[package][bug]['done']:
                    html += 'bug-done" title="#' + str(bug) + ', done">#'
                elif bugs[package][bug]['pending']:
                    html += 'bug-pending" title="#' + str(bug) + ', pending">P'
                elif bugs[package][bug]['patch']:
                    html += 'bug-patch" title="#' + str(bug) + ', with patch">+'
                else:
                    html += 'bug">'
                html += '</span>'
        except KeyError:
            pass
    return html


def irc_msg(msg):
    kgb = ['kgb-client', '--conf', '/srv/jenkins/kgb/debian-reproducible.conf',
           '--relay-msg']
    kgb.extend(str(msg).strip().split())
    call(kgb)


class Bug:
    def __init__(self, bug):
        self.bug = bug

    def __str__(self):
        return str(self.bug)


class Issue:
    def __init__(self, name):
        self.name = name
        query = 'SELECT url, description  FROM issues WHERE name="{}"'
        result = query_db(query.format(self.name))
        try:
            self.url = result[0][0]
        except IndexError:
            self.url = ''
        try:
            self.desc = result[0][0]
        except IndexError:
            self.desc = ''


class Note:
    def __init__(self, pkg, results):
        log.debug(str(results))
        self.issues = [Issue(x) for x in json.loads(results[0])]
        self.bugs = [Bug(x) for x in json.loads(results[1])]
        self.comment = results[2]


class NotedPkg:
    def __init__(self, package, suite, arch):
        self.package = package
        self.suite = suite
        self.arch = arch
        query = 'SELECT n.issues, n.bugs, n.comments ' + \
                'FROM sources AS s JOIN notes AS n ON s.id=n.package_id ' + \
                'WHERE s.name="{}" AND s.suite="{}" AND s.architecture="{}"'
        result = query_db(query.format(self.package, self.suite, self.arch))
        try:
            result = result[0]
        except IndexError:
            self.note = None
        else:
            self.note = Note(self, result)

class Build:
    def __init__(self, package, suite, arch):
        self.package = package
        self.suite = suite
        self.arch = arch
        self.status = False
        self.version = False
        self.build_date = False
        self._get_package_status()

    def _get_package_status(self):
        try:
            query = 'SELECT r.status, r.version, r.build_date ' + \
                    'FROM results AS r JOIN sources AS s ' + \
                    'ON r.package_id=s.id WHERE s.name="{}" ' + \
                    'AND s.architecture="{}" AND s.suite="{}"'
            query = query.format(self.package, self.arch, self.suite)
            result = query_db(query)[0]
        except IndexError:  # not tested, look whether it actually exists
            query = 'SELECT version FROM sources WHERE name="{}" ' + \
                    'AND suite="{}" AND architecture="{}"'
            query = query.format(self.package, self.suite, self.arch)
            try:
                result = query_db(query)[0][0]
                if result:
                    result = ('untested', str(result), False)
            except IndexError:  # there is no package with this name in this
                return          # suite/arch, or none at all
        self.status = str(result[0])
        self.version = str(result[1])
        # this is currently used only on rb-pkg pages, no need to have
        if result[2]:                       # parsable timestamps and the like
            self.build_date = 'at ' + str(result[2]) + ' UTC'
        else:
            self.build_date = \
                '<span style="color:red;font-weight:bold;">UNTESTED</span>'


class Package:
    def __init__(self, name, no_notes=False):
        self.name = name
        self._status = {}
        for suite in SUITES:
            self._status[suite] = {}
            for arch in ARCHS:
                self._status[suite][arch] = Build(self.name, suite, arch)
                if not no_notes:
                    self.note = NotedPkg(self.name, suite, arch).note
                else:
                    self.note = False
        try:
            self.status = self._status[defaultsuite][defaultarch].status
        except KeyError:
            self.status = False
        query = 'SELECT notify_maintainer FROM sources WHERE name="{}"'
        try:
            result = int(query_db(query.format(self.name))[0][0])
        except IndexError:
            result = 0
        self.notify_maint = '⚑' if result == 1 else ''

    def get_status(self, suite, arch):
        """ This returns False if the package does not exists in this suite """
        try:
            return self._status[suite][arch].status
        except KeyError:
            return False

    def get_build_date(self, suite, arch):
        """ This returns False if the package does not exists in this suite """
        try:
            return self._status[suite][arch].build_date
        except KeyError:
            return False

    def get_tested_version(self, suite, arch):
        """ This returns False if the package does not exists in this suite """
        try:
            return self._status[suite][arch].version
        except KeyError:
            return False


# init the databases connections
conn_db = start_db_connection()  # the local sqlite3 reproducible db
# get_bugs() is the only user of this, let it initialize the connection itself,
# during it's first call to speed up things when unneeded
# also "share" the bugs, to avoid collecting them multiple times per run
conn_udd = None
bugs = None
