#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
# Based on reproducible_scheduler.sh © 2014-2015 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3 python3-debian
#
# Schedule packages to be build.

import sys
import lzma
import deb822
import aptsources.sourceslist
import random
from time import sleep
from random import randint
from subprocess import call
from apt_pkg import version_compare
from urllib.request import urlopen

from reproducible_common import *
from reproducible_html_live_status import generate_schedule
from reproducible_html_packages import gen_packages_html
from reproducible_html_packages import purge_old_pages

"""
How the scheduler chooses which limit to apply, based on the MAXIMA
and LIMIT arrays:

First, the scheduler is only started for an architecture if the number of
currently scheduled packages is lower than MAXIMA*2. Then if the number of
scheduled packages is higher than MAXIMA, only new versions are scheduled...


Then, for each category (totally _untested_ packages, _new_ versions,
_ftbfs_ packages and _old_ versions) it depends on how many packages are
already scheduled in that category, in a 3 steps process.


Let's go by an example:
    'unstable': {1: (250, 40), 2: (350, 20), '*': 5},
is translated to:

if total < 250:
    40
elif total < 350:
    20
else:
    5

 * 1st step, if there are less than 250 packages in the queue, schedule 40
 * 2nd step, if there are less than 350 packages in the queue, schedule 20
 * 3rd step, schedule 5

So, the 3rd step happens only when there are more than 350 packages queued up.


Finally, MINIMUM_AGE is respected when scheduling old versions.

"""
MAXIMA = {'amd64': 750, 'armhf': 250}

LIMITS = {
    'untested': {
        'amd64': {
            'testing': {'*': 440},
            'unstable': {'*': 440},
            'experimental': {'*': 440},
        },
        'armhf': {
            'testing': {'*': 0},
            'unstable': {'*': 130},
            'experimental': {'*': 0},
        },
    },
    'new': {
        'amd64': {
            'testing': {1: (100, 250), 2: (200, 200), '*': 150},
            'unstable': {1: (100, 250), 2: (200, 200), '*': 150},
            'experimental': {1: (100, 250), 2: (200, 200), '*': 150},
        },
        'armhf': {
            'testing': {1: (100, 0), 2: (200, 0), '*': 0},
            'unstable': {1: (100, 75), 2: (200, 60), '*': 45},
            'experimental': {1: (100, 0), 2: (200, 0), '*': 0},
        },
    },
    'ftbfs': {
        'amd64': {
            'testing': {1: (250, 40), 2: (350, 20), '*': 0},
            'unstable': {1: (250, 40), 2: (350, 20), '*': 0},
            'experimental': {1: (250, 40), 2: (350, 20), '*': 0},
        },
        'armhf': {
            'testing': {1: (250, 0), 2: (350, 0), '*': 0},
            'unstable': {1: (250, 12), 2: (350, 6), '*': 0},
            'experimental': {1: (250, 0), 2: (350, 0), '*': 0},
        }
    },
    'old': {
        'amd64': {
            'testing': {1: (300, 333), 2: (400, 400), '*': 0},
            'unstable': {1: (300, 444), 2: (400, 500), '*': 0},
            'experimental': {1: (300, 35), 2: (400, 25), '*': 0},
        },
        'armhf': {
            'testing': {1: (300, 0), 2: (400, 0), '*': 0},
            'unstable': {1: (300, 50), 2: (400, 40), '*': 0},
            'experimental': {1: (300, 0), 2: (400, 0), '*': 0},
        }
    }
}

# only old packages older than this will be rescheduled
MINIMUM_AGE = {'amd64': 14, 'armhf': 100}


class Limit:
    def __init__(self, arch, queue):
        self.arch = arch
        self.queue = queue

    def get_level(self, stage):
        try:
            return int(LIMITS[self.queue][self.arch][self.suite][stage][0])
        except KeyError:
            log.error('No limit defined for the %s queue on %s/%s stage %s. '
                      'Returning 1', self.queue, self.suite, self.arch, stage)
            return 1
        except IndexError:
            log.critical('The limit is not in the format "(level, limit)". '
                         'I can\'t guess what you want, giving up')
            sys.exit(1)

    def get_limit(self, stage):
        try:
            limit = LIMITS[self.queue][self.arch][self.suite][stage]
            limit = limit[1]
        except KeyError:
            log.error('No limit defined for the %s queue on %s/%s stage %s. '
                      'Returning 1', self.queue, self.suite, self.arch, stage)
            return 1
        except IndexError:
            log.critical('The limit is not in the format "(level, limit)". '
                         'I can\'t guess what you want, giving up')
            sys.exit(1)
        except TypeError:
            # this is the case of the default target
            if isinstance(limit, int):
                pass
            else:
                raise
        return int(limit)

    def get_staged_limit(self, current_total):
        if current_total <= self.get_level(1):
            return self.get_limit(1)
        elif current_total <= self.get_level(2):
            return self.get_limit(2)
        else:
            return self.get_limit('*')


