#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# A secure script to be called from remote hosts

import sys
import time
import argparse


parser = argparse.ArgumentParser(
    description='Reschedule packages to re-test their reproducibility',
    epilog='The build results will be announced on the #debian-reproducible'
           ' IRC channel if -n is provided. Specifying two or more filters'
           ' (namely two or more -r/-i/-t/-b) means "all packages with that'
           ' issue AND that status AND that date". Blacklisted package '
           "can't be selected by a filter, but needs to be explitely listed"
           ' in the package list.')
parser.add_argument('--dry-run', action='store_true')
parser.add_argument('--null', action='store_true', help='The arguments are '
                    'considered null-separated and coming from stding')
parser.add_argument('-k', '--keep-artifacts',  action='store_true',
                   help='Save artifacts (for further offline study)')
parser.add_argument('-n', '--notify', action='store_true',
                   help='Notify the channel when the build finishes')
parser.add_argument('--noisy', action='store_true', help='Also notify when ' +
                    'the build starts, linking to the build url.')
parser.add_argument('-m', '--message', default='',
                    help='A text to be sent to the IRC channel when notifying' +
                    ' about the scheduling')
parser.add_argument('-r', '--status', required=False,
                    help='Schedule all package with this status')
parser.add_argument('-i', '--issue', required=False,
                    help='Schedule all packages with this issue')
parser.add_argument('-t', '--after', required=False,
                    help='Schedule all packages built after this date')
parser.add_argument('-b', '--before', required=False,
                    help='Schedule all packages built before this date')
parser.add_argument('-a', '--architecture', required=False, default='amd64',
                    help='Specify the architecture to schedule for ' +
                    '(defaults to amd64)')
parser.add_argument('-s', '--suite', required=False,
                    help='Specify the suite to schedule in')
parser.add_argument('packages', metavar='package', nargs='*',
                    help='list of packages to reschedule')
scheduling_args = parser.parse_known_args()[0]
if scheduling_args.null:
    scheduling_args = parser.parse_known_args(sys.stdin.read().split('\0'))

# these are here as an hack to be able to parse the command line
from reproducible_common import *
from reproducible_html_indexes import generate_schedule

# this variable is expected to come from the remote host
try:
    requester = os.environ['LC_USER']
except KeyError:
    log.critical(bcolors.FAIL + 'You should use the provided script to '
                 'schedule packages. Ask in #debian-reproducible if you have '
                 'trouble with that.' + bcolors.ENDC)
    sys.exit(1)
# this variable is setted by reproducible scripts, and it's clearly available
# only on calls made by the local host
try:
    local = True if os.environ['LOCAL_CALL'] == 'true' else False
except KeyError:
    local = False

suite = scheduling_args.suite
arch = scheduling_args.architecture
reason = scheduling_args.message
issue = scheduling_args.issue
status = scheduling_args.status
built_after = scheduling_args.after
built_before = scheduling_args.before
packages = scheduling_args.packages
artifacts = scheduling_args.keep_artifacts
notify = scheduling_args.notify or scheduling_args.noisy
debug_url = scheduling_args.noisy
dry_run = scheduling_args.dry_run

log.debug('Requester: ' + requester)
log.debug('Dry run: ' + str(dry_run))
log.debug('Local call: ' + str(local))
log.debug('Reason: ' + reason)
log.debug('Artifacts: ' + str(artifacts))
log.debug('Notify: ' + str(notify))
log.debug('Debug url: ' + str(debug_url))
log.debug('Architecture: ' + defaultarch)
log.debug('Issue: ' + issue if issue else str(None))
log.debug('Status: ' + status if status else str(None))
log.debug('Date: after ' + built_after if built_after else str(None) +
          ' before ' + built_before if built_before else str(None))
log.debug('Suite: ' + suite)
log.debug('Architecture: ' + arch)
log.debug('Packages: ' + ' '.join(packages))

if not suite:
    log.critical('You need to specify the suite name')
    sys.exit(1)

if suite not in SUITES:
    log.critical('The specified suite is not being tested.')
    log.critical('Please choose between ' + ', '.join(SUITES))
    sys.exit(1)

if arch not in ARCHS:
    log.critical('The specified architecture is not being tested.')
    log.critical('Please choose between ' + ', '.join(ARCHS))
    sys.exit(1)

if issue or status or built_after or built_before:
    formatter = dict(suite=suite, notes_table='')
    log.info('Querying packages with given issues/status...')
    query = 'SELECT s.name ' + \
            'FROM sources AS s, {notes_table} results AS r ' + \
            'WHERE r.package_id=s.id ' + \
            'AND s.suite = "{suite}" AND r.status != "blacklisted" '
    if issue:
        query += 'AND n.package_id=s.id AND n.issues LIKE "%{issue}%" '
        formatter['issue'] = issue
        formatter['notes_table'] = 'notes AS n,'
    if status:
        query += 'AND r.status = "{status}"'
        formatter['status'] = status
    if built_after:
        query += 'AND r.build_date > "{built_after}" '
        formatter['built_after'] = built_after
    if built_before:
        query += 'AND r.build_date < "{built_before}" '
        formatter['built_before'] = built_before
    results = query_db(query.format_map(formatter))
    results = [x for (x,) in results]
    log.info('Selected packages: ' + ' '.join(results))
    packages.extend(results)

