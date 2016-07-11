#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015-2016 Holger Levsen <holger@layer-acht.org>
# Based on the reproducible_common.sh by © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3 python3-psycopg2
#
# This is included by all reproducible_*.py scripts, it contains common functions

import os
import re
import sys
import csv
import json
import errno
import atexit
import sqlite3
import logging
import argparse
import pystache
import psycopg2
import html as HTML
from string import Template
from traceback import print_exception
from subprocess import call, check_call
from tempfile import NamedTemporaryFile
from datetime import datetime, timedelta


DEBUG = False
QUIET = False

# don't try to run on test system
if os.uname()[1] == 'jenkins-test-vm':
    sys.exit()

# tested suites
SUITES = ['testing', 'unstable', 'experimental']
# tested architectures
ARCHS = ['amd64', 'i386', 'armhf']
# defaults
defaultsuite = 'unstable'
defaultarch = 'amd64'

BIN_PATH = '/srv/jenkins/bin'
BASE = '/var/lib/jenkins/userContent/reproducible'
DEBIAN_BASE = '/var/lib/jenkins/userContent/reproducible/debian'
TEMPLATE_PATH = BIN_PATH + '/templates'
PKGSET_DEF_PATH = '/srv/reproducible-results'
TEMP_PATH="/tmp/reproducible"

REPRODUCIBLE_JSON = BASE + '/reproducible.json'
REPRODUCIBLE_TRACKER_JSON = BASE + '/reproducible-tracker.json'
REPRODUCIBLE_DB = '/var/lib/jenkins/reproducible.db'

DBD_URI = '/debian/dbd'
DBDTXT_URI = '/debian/dbdtxt'
LOGS_URI = '/debian/logs'
DIFFS_URI = '/debian/logdiffs'
NOTES_URI = '/debian/notes'
ISSUES_URI = '/debian/issues'
RB_PKG_URI = '/debian/rb-pkg'
RBUILD_URI = '/debian/rbuild'
HISTORY_URI = '/debian/history'
BUILDINFO_URI = '/debian/buildinfo'
DBD_PATH = BASE + DBD_URI
DBDTXT_PATH = BASE + DBDTXT_URI
LOGS_PATH = BASE + LOGS_URI
DIFFS_PATH = BASE + DIFFS_URI
NOTES_PATH = BASE + NOTES_URI
ISSUES_PATH = BASE + ISSUES_URI
RB_PKG_PATH = BASE + RB_PKG_URI
RBUILD_PATH = BASE + RBUILD_URI
HISTORY_PATH = BASE + HISTORY_URI
BUILDINFO_PATH = BASE + BUILDINFO_URI

REPRODUCIBLE_URL = 'https://tests.reproducible-builds.org'
DEBIAN_URL = 'https://tests.reproducible-builds.org/debian'
JENKINS_URL = 'https://jenkins.debian.net'

# global package set definitions
# for unknown historical reasons the meta_pkgset list is 1-indexed
META_PKGSET = {}
with open(os.path.join(BIN_PATH, './meta_pkgset.csv'), newline='') as f:
    for line in csv.reader(f):
        META_PKGSET[int(line[0])] = line[1]

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
log.debug("HISTORY_URI:\t" + HISTORY_URI)
log.debug("HISTORY_PATH:\t" + HISTORY_PATH)
log.debug("BUILDINFO_URI:\t" + BUILDINFO_URI)
log.debug("BUILDINFO_PATH:\t" + BUILDINFO_PATH)
log.debug("REPRODUCIBLE_DB:\t" + REPRODUCIBLE_DB)
log.debug("REPRODUCIBLE_JSON:\t" + REPRODUCIBLE_JSON)
log.debug("JENKINS_URL:\t\t" + JENKINS_URL)
log.debug("REPRODUCIBLE_URL:\t" + REPRODUCIBLE_URL)
log.debug("DEBIAN_URL:\t" + DEBIAN_URL)

if args.ignore_missing_files:
    log.warning("Missing files will be ignored!")

tab = '  '

# Templates used for creating package pages
renderer = pystache.Renderer()
status_icon_link_template = renderer.load_template(
    TEMPLATE_PATH + '/status_icon_link')
default_page_footer_template = renderer.load_template(
    TEMPLATE_PATH + '/default_page_footer')
pkg_legend_template = renderer.load_template(
    TEMPLATE_PATH + '/pkg_symbol_legend')
project_links_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'project_links'))
main_navigation_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'main_navigation'))
basic_page_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'basic_page'))