def update_sources(suite):
    # download the sources file for this suite
    mirror = 'http://ftp.de.debian.org/debian'
    remotefile = mirror + '/dists/' + suite + '/main/source/Sources.xz'
    log.info('Downloading sources file for %s: %s', suite, remotefile)
    sources = lzma.decompress(urlopen(remotefile).read()).decode('utf8')
    log.debug('\tdownloaded')
    for arch in ARCHS:
        if arch == 'armhf' and suite != 'unstable':
            continue
        else:
            log.info('Updating sources db for %s/%s...', suite, arch)
            update_sources_db(suite, arch, sources)


def update_sources_db(suite, arch, sources):
    # extract relevant info (package name and version) from the sources file
    new_pkgs = []
    for src in deb822.Sources.iter_paragraphs(sources.split('\n')):
        pkg = (src['Package'], src['Version'], suite, arch)
        new_pkgs.append(pkg)
    # get the current packages in the database
    query = 'SELECT name, version, suite, architecture FROM sources ' + \
            'WHERE suite="{}" AND architecture="{}"'.format(suite, arch)
    cur_pkgs = query_db(query)
    pkgs_to_add = []
    updated_pkgs = []
    different_pkgs = [x for x in new_pkgs if x not in cur_pkgs]
    log.debug('Packages different in the archive and in the db: ' +
              str(different_pkgs))
    for pkg in different_pkgs:
        # pkg: (name, version, suite, arch)
        query = 'SELECT id, version, notify_maintainer FROM sources ' + \
                'WHERE name="{}" AND suite="{}" AND architecture="{}"'
        query = query.format(pkg[0], pkg[2], pkg[3])
        try:
            result = query_db(query)[0]
        except IndexError:  # new package
            pkgs_to_add.append(pkg)
            continue
        pkg_id = result[0]
        old_version = result[1]
        notify_maint = int(result[2])
        if version_compare(pkg[1], old_version) > 0:
            log.debug('New version: ' + str(pkg) + ' (we had  ' +
                      old_version + ')')
            updated_pkgs.append(
                (pkg_id, pkg[0], pkg[1], pkg[2], pkg[3], notify_maint))
    # Now actually update the database:
    cursor = conn_db.cursor()
    # updated packages
    log.info('Pushing ' + str(len(updated_pkgs)) +
             ' updated packages to the database...')
    cursor.executemany(
        'REPLACE INTO sources ' +
        '(id, name, version, suite, architecture, notify_maintainer) ' +
        'VALUES (?, ?, ?, ?, ?, ?)',
        updated_pkgs)
    conn_db.commit()
    # new packages
    log.info('Now inserting ' + str(len(pkgs_to_add)) +
             ' new sources in the database: ' +
             str(pkgs_to_add))
    cursor.executemany('INSERT INTO sources ' +
                       '(name, version, suite, architecture) ' +
                       'VALUES (?, ?, ?, ?)', pkgs_to_add)
    conn_db.commit()
    # RM'ed packages
    cur_pkgs_name = [x[0] for x in cur_pkgs]
    new_pkgs_name = [x[0] for x in new_pkgs]
    rmed_pkgs = [x for x in cur_pkgs_name if x not in new_pkgs_name]
    log.info('Now deleting ' + str(len(rmed_pkgs)) +
             ' removed packages: ' + str(rmed_pkgs))
    rmed_pkgs_id = []
    pkgs_to_rm = []
    query = 'SELECT id FROM sources WHERE name="{}" AND suite="{}" ' + \
            'AND architecture="{}"'
    for pkg in rmed_pkgs:
        result = query_db(query.format(pkg, suite, arch))
        rmed_pkgs_id.extend(result)
        pkgs_to_rm.append((pkg, suite, arch))
    log.debug('removed packages ID: ' + str([str(x[0]) for x in rmed_pkgs_id]))
    log.debug('removed packages: ' + str(pkgs_to_rm))
    cursor.executemany('DELETE FROM sources '
                       'WHERE id=?', rmed_pkgs_id)
    cursor.executemany('DELETE FROM results '
                       'WHERE package_id=?', rmed_pkgs_id)
    cursor.executemany('DELETE FROM schedule '
                       'WHERE package_id=?', rmed_pkgs_id)
    cursor.executemany('INSERT INTO removed_packages '
                       '(name, suite, architecture) '
                       'VALUES (?, ?, ?)', pkgs_to_rm)
    conn_db.commit()
    # finally check whether the db has the correct number of packages
    query = 'SELECT count(*) FROM sources WHERE suite="{}" ' + \
            'AND architecture="{}"'
    pkgs_end = query_db(query.format(suite, arch))
    count_new_pkgs = len(set([x[0] for x in new_pkgs]))
    if int(pkgs_end[0][0]) != count_new_pkgs:
        print_critical_message('AH! The number of source in the Sources file' +
                               ' is different than the one in the DB!')
        log.critical('source in the debian archive for the ' + suite +
                     ' suite:' + str(count_new_pkgs))
        log.critical('source in the reproducible db for the ' + suite +
                     ' suite:' + str(pkgs_end[0][0]))
        sys.exit(1)
    if pkgs_to_add:
        log.info('Building pages for the new packages')
        gen_packages_html([Package(x) for x in pkgs_to_add], no_clean=True)


