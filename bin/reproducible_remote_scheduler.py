#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# A secure script to be called from remote hosts

import argparse
from subprocess import check_output


parser = argparse.ArgumentParser(
    description='Reschedule packages to re-test their reproducibly',
    epilog='You can wait for the results on #debian-reproducible, where the ' +
           'build will be announced')
parser.add_argument('-a', '--artifacts', default=False, action='store_true',
                    help='Save artifacts (for further offline study)')
parser.add_argument('-s', '--suite', required=True,
                    help='Specify the suite to schedule for')
parser.add_argument('-m', '--message', default='',
                    help='A text to be sent to the channel while notifing ' +
                    'the scheduling')
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
    log.critical('The specified suite is not in the available ones.')
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
now = datetime.datetime.now()
days = int(now.strftime('%j'))*2
hours = int(now.strftime('%H'))*2
minutes = int(now.strftime('%M'))
time_delta = datetime.timedelta(days=days, hours=hours, minutes=minutes)
date = (now - time_delta).strftime('%Y-%m-%d %H:%M')
log.debug('date_scheduled = ' + date + ' time_delta = ' + str(time_delta))

to_schedule = []
for id in ids:
    artifacts_value = 1 if artifacts else 0
    to_schedule.append((id, date, artifacts_value))
log.debug('Packages about to be scheduled: ' + str(to_schedule))

query = '''REPLACE INTO schedule
    (package_id, date_scheduled, date_build_started, save_artifacts, notify)
    VALUES (?, ?, "", ?, "true")'''

cursor = conn_db.cursor()
cursor.executemany(query, to_schedule)

log.info(bcolors.GOOD + message + bcolors.ENDC)
irc_msg(message)

generate_schedule()  # the html page