html_header = Template("""<!DOCTYPE html>
<html>
  <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
      <meta name="viewport" content="width=device-width" />
      $meta_refresh
      <link href="/static/style.css" type="text/css" rel="stylesheet" />
      <title>$page_title</title>
  </head>
  <body class="wrapper">""")

try:
    JOB_URL = os.environ['JOB_URL']
except KeyError:
    JOB_URL = ''
    JOB_NAME = ''
else:
    JOB_NAME = os.path.basename(JOB_URL[:-1])

def create_default_page_footer(date):
    return renderer.render(default_page_footer_template, {
            'date': date,
            'job_url': JOB_URL,
            'job_name': JOB_NAME,
            'jenkins_url': JENKINS_URL,
        })

url2html = re.compile(r'((mailto\:|((ht|f)tps?)\://|file\:///){1}\S+)')

# filter used on the index_FTBFS pages and for the reproducible.json
filtered_issues = (
    'ftbfs_in_jenkins_setup',
    'ftbfs_build_depends_not_available_on_amd64',
    'ftbfs_build-indep_not_build_on_some_archs'
)
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


def percent(part, whole):
    return round(100 * float(part)/float(whole), 1)


def create_temp_file(mode='w+b'):
    os.makedirs(TEMP_PATH, exist_ok=True)
    return NamedTemporaryFile(suffix=JOB_NAME, dir=TEMP_PATH, mode=mode)


class bcolors:
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    RED = '\033[91m'
    GOOD = '\033[92m'
    WARN = '\033[93m' + UNDERLINE
    FAIL = RED + BOLD + UNDERLINE
    ENDC = '\033[0m'


def convert_into_hms_string(duration):
    if not duration:
        duration = ''
    else:
        duration = int(duration)
        hours = int(duration/3600)
        minutes = int((duration-(hours*3600))/60)
        seconds = int(duration-(hours*3600)-(minutes*60))
        duration = ''
        if hours > 0:
            duration = str(hours)+'h ' + str(minutes)+'m ' + str(seconds) + 's'
        elif minutes > 0:
            duration = str(minutes)+'m ' + str(seconds) + 's'
        else:
            duration = str(seconds)+'s'
    return duration


# See bash equivelent: reproducible_common.sh's "write_page_header()"
def create_main_navigation(page_title, suite, arch, displayed_page=None):
    context = {
        'page_title': page_title,
        'suite': suite,
        'arch': arch,
        'project_links_html': renderer.render(project_links_template),
        'suite_list': [{'s': s} for s in SUITES],
        'arch_list': [{'a': a} for a in ARCHS],
        'debian_url': DEBIAN_URL,
    }
    if suite != 'experimental':
        # there are not package sets in experimental
        context['include_pkgset_link'] = True
    # this argument controls which of the main page navigation items will be
    # highlighted.
    if displayed_page:
       context[displayed_page] = True
    return renderer.render(main_navigation_template, context)


def write_html_page(title, body, destfile, suite=defaultsuite, arch=defaultarch,
                    noheader=False, style_note=False, noendpage=False,
                    packages=False, refresh_every=None, displayed_page=None):
    meta_refresh = '<meta http-equiv="refresh" content="%d">' % \
        refresh_every if refresh_every is not None else ''
    context = {
        'page_title': title,
        'meta_refresh': meta_refresh,
    }
    if not noheader:
        context['main_navigation_html'] = create_main_navigation(
            page_title=title,
            suite=suite,
            arch=arch,
            displayed_page=displayed_page,
        )
    main_html = body
    if style_note:
        main_html += renderer.render(pkg_legend_template, {})
    if not noendpage:
        now = datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
        main_html += create_default_page_footer(now)
    context['main_html'] = main_html
    html = renderer.render(basic_page_template, context)

    try:
        os.makedirs(destfile.rsplit('/', 1)[0], exist_ok=True)
    except OSError as e:
        if e.errno != errno.EEXIST:  # that's 'File exists' error (errno 17)
            raise
    log.debug("Writing " + destfile)
    with open(destfile, 'w', encoding='UTF-8') as fd:
        fd.write(html)

def start_db_connection():
    return sqlite3.connect(REPRODUCIBLE_DB, timeout=60)

def query_db(query):
    cursor = conn_db.cursor()
    try:
        cursor.execute(query)
    except:
        print_critical_message('Error executing this query:\n' + query)
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
                          'Maybe the machine is offline or just unavailable.')
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
    try:
        cursor = conn_udd.cursor()
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