def print_schedule_result(suite, arch, criteria, packages):
    '''
    `packages` is the usual list-of-tuples returned by SQL queries,
    where the first item is the id and the second one the package name
    '''
    log.info('Criteria:   ' + criteria)
    log.info('Suite/Arch: ' + suite + '/' + arch)
    log.info('Amount:     ' + str(len(packages)))
    log.info('Packages:   ' + ' '.join([x[1] for x in packages]))


def queue_packages(all_pkgs, packages, date):
    date = date.strftime('%Y-%m-%d %H:%M')
    pkgs = [x for x in packages if x[0] not in all_pkgs]
    if len(pkgs) > 0:
        log.info('The following ' + str(len(pkgs)) + ' source packages have ' +
             'been queued up for scheduling at ' + date + ': ' +
             ' '.join([str(x[1]) for x in pkgs]))
    all_pkgs.update({x[0]: date for x in pkgs})
    return all_pkgs


def schedule_packages(packages):
    pkgs = ((x, packages[x]) for x in packages)
    log.debug('IDs about to be scheduled: ' + str(packages.keys()))
    query = 'INSERT INTO schedule ' + \
            '(package_id, date_scheduled, date_build_started) ' + \
            'VALUES (?, ?, "")'
    cursor = conn_db.cursor()
    cursor.executemany(query, pkgs)
    conn_db.commit()


def add_up_numbers(packages, arch):
    packages_sum = '+'.join([str(len(packages[x])) for x in SUITES])
    if packages_sum == '0+0+0':
        packages_sum = '0'
    elif arch == 'armhf':
        packages_sum = str(len(packages['unstable']))
    return packages_sum


