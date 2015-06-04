#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Choose which packages should trigger an email to the maintainer when the
# reproducibly status change

import argparse

parser = argparse.ArgumentParser(
    description='Choose which packages should trigger an email to the ' +
                'maintainer when the reproducibly status change',
    epilog='The build results will be announced on the #debian-reproducible' +
           ' IRC channel.')
parser.add_argument('-o', '--deactivate', action='store_true',
                    help='Deactivate the notifications')
parser.add_argument('-p', '--packages', default='', nargs='+',
                    help='list of packages for which activate notifications')
parser.add_argument('-m', '--maintainer', default='',
                    help='email of a maintainer interested in his packages')
local_args = parser.parse_known_args()[0]

# these are here as an hack to be able to parse the command line
from reproducible_common import *
from reproducible_html_packages import gen_packages_html
from reproducible_html_indexes import build_page


class bcolors:
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    GOOD = '\033[92m'
    WARN = '\033[93m' + UNDERLINE
    FAIL = '\033[91m' + BOLD + UNDERLINE
    ENDC = '\033[0m'

packages = local_args.packages if local_args.packages else []
maintainer = local_args.maintainer

if not packages and not maintainer:
    log.critical(bcolors.FAIL + 'You have to specify at least a package ' +
                 'or a maintainer.' + bcolors.ENDC)

def _good(text):
    log.info(bcolors.GOOD + str(text) + bcolors.ENDC)


def process_pkg(package, deactivate):
    if deactivate:
        _good('Deactovating notification for package ' + str(package))
        flag = 0
    else:
        _good('Activating notification for package ' + str(package))
        flag = 1
    rows = c.execute(('UPDATE OR FAIL sources SET notify_maintainer="{}" ' +
                     'WHERE name="{}"').format(flag, package)).rowcount
    conn_db.commit()
    if rows == 0:
        log.error(bcolors.FAIL + str(package) + ' does not exists')
        sys.exit(1)
    if DEBUG:
        log.debug('Double check the change:')
        query = 'SELECT * FROM sources WHERE name="{}"'.format(package)
        log.debug(query_db(query))

if maintainer:
    global conn_udd
    if not conn_udd:
        conn_udd = start_udd_connection()
    c = conn_udd.cursor()
    query = "SELECT source FROM sources WHERE maintainer_email = '{}' " + \
            "AND release = 'sid' AND component = 'main'"
    try:
        c.execute(query.format(maintainer))
        pkgs = [x[0] for x in c.fetchall()]
    except IndexError:
        log.info('No packages maintained by ' + maintainer)
        sys.exit(0)
    finally:
        conn_udd.close()
    log.info('Packages maintained by ' + maintainer + ':')
    log.info('\t' + ', '.join(pkgs))
    packages.extend(pkgs)


c = conn_db.cursor()
for package in packages:
    process_pkg(package, local_args.deactivate)

gen_packages_html(packages, no_clean=True)
build_page('notify')

if local_args.deactivate:
    _good('Notifications disabled for ' + str(len(packages)) + ' package(s)')
else:
    _good('Notifications enabled for ' + str(len(packages)) + ' package(s)')
