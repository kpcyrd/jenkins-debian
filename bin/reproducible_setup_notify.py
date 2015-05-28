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
group = parser.add_mutually_exclusive_group()
parser.add_argument('-o', '--deactivate', action='store_true',
                    help='Deactivate the notifications')
group.add_argument('-p', '--packages', default='', nargs='+',
                   help='list of packages for which activate notifications')
local_args = parser.parse_known_args()[0]

# these are here as an hack to be able to parse the command line
from reproducible_common import *


class bcolors:
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    GOOD = '\033[92m'
    WARN = '\033[93m' + UNDERLINE
    FAIL = '\033[91m' + BOLD + UNDERLINE
    ENDC = '\033[0m'

packages = local_args.packages

if not packages:
    log.critical(bcolors.FAIL + 'You have to specify at least a package' +
                 bcolors.ENDC)

def _good(text):
    log.info(bcolors.GOOD + str(text) + bcolors.ENDC)

c = conn_db.cursor()

for package in packages:
    if local_args.deactivate:
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