if len(packages) > 50 and notify:
    log.critical(bcolors.RED + bcolors.BOLD)
    call(['figlet', 'No.'])
    log.critical(bcolors.FAIL + 'Do not reschedule more than 50 packages ',
                 'with notification.\nIf you think you need to do this, ',
                 'please discuss this with the IRC channel first.',
                 bcolors.ENDC)
    sys.exit(1)

if artifacts:
    log.info('The artifacts of the build(s) will be saved to the location '
             'mentioned at the end of the build log(s).')

if debug_url:
    log.info('The channel will be notified when the build starts')

ids = []
pkgs = []

query1 = '''SELECT id FROM sources WHERE name="{pkg}" AND suite="{suite}"
            AND architecture="{arch}"'''
query2 = '''SELECT p.date_build_started
            FROM sources AS s JOIN schedule as p ON p.package_id=s.id
            WHERE s.name="{pkg}"
            AND s.suite="{suite}" AND s.architecture="{arch}"'''
for pkg in packages:
    # test whether the package actually exists
    result = query_db(query1.format(pkg=pkg, suite=suite, arch=arch))
    try:
        # tests whether the package is already building
        result2 = query_db(query2.format(pkg=pkg, suite=suite, arch=arch))
        try:
            if not result2[0][0]:
                ids.append(result[0][0])
                pkgs.append(pkg)
            else:
                log.warning(bcolors.WARN + 'The package ' + pkg + ' is ' +
                    'already building, not scheduling it.' + bcolors.ENDC)
        except IndexError:
            ids.append(result[0][0])
            pkgs.append(pkg)
    except IndexError:
        log.error('%sThe package %s is not available in %s/%s%s',
                  bcolors.FAIL, pkg, suite, arch, bcolors.ENDC)

blablabla = '✂…' if len(' '.join(pkgs)) > 257 else ''
packages_txt = ' packages ' if len(pkgs) > 1 else ' package '
trailing = ' - artifacts will be preserved' if artifacts else ''
trailing += ' - with irc notification' if notify else ''
trailing += ' - notify on start too' if debug_url else ''

message = str(len(ids)) + packages_txt + 'scheduled in ' + suite + '/' + \
    arch + ' by ' + requester
if reason:
    message += ' (reason: ' + reason + ')'
message += ': ' + ' '.join(pkgs)[0:256] + blablabla + trailing


# these packages are manually scheduled, so should have high priority,
# so schedule them in the past, so they are picked earlier :)
# the current date is subtracted twice, so it sorts before early scheduling
# schedule on the full hour so we can recognize them easily
epoch = int(time.time())
yesterday = epoch - 60*60*24
now = datetime.now()
days = int(now.strftime('%j'))*2
hours = int(now.strftime('%H'))*2
minutes = int(now.strftime('%M'))
time_delta = timedelta(days=days, hours=hours, minutes=minutes)
date = (now - time_delta).strftime('%Y-%m-%d %H:%M')
log.debug('date_scheduled = ' + date + ' time_delta = ' + str(time_delta))


# a single person can't schedule more than 50 packages in the same day; this
# is actually easy to bypass, but let's give some trust to the Debian people
query = '''SELECT count(*) FROM manual_scheduler
           WHERE requester = "{}" AND date_request > "{}"'''
try:
    amount = int(query_db(query.format(requester, int(time.time()-86400)))[0][0])
except IndexError:
    amount = 0
log.debug(requester + ' already scheduled ' + str(amount) + ' packages today')
if amount + len(ids) > 50 and not local:
    log.error(bcolors.FAIL + 'You have exceeded the maximum number of manual ' +
              'reschedulings allowed for a day. Please ask in ' +
              '#debian-reproducible if you need to schedule more packages.' +
              bcolors.ENDC)
    sys.exit(1)


# do the actual scheduling
to_schedule = []
save_schedule = []
notify = '' if not notify else notify
debug_url = '' if not debug_url else 'TBD'
for id in ids:
    artifacts_value = 1 if artifacts else 0
    to_schedule.append((id, date, artifacts_value, str(notify).lower(),
                        requester, debug_url))
    save_schedule.append((id, requester, epoch))
log.debug('Packages about to be scheduled: ' + str(to_schedule))

query1 = '''REPLACE INTO schedule
    (package_id, date_scheduled, date_build_started, save_artifacts, notify,
    scheduler, builder)
    VALUES (?, ?, "", ?, ?, ?, ?)'''
query2 = '''INSERT INTO manual_scheduler
    (package_id, requester, date_request) VALUES (?, ?, ?)'''

if not dry_run:
    cursor = conn_db.cursor()
    cursor.executemany(query1, to_schedule)
    cursor.executemany(query2, save_schedule)
    conn_db.commit()
else:
    log.info('Ran with --dry-run, I did scheduled nothing')

log.info(bcolors.GOOD + message + bcolors.ENDC)
if not (local and requester == "jenkins maintenance job") and len(ids) != 0:
    if not dry_run:
        irc_msg(message)

generate_schedule()  # the html page