def link_package(package, suite, arch, bugs={}, popcon=None, is_popular=None):
    url = RB_PKG_URI + '/' + suite + '/' + arch + '/' + package + '.html'
    query = 'SELECT n.issues, n.bugs, n.comments ' + \
            'FROM notes AS n JOIN sources AS s ON s.id=n.package_id ' + \
            'WHERE s.name="{pkg}" AND s.suite="{suite}" ' + \
            'AND s.architecture="{arch}"'
    css_classes = []
    if is_popular:
        css_classes += ["package-popular"]
    title = ''
    if popcon is not None:
        title += 'popcon score: ' + str(popcon) + '\n'
    try:
        notes = query_db(query.format(pkg=package, suite=suite, arch=arch))[0]
    except IndexError:  # no notes for this package
        css_classes += ["package"]
    else:
        css_classes += ["noted"]
        for issue in json.loads(notes[0]):
            title += issue + '\n'
        for bug in json.loads(notes[1]):
            title += '#' + str(bug) + '\n'
        if notes[2]:
            title += notes[2]
    html = '<a href="' + url + '" class="' + ' '.join(css_classes) \
         + '" title="' + HTML.escape(title.strip()) + '">' + package + '</a>' \
         + get_trailing_icon(package, bugs) + '\n'
    return html


def link_packages(packages, suite, arch, bugs=None):
    if bugs is None:
        bugs = get_bugs()
    html = ''
    for pkg in packages:
        html += link_package(pkg, suite, arch, bugs)
    return html


def get_status_icon(status):
    table = {'reproducible' : 'weather-clear.png',
             'FTBFS': 'weather-storm.png',
             'FTBR' : 'weather-showers-scattered.png',
             '404': 'weather-severe-alert.png',
             'depwait': 'weather-snow.png',
             'not for us': 'weather-few-clouds-night.png',
             'not_for_us': 'weather-few-clouds-night.png',
             'untested': 'weather-clear-night.png',
             'blacklisted': 'error.png'}
    spokenstatus = status
    if status == 'unreproducible':
            status = 'FTBR'
    elif status == 'not for us':
            status = 'not_for_us'
    try:
        return (status, table[status], spokenstatus)
    except KeyError:
        log.error('Status ' + status + ' not recognized')
        return (status, '', spokenstatus)


def gen_status_link_icon(status, spokenstatus, icon, suite, arch):
    """
    Returns the html for "<icon> <spokenstatus>" with both icon and status
    linked to the appropriate index page for the status, arch and suite.

    If icon is set to None, the icon will be ommited.
    If spokenstatus is set to None, the spokenstatus link be ommited.
    """
    context = {
        'status': status,
        'spokenstatus': spokenstatus,
        'icon': icon,
        'suite': suite,
        'arch': arch,
        'untested': True if status == 'untested' else False,
    }
    return renderer.render(status_icon_link_template, context)


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
                '_' + strip_epoch(version) + '_' + arch + '.buildinfo'
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
        bug1: {patch: True, done: False, title: "string"},
        bug2: {patch: False, done: False, title: "string"},
       }
    }
    """
    query = """
        SELECT bugs.id, bugs.source, bugs.done, ARRAY_AGG(tags.tag), bugs.title
        FROM bugs JOIN bugs_usertags ON bugs.id = bugs_usertags.id
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
        # bug[3] = tag (patch or pending), bug[4] = title
        packages[bug[1]][bug[0]] = {
            'done': False, 'patch': False, 'pending': False, 'title': bug[4]
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
            html += '<a href="https://bugs.debian.org/{bug}">'.format(bug=bug)
            html += '<span class="'
            if bugs[package][bug]['done']:
                html += 'bug-done" title="#' + str(bug) + ', done">#</span>'
            elif bugs[package][bug]['pending']:
                html += 'bug-pending" title="#' + str(bug) + ', pending">P</span>'
            elif bugs[package][bug]['patch']:
                html += 'bug-patch" title="#' + str(bug) + ', with patch">+</span>'
            else:
                html += 'bug" title="#' + str(bug) + '">#</span>'
            html += '</a>'
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
        if result[2]:
            self.build_date = str(result[2]) + ' UTC'


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
        self.history = []
        self._load_history()

    def _load_history(self):
        keys = ['build ID', 'version', 'suite', 'architecture', 'result',
            'build date', 'build duration', 'node1', 'node2', 'job',
            'schedule message']
        query = """
                SELECT id, version, suite, architecture, status, build_date,
                    build_duration, node1, node2, job, schedule_message
                FROM stats_build WHERE name='{}' ORDER BY build_date DESC
            """.format(self.name)
        results = query_db(query)
        for record in results:
            self.history.append(dict(zip(keys, record)))

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