def query_untested_packages(suite, arch, limit):
    criteria = 'not tested before, randomly sorted'
    query = """SELECT DISTINCT sources.id, sources.name FROM sources
               WHERE sources.suite='{suite}' AND sources.architecture='{arch}'
               AND sources.id NOT IN
                       (SELECT schedule.package_id FROM schedule)
               AND sources.id NOT IN
                       (SELECT results.package_id FROM results)
               ORDER BY random()
               LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_new_versions(suite, arch, limit):
    criteria = 'tested before, new version available, sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name, s.version, r.version
               FROM sources AS s JOIN results AS r ON s.id = r.package_id
               WHERE s.suite='{suite}' AND s.architecture='{arch}'
               AND s.version != r.version
               AND r.status != 'blacklisted'
               AND s.id IN (SELECT package_id FROM results)
               AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
               ORDER BY r.build_date
               LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit)
    pkgs = query_db(query)
    # this is to avoid constant rescheduling of packages in our exp repository
    packages = [(x[0], x[1]) for x in pkgs if version_compare(x[2], x[3]) > 0]
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_old_ftbfs_versions(suite, arch, limit):
    criteria = 'status ftbfs, no bug filed, tested at least ten days ago, ' + \
               'no new version available, sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                JOIN notes AS n ON n.package_id=s.id
                WHERE s.suite='{suite}' AND s.architecture='{arch}'
                AND r.status = 'FTBFS'
                AND ( n.bugs = '[]' OR n.bugs IS NULL )
                AND r.build_date < datetime('now', '-10 day')
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                ORDER BY r.build_date
                LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_old_versions(suite, arch, limit):
    criteria = 'tested at least two weeks ago, no new version available, ' + \
               'sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                WHERE s.suite='{suite}' AND s.architecture='{arch}'
                AND r.status != 'blacklisted'
                AND r.build_date < datetime('now', '-{minimum_age} day')
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                ORDER BY r.build_date
                LIMIT {limit}""".format(suite=suite, arch=arch, minimum_age=MINIMUM_AGE[arch], limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def schedule_untested_packages(arch, total):
    packages = {}
    limit = Limit(arch, 'untested')
    for suite in SUITES:
        limit.suite = suite
        many_untested = limit.get_limit('*')
        log.info('Requesting %s untested packages in %s/%s...',
                 many_untested, suite, arch)
        packages[suite] = query_untested_packages(suite, arch, many_untested)
        log.info('Received ' + str(len(packages[suite])) +
                 ' untested packages in ' + suite + '/' + arch + 'to schedule.')
        log.info('--------------------------------------------------------------')
    msg = add_up_numbers(packages, arch)
    if msg != '0':
        msg += ' new packages'
    else:
        msg = ''
    return packages, msg


def schedule_new_versions(arch, total):
    packages = {}
    limit = Limit(arch, 'new')
    for suite in SUITES:
        limit.suite = suite
        many_new = limit.get_staged_limit(total)
        log.info('Requesting %s new versions in %s/%s...',
                 many_new, suite, arch)
        packages[suite] = query_new_versions(suite, arch, many_new)
        log.info('Received ' + str(len(packages[suite])) +
                 ' new packages in ' + suite + '/' + arch + ' to schedule.')
        log.info('--------------------------------------------------------------')
    msg = add_up_numbers(packages, arch)
    if msg != '0':
        msg += ' with new versions'
    else:
        msg = ''
    return packages, msg


def schedule_old_ftbfs_versions(arch, total):
    packages = {}
    limit = Limit(arch, 'ftbfs')
    for suite in SUITES:
        limit.suite = suite
        old_ftbfs = limit.get_staged_limit(total)
        log.info('Requesting %s old ftbfs packages in %s/%s...', old_ftbfs,
                 suite, arch)
        packages[suite] = query_old_ftbfs_versions(suite, arch, old_ftbfs)
        log.info('Received ' + str(len(packages[suite])) +
                 ' old ftbfs packages in ' + suite + '/' + arch + ' to schedule.')
        log.info('--------------------------------------------------------------')
    msg = add_up_numbers(packages, arch)
    if msg != '0':
        msg += ' ftbfs versions without bugs filed'
    else:
        msg = ''
    return packages, msg


def schedule_old_versions(arch, total):
    packages = {}
    limit = Limit(arch, 'old')
    for suite in SUITES:
        limit.suite = suite
        many_old = limit.get_staged_limit(total)
        log.info('Requesting %s old packages in %s/%s...', many_old,
                 suite, arch)
        packages[suite] = query_old_versions(suite, arch, many_old)
        log.info('Received ' + str(len(packages[suite])) +
                 ' old packages in ' + suite + '/' + arch + ' to schedule.')
        log.info('--------------------------------------------------------------')
    msg = add_up_numbers(packages, arch)
    if msg != '0':
        msg += ' known versions'
    else:
        msg = ''
    return packages, msg


def scheduler(arch):
    query = 'SELECT count(*) ' + \
            'FROM schedule AS p JOIN sources AS s ON p.package_id=s.id ' + \
            'WHERE s.architecture="{arch}"'
    total = int(query_db(query.format(arch=arch))[0][0])
    log.info('==============================================================')
    log.info('Currently scheduled packages in all suites on ' + arch + ': ' + str(total))
    if total > MAXIMA[arch]:
        log.info(str(total) + ' packages already scheduled' +
                 ', only scheduling new versions.')
        empty_pkgs = {}
        for suite in SUITES:
            empty_pkgs[suite] = []
        untested, msg_untested = empty_pkgs, ''
        new, msg_new = schedule_new_versions(arch, total)
        old_ftbfs, msg_old_ftbfs = empty_pkgs, ''
        old, msg_old = empty_pkgs, ''
    else:
        log.info(str(total) + ' packages already scheduled' +
                 ', scheduling some more...')
        untested, msg_untested = schedule_untested_packages(arch, total)
        new, msg_new = schedule_new_versions(arch, total+len(untested))
        old_ftbfs, msg_old_ftbfs = schedule_old_ftbfs_versions(arch, total+len(untested)+len(new))
        old, msg_old = schedule_old_versions(arch, total+len(untested)+len(new)+len(old_ftbfs))

    now_queued_here = {}
    # make sure to schedule packages in unstable first
    # (but keep the view ordering everywhere else)
    priotized_suite_order = ['unstable']
    for suite in SUITES:
        if suite not in priotized_suite_order:
            priotized_suite_order.append(suite)
    for suite in priotized_suite_order:
        if arch == 'armhf' and suite != 'unstable':
            now_queued_here[suite] = 0
            continue
        query = 'SELECT count(*) ' \
                'FROM schedule AS p JOIN sources AS s ON p.package_id=s.id ' \
                'WHERE s.suite="{suite}" AND s.architecture="{arch}"'
        query = query.format(suite=suite, arch=arch)
        now_queued_here[suite] = int(query_db(query)[0][0]) + \
            len(untested[suite]+new[suite]+old[suite])
        # schedule packages differently in the queue...
        to_be_scheduled = queue_packages({}, untested[suite], datetime.now())
        assert(isinstance(to_be_scheduled, dict))
        to_be_scheduled = queue_packages(to_be_scheduled, new[suite], datetime.now()+timedelta(minutes=-720))
        to_be_scheduled = queue_packages(to_be_scheduled, old_ftbfs[suite], datetime.now()+timedelta(minutes=360))
        to_be_scheduled = queue_packages(to_be_scheduled, old[suite], datetime.now()+timedelta(minutes=720))
        schedule_packages(to_be_scheduled)
    # update the scheduled page
    generate_schedule(arch)  # from reproducible_html_indexes
    # build the kgb message text
    if arch != 'armhf':
        message = 'Scheduled in ' + '+'.join(SUITES) + ' (' + arch + '): '
    else:
        message = 'Scheduled in unstable (' + arch + '): '
    if msg_untested:
        message += msg_untested
        message += ' and ' if msg_new and not msg_old_ftbfs and not msg_old else ''
        message += ', ' if ( msg_new and msg_old_ftbfs ) or ( msg_new and msg_old ) else ''
    if msg_new:
        message += msg_new
        message += ' and ' if msg_old_ftbfs and not msg_old else ''
        message += ', ' if msg_old_ftbfs and msg_old else ''
    if msg_old_ftbfs:
        message += msg_old_ftbfs
        message += ' and ' if msg_old_ftbfs else ''
    if msg_old:
        message += msg_old
    total = [now_queued_here[x] for x in SUITES]
    message += ', for ' + str(sum(total))
    if arch != 'armhf':
        message += ' or ' + '+'.join([str(now_queued_here[x]) for x in SUITES])
    message += ' packages in total.'
    # only notifiy irc if there were packages scheduled in any suite
    for x in SUITES:
        if len(untested[x])+len(new[x])+len(old[x])+len(old_ftbfs[x]) > 0:
            log.info(message)
            irc_msg(message)
            break
    log.info('Scheduling for architecture ' + arch + ' done.')
    log.info('--------------------------------------------------------------')


if __name__ == '__main__':
    log.info('Updating sources tables for all suites.')
    for suite in SUITES:
        update_sources(suite)
    purge_old_pages()
    query = 'SELECT count(*) ' + \
            'FROM schedule AS p JOIN sources AS s ON s.id=p.package_id ' + \
            'WHERE s.architecture="{}"'
    for arch in ARCHS:
        log.info('Scheduling for %s...', arch)
        overall = int(query_db(query.format(arch))[0][0])
        if overall > (MAXIMA[arch]*2):
            log.info('%s packages already scheduled for %s, nothing to do.', overall, arch)
            continue
        log.info('%s packages already scheduled for %s, probably scheduling some '
                 'more...', overall, arch)
        scheduler(arch)
