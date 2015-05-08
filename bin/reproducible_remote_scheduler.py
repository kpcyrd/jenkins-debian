#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# A secure script to be called from remote hosts

import time
import argparse


parser = argparse.ArgumentParser(
    description='Reschedule packages to re-test their reproducibility',
    epilog='The build results will be announced on the #debian-reproducible' +
           ' IRC channel.')
parser.add_argument('-a', '--artifacts', default=False, action='store_true',
                    help='Save artifacts (for further offline study)')
parser.add_argument('-s', '--suite', required=True,
                    help='Specify the suite to schedule in')
parser.add_argument('-m', '--message', default='',
                    help='A text to be sent to the IRC channel when notifying' +
                    ' about the scheduling')
parser.add_argument('packages', metavar='package', nargs='+',
                    help='list of packages to reschedule')
scheduling_args = parser.parse_known_args()[0]

# these are here as an hack to be able to parse the command line
from reproducible_common import *
from reproducible_html_indexes import generate_schedule


class bcolors:
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    GOOD = '\033[92m'
    WARN = '\033[93m' + UNDERLINE
    FAIL = '\033[91m' + BOLD + UNDERLINE
    ENDC = '\033[0m'


# this variable is expected to come from the remote host
try:
    requester = os.environ['LC_USER']
except KeyError:
    log.critical(bcolors.FAIL + 'You should use the provided script to '
                 'schedule packages. Ask in #debian-reproducible if you have '
                 'trouble with that.' + bcolors.ENDC)
    sys.exit(1)
suite = scheduling_args.suite
reason = scheduling_args.message
packages = scheduling_args.packages
artifacts = scheduling_args.artifacts

log.debug('Requester: ' + requester)
log.debug('Reason: ' + reason)
log.debug('Artifacts: ' + str(artifacts))
log.debug('Architecture: ' + defaultarch)
log.debug('Suite: ' + suite)

if suite not in SUITES:
    log.critical('The specified suite is not being tested.')
    log.critical('Please chose between ' + ', '.join(SUITES))
    sys.exit(1)

if scheduling_args.artifacts:
    log.info('The artifacts of the build(s) will be saved to the location '
             'mentioned at the end of the build log(s).')

ids = []

query = 'SELECT id FROM sources WHERE name="{pkg}" AND suite="{suite}"'
for pkg in packages:
    queryed = query.format(pkg=pkg, suite=suite)
    result = query_db(query.format(pkg=pkg, suite=suite))
    result = query_db(queryed)
    try:
        ids.append(result[0][0])
    except IndexError:
        log.critical('The package ' + pkg + ' is not available in ' + suite)
        sys.exit(1)

blablabla = '✂…' if len(' '.join(packages)) > 257 else ''
packages_txt = ' packages ' if len(packages) > 1 else ' package '
artifacts_txt = ' - artifacts will be preserved' if artifacts else ''

message = str(len(ids)) + packages_txt + 'scheduled in ' + suite + ' by ' + \
    requester
if reason:
    message += ' (reason: ' + reason + ')'
message += ': ' + ' '.join(packages)[0:256] + blablabla + artifacts_txt


# these packages are manually scheduled, so should have high priority,
# so schedule them in the past, so they are picked earlier :)
# the current date is subtracted twice, so it sorts before early scheduling
# schedule on the full hour so we can recognize them easily
epoch = int(time.time())
yesterday = epoch - 60*60*24
now = datetime.datetime.now()
days = int(now.strftime('%j'))*2
hours = int(now.strftime('%H'))*2
minutes = int(now.strftime('%M'))
time_delta = datetime.timedelta(days=days, hours=hours, minutes=minutes)
date = (now - time_delta).strftime('%Y-%m-%d %H:%M')
log.debug('date_scheduled = ' + date + ' time_delta = ' + str(time_delta))


# a single person can't schedule more than 50 packages in the same day; this
# is actually easy to bypass, but let's give some trust to the Debian people
query = '''SELECT count(*) FROM manual_scheduler
           WHERE requester = "{}" AND date_request > "{}"'''
try:
    amount = int(query_db(query.format(requester, date))[0][0])
except IndexError:
    amount = 0
log.debug(requester + ' already scheduled ' + str(amount) + ' packages today')
if amount + len(ids) > 50:
    log.error(bcolors.FAIL + 'You have exceeded the maximun number of manual ' +
              'rescheduling allowed for a day. Please ask in ' +
              '#debian-reproducible if you need to schedule more packages.' +
              bcolors.ENDC)
    sys.exit(1)


# do the actual scheduling
to_schedule = []
save_schedule = []
for id in ids:
    artifacts_value = 1 if artifacts else 0
    to_schedule.append((id, date, artifacts_value, requester))
    save_schedule.append((id, requester, epoch))
log.debug('Packages about to be scheduled: ' + str(to_schedule))

query1 = '''REPLACE INTO schedule
    (package_id, date_scheduled, date_build_started, save_artifacts, notify, scheduler)
    VALUES (?, ?, "", ?, "true", ?)'''
query2 = '''INSERT INTO manual_scheduler
    (package_id, requester, date_request) VALUES (?, ?, ?)'''

cursor = conn_db.cursor()
cursor.executemany(query1, to_schedule)
cursor.executemany(query2, save_schedule)
conn_db.commit()

log.info(bcolors.GOOD + message + bcolors.ENDC)
irc_msg(message)

generate_schedule()  # the html page
