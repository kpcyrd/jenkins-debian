#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
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
import smtplib
from subprocess import call
from apt_pkg import version_compare
from urllib.request import urlopen
from sqlalchemy import sql
from email.mime.text import MIMEText

from reproducible_common import *
from reproducible_html_live_status import generate_schedule
from reproducible_html_packages import gen_packages_html
from reproducible_html_packages import purge_old_pages

"""
How the scheduler chooses which limit to apply, based on the MAXIMA
and LIMIT arrays:

First, the scheduler is only started for an architecture if the number of
currently scheduled packages is lower than MAXIMA*3. Then if the number of
scheduled packages is higher than MAXIMA, only new versions are scheduled...


Then, for each category (totally _untested_ packages, _new_ versions,
_ftbfs_ and  _depwait_ packages and _old_ versions) it depends on how many
packages are already scheduled in that category, in a 3 steps process.

Only when scheduling old versions MINIMUM_AGE is respected.


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


LIMITS_404 defines how many packages with status 404 are rescheduled at max.

"""
# only old packages older than this will be rescheduled
MINIMUM_AGE = {'amd64': 10, 'i386': 14, 'arm64': 12, 'armhf':28 }
# maximum queue size, see explainations above
MAXIMA = {'amd64': 750, 'i386': 750, 'arm64': 1000, 'armhf': 750}
# limits, see explainations above
LIMITS = {
    'untested': {
        'amd64': {
            'testing': {'*': 100},
            'unstable': {'*': 100},
            'experimental': {'*': 100},
        },
        'i386': {
            'testing': {'*': 100},
            'unstable': {'*': 100},
            'experimental': {'*': 100},
        },
       'arm64': {
            'testing': {'*': 100},
            'unstable': {'*': 100},
            'experimental': {'*': 100},
        },
       'armhf': {
            'testing': {'*': 100},
            'unstable': {'*': 100},
            'experimental': {'*': 100},
        },
    },
    'new': {
        'amd64': {
            'testing': {1: (100, 250), 2: (200, 200), '*': 100},
            'unstable': {1: (100, 250), 2: (200, 200), '*': 150},
            'experimental': {1: (100, 250), 2: (200, 200), '*': 50},
        },
        'i386': {
            'testing': {1: (100, 250), 2: (200, 200), '*': 100},
            'unstable': {1: (100, 250), 2: (200, 200), '*': 150},
            'experimental': {1: (100, 250), 2: (200, 200), '*': 50},
        },
        'arm64': {
            'testing': {1: (100, 250), 2: (200, 200), '*': 50},
            'unstable': {1: (100, 250), 2: (200, 200), '*': 75},
            'experimental': {1: (100, 200), 2: (200, 200), '*': 25},
        },
        'armhf': {
            'testing': {1: (100, 200), 2: (200, 200), '*': 50},
            'unstable': {1: (100, 200), 2: (200, 200), '*': 75},
            'experimental': {1: (100, 200), 2: (200, 200), '*': 25},
        },
    },
    'ftbfs': {
        'amd64': {
            'testing': {1: (700, 40), 2: (500, 20), '*': 5},
            'unstable': {1: (700, 40), 2: (500, 20), '*': 5},
            'experimental': {1: (700, 40), 2: (500, 20), '*': 2},
        },
        'i386': {
            'testing': {1: (700, 40), 2: (500, 20), '*': 5},
            'unstable': {1: (700, 40), 2: (500, 20), '*': 5},
            'experimental': {1: (700, 40), 2: (500, 20), '*': 2},
        },
        'arm64': {
            'testing': {1: (700, 40), 2: (500, 20), '*': 5},
            'unstable': {1: (700, 40), 2: (500, 20), '*': 5},
            'experimental': {1: (700, 40), 2: (500, 20), '*': 2},
        },
        'armhf': {
            'testing': {1: (575, 20), 2: (450, 10), '*': 5},
            'unstable': {1: (575, 20), 2: (450, 10), '*': 5},
            'experimental': {1: (575, 20), 2: (450, 10), '*': 2},
        }
    },
    'depwait': {
        'amd64': {
            'testing': {1: (700, 400), 2: (500, 200), '*': 50},
            'unstable': {1: (700, 400), 2: (500, 200), '*': 50},
            'experimental': {1: (700, 400), 2: (500, 200), '*': 20},
        },
        'i386': {
            'testing': {1: (700, 400), 2: (500, 200), '*': 50},
            'unstable': {1: (700, 400), 2: (500, 200), '*': 50},
            'experimental': {1: (700, 400), 2: (500, 200), '*': 20},
        },
        'arm64': {
            'testing': {1: (700, 400), 2: (500, 200), '*': 50},
            'unstable': {1: (700, 400), 2: (500, 200), '*': 50},
            'experimental': {1: (700, 400), 2: (500, 200), '*': 20},
        },
        'armhf': {
            'testing': {1: (575, 200), 2: (450, 100), '*': 50},
            'unstable': {1: (575, 200), 2: (450, 100), '*': 50},
            'experimental': {1: (575, 200), 2: (450, 100), '*': 20},
        }
    },
    'old': {
        'amd64': {
            'testing': {1: (500, 900), 2: (850, 750), '*': 0},
            'unstable': {1: (500, 1100), 2: (850, 950), '*': 0},
            'experimental': {1: (500, 70), 2: (850, 50), '*': 0},
        },
        'i386': {
            'testing': {1: (500, 900), 2: (850, 750), '*': 0},
            'unstable': {1: (500, 1100), 2: (850, 950), '*': 0},
            'experimental': {1: (500, 70), 2: (850, 50), '*': 0},
        },
        'arm64': {
            'testing': {1: (500, 900), 2: (850, 750), '*': 0},
            'unstable': {1: (500, 1100), 2: (850, 950), '*': 0},
            'experimental': {1: (500, 70), 2: (850, 50), '*': 0},
        },
        'armhf': {
            'testing': {1: (500, 700), 2: (850, 400), '*': 0},
            'unstable': {1: (500, 900), 2: (850, 600), '*': 0},
            'experimental': {1: (500, 70), 2: (850, 50), '*': 0},
        }
    }
}
# maximum amount of packages with status 404 which will be rescheduled
LIMIT_404 = 255


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
        log.info('Updating sources db for %s/%s...', suite, arch)
        update_sources_db(suite, arch, sources)
        log.info('DB update done for %s/%s done at %s.', suite, arch, datetime.now().strftime("%Y-%m-%d %H:%M:%S"))


def update_sources_db(suite, arch, sources):
    # extract relevant info (package name and version) from the sources file
    new_pkgs = set()
    newest_version = {}
    for src in deb822.Sources.iter_paragraphs(sources.split('\n')):
        pkg = (src['Package'], src['Version'], suite, arch)

        # only keep the most recent version of a src for each package/suite/arch
        key = src['Package'] + suite + arch
        if key in newest_version:
            oldversion = newest_version[key]
            oldpackage = (src['Package'], oldversion, suite, arch)
            new_pkgs.remove(oldpackage)

        newest_version[key] = src['Version']
        new_pkgs.add(pkg)

    # get the current packages in the database
    query = "SELECT name, version, suite, architecture FROM sources " + \
            "WHERE suite='{}' AND architecture='{}'".format(suite, arch)
    cur_pkgs = set([(p.name, p.version, p.suite, p.architecture) for p in query_db(query)])
    pkgs_to_add = []
    updated_pkgs = []
    different_pkgs = [x for x in new_pkgs if x not in cur_pkgs]
    log.debug('Packages different in the archive and in the db: %s',
              different_pkgs)
    for pkg in different_pkgs:
        # pkg: (name, version, suite, arch)
        query = "SELECT id, version, notify_maintainer FROM sources " + \
                "WHERE name='{}' AND suite='{}' AND architecture='{}'"
        query = query.format(pkg[0], pkg[2], pkg[3])
        try:
            result = query_db(query)[0]
        except IndexError:  # new package
            pkgs_to_add.append({
                'name': pkg[0],
                'version': pkg[1],
                'suite': pkg[2],
                'architecture': pkg[3],
            })
            continue
        pkg_id = result[0]
        old_version = result[1]
        notify_maint = int(result[2])
        if version_compare(pkg[1], old_version) > 0:
            log.debug('New version: ' + str(pkg) + ' (we had  ' +
                      old_version + ')')
            updated_pkgs.append({
                'update_id': pkg_id,
                'name': pkg[0],
                'version': pkg[1],
                'suite': pkg[2],
                'architecture': pkg[3],
                'notify_maintainer': notify_maint,
            })
    # Now actually update the database:
    sources_table = db_table('sources')
    # updated packages
    log.info('Pushing ' + str(len(updated_pkgs)) +
             ' updated packages to the database...')
    if updated_pkgs:
        transaction = conn_db.begin()
        update_query = sources_table.update().\
                       where(sources_table.c.id == sql.bindparam('update_id'))
        conn_db.execute(update_query, updated_pkgs)
        transaction.commit()

    # new packages
    if pkgs_to_add:
        log.info('Now inserting %i new sources in the database: %s',
                 len(pkgs_to_add), pkgs_to_add)
        transaction = conn_db.begin()
        conn_db.execute(sources_table.insert(), pkgs_to_add)
        transaction.commit()

    # RM'ed packages
    cur_pkgs_name = [x[0] for x in cur_pkgs]
    new_pkgs_name = [x[0] for x in new_pkgs]
    rmed_pkgs = [x for x in cur_pkgs_name if x not in new_pkgs_name]
    log.info('Now deleting %i removed packages: %s', len(rmed_pkgs),
             rmed_pkgs)
    rmed_pkgs_id = []
    pkgs_to_rm = []
    query = "SELECT id FROM sources WHERE name='{}' AND suite='{}' " + \
            "AND architecture='{}'"
    for pkg in rmed_pkgs:
        result = query_db(query.format(pkg, suite, arch))
        rmed_pkgs_id.append({'deleteid': result[0][0]})
        pkgs_to_rm.append({'name': pkg, 'suite': suite, 'architecture': arch})
    log.debug('removed packages ID: %s',
              [str(x['deleteid']) for x in rmed_pkgs_id])
    log.debug('removed packages: %s', pkgs_to_rm)

    if rmed_pkgs_id:
        transaction = conn_db.begin()
        results_table = db_table('results')
        schedule_table = db_table('schedule')
        notes_table = db_table('notes')
        removed_packages_table = db_table('removed_packages')

        delete_results_query = results_table.delete().\
            where(results_table.c.package_id == sql.bindparam('deleteid'))
        delete_schedule_query = schedule_table.delete().\
            where(schedule_table.c.package_id == sql.bindparam('deleteid'))
        delete_notes_query = notes_table.delete().\
            where(notes_table.c.package_id == sql.bindparam('deleteid'))
        delete_sources_query = sources_table.delete().\
            where(sources_table.c.id == sql.bindparam('deleteid'))

        conn_db.execute(delete_results_query, rmed_pkgs_id)
        conn_db.execute(delete_schedule_query, rmed_pkgs_id)
        conn_db.execute(delete_notes_query, rmed_pkgs_id)
        conn_db.execute(delete_sources_query, rmed_pkgs_id)
        conn_db.execute(removed_packages_table.insert(), pkgs_to_rm)
        transaction.commit()

    # finally check whether the db has the correct number of packages
    query = "SELECT count(*) FROM sources WHERE suite='{}' " + \
            "AND architecture='{}'"
    pkgs_end = query_db(query.format(suite, arch))
    count_new_pkgs = len(set([x[0] for x in new_pkgs]))
    if int(pkgs_end[0][0]) != count_new_pkgs:
        print_critical_message('AH! The number of source in the Sources file' +
                               ' is different than the one in the DB!')
        log.critical('source in the debian archive for the %s suite: %s',
                     suite, str(count_new_pkgs))
        log.critical('source in the reproducible db for the  %s suite: %s',
                     suite, str(pkgs_end[0][0]))
        sys.exit(1)
    if pkgs_to_add:
        log.info('Building pages for the new packages')
        gen_packages_html([Package(x['name']) for x in pkgs_to_add], no_clean=True)


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
    pkgs = [{'package_id': x, 'date_scheduled': packages[x]} for x in packages.keys()]
    log.debug('IDs about to be scheduled: %s', packages.keys())
    if pkgs:
        conn_db.execute(db_table('schedule').insert(), pkgs)


def add_up_numbers(packages, arch):
    packages_sum = '+'.join([str(len(packages[x])) for x in SUITES])
    if packages_sum == '0+0+0':
        packages_sum = '0'
    return packages_sum


def query_untested_packages(suite, arch, limit):
    criteria = 'not tested before, randomly sorted'
    query = """SELECT DISTINCT *
               FROM (
                    SELECT sources.id, sources.name FROM sources
                    WHERE sources.suite='{suite}' AND sources.architecture='{arch}'
                    AND sources.id NOT IN
                       (SELECT schedule.package_id FROM schedule)
                    AND sources.id NOT IN
                       (SELECT results.package_id FROM results)
                    ORDER BY random()
                ) AS tmp
                LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_new_versions(suite, arch, limit):
    criteria = 'tested before, new version available, sorted by last build date'
    query = """SELECT s.id, s.name, s.version, r.version, max(r.build_date) max_date
               FROM sources AS s JOIN results AS r ON s.id = r.package_id
               WHERE s.suite='{suite}' AND s.architecture='{arch}'
               AND s.version != r.version
               AND r.status != 'blacklisted'
               AND s.id IN (SELECT package_id FROM results)
               AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
               GROUP BY s.id, s.name, s.version, r.version
               ORDER BY max_date
               LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit)
    pkgs = query_db(query)
    # the next line avoids constant rescheduling of packages:
    # packages in our repository != sid or testing,
    # so they will always be selected by the query above
    # so we only accept them if there version is greater than the already tested one
    packages = [(x[0], x[1]) for x in pkgs if version_compare(x[2], x[3]) > 0]
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_old_ftbfs_versions(suite, arch, limit):
    criteria = 'status ftbfs, no bug filed, tested at least 3 days ago, ' + \
               'no new version available, sorted by last build date'
    date = (datetime.now()-timedelta(days=3)).strftime('%Y-%m-%d %H:%M')
    query = """SELECT s.id, s.name, max(r.build_date) max_date
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                JOIN notes AS n ON n.package_id=s.id
                WHERE s.suite='{suite}' AND s.architecture='{arch}'
                AND r.status='FTBFS'
                AND ( n.bugs = '[]' OR n.bugs IS NULL )
                AND r.build_date < '{date}'
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                GROUP BY s.id, s.name
                ORDER BY max_date
                LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit,
                                        date=date)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_old_depwait_versions(suite, arch, limit):
    criteria = 'status depwait, no bug filed, tested at least 2 days ago, ' + \
               'no new version available, sorted by last build date'
    date = (datetime.now()-timedelta(days=2)).strftime('%Y-%m-%d %H:%M')
    query = """SELECT s.id, s.name, max(r.build_date) max_date
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                WHERE s.suite='{suite}' AND s.architecture='{arch}'
                AND r.status='depwait'
                AND r.build_date < '{date}'
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                GROUP BY s.id, s.name
                ORDER BY max_date
                LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit,
                                        date=date)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages


def query_old_versions(suite, arch, limit):
    criteria = """tested at least {minimum_age} days ago, no new version available,
               sorted by last build date""".format(minimum_age=MINIMUM_AGE[arch])
    date = (datetime.now()-timedelta(days=MINIMUM_AGE[arch]))\
           .strftime('%Y-%m-%d %H:%M')
    query = """SELECT s.id, s.name, max(r.build_date) max_date
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                WHERE s.suite='{suite}' AND s.architecture='{arch}'
                AND r.status != 'blacklisted'
                AND r.build_date < '{date}'
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                GROUP BY s.id, s.name
                ORDER BY max_date
                LIMIT {limit}""".format(suite=suite, arch=arch,
                                        date=date, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, arch, criteria, packages)
    return packages

def query_404_versions(suite, arch, limit):
    criteria = """tested at least a day ago, status 404,
               sorted by last build date"""
    date = (datetime.now()-timedelta(days=1)).strftime('%Y-%m-%d %H:%M')
    query = """SELECT s.id, s.name, max(r.build_date) max_date
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                WHERE s.suite='{suite}' AND s.architecture='{arch}'
                AND r.status = '404'
                AND r.build_date < '{date}'
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                GROUP BY s.id, s.name
                ORDER BY max_date
                LIMIT {limit}""".format(suite=suite, arch=arch, limit=limit,
                                        date=date)
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
                 ' untested packages in ' + suite + '/' + arch + ' to schedule.')
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
        msg += ' new versions'
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
        msg += ' ftbfs without bugs filed'
    else:
        msg = ''
    return packages, msg


def schedule_old_depwait_versions(arch, total):
    packages = {}
    limit = Limit(arch, 'depwait')
    for suite in SUITES:
        limit.suite = suite
        old_depwait = limit.get_staged_limit(total)
        log.info('Requesting %s old depwait packages in %s/%s...', old_depwait,
                 suite, arch)
        packages[suite] = query_old_depwait_versions(suite, arch, old_depwait)
        log.info('Received ' + str(len(packages[suite])) +
                 ' old depwait packages in ' + suite + '/' + arch + ' to schedule.')
        log.info('--------------------------------------------------------------')
    msg = add_up_numbers(packages, arch)
    if msg != '0':
        msg += ' in depwait state'
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

def schedule_404_versions(arch, total):
    packages = {}
    for suite in SUITES:
        log.info('Requesting 404 packages in %s/%s...',
                 suite, arch)
        packages[suite] = query_404_versions(suite, arch, LIMIT_404)
        log.info('Received ' + str(len(packages[suite])) +
                 ' 404 packages in ' + suite + '/' + arch + ' to schedule.')
        log.info('--------------------------------------------------------------')
    msg = add_up_numbers(packages, arch)
    if msg != '0':
        msg += ' with status \'404\''
    else:
        msg = ''
    return packages, msg


def scheduler(arch):
    query = "SELECT count(*) " + \
            "FROM schedule AS p JOIN sources AS s ON p.package_id=s.id " + \
            "WHERE s.architecture='{arch}'"
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
        old_depwait, msg_old_depwait = empty_pkgs, ''
        old, msg_old = empty_pkgs, ''
        four04, msg_404 = empty_pkgs, ''
    else:
        log.info(str(total) + ' packages already scheduled' +
                 ', scheduling some more...')
        untested, msg_untested = schedule_untested_packages(arch, total)
        new, msg_new = schedule_new_versions(arch, total+len(untested))
        old_ftbfs, msg_old_ftbfs = schedule_old_ftbfs_versions(arch, total+len(untested)+len(new))
        old_depwait, msg_old_depwait = schedule_old_depwait_versions(arch, total+len(untested)+len(new)+len(old_ftbfs))
        four04, msg_404 = schedule_404_versions(arch, total+len(untested)+len(new)+len(old_ftbfs)+len(old_depwait))
        old, msg_old = schedule_old_versions(arch, total+len(untested)+len(new)+len(old_ftbfs)+len(old_depwait)+len(four04))

    now_queued_here = {}
    # make sure to schedule packages in unstable first
    # (but keep the view ordering everywhere else)
    priotized_suite_order = ['unstable']
    for suite in SUITES:
        if suite not in priotized_suite_order:
            priotized_suite_order.append(suite)
    for suite in priotized_suite_order:
        query = "SELECT count(*) " \
                "FROM schedule AS p JOIN sources AS s ON p.package_id=s.id " \
                "WHERE s.suite='{suite}' AND s.architecture='{arch}'"
        query = query.format(suite=suite, arch=arch)
        now_queued_here[suite] = int(query_db(query)[0][0]) + \
            len(untested[suite]+new[suite]+old[suite])
        # schedule packages differently in the queue...
        to_be_scheduled = queue_packages({}, untested[suite], datetime.now()+timedelta(minutes=-720))
        assert(isinstance(to_be_scheduled, dict))
        to_be_scheduled = queue_packages(to_be_scheduled, new[suite], datetime.now()+timedelta(minutes=-1440))
        to_be_scheduled = queue_packages(to_be_scheduled, old_ftbfs[suite], datetime.now()+timedelta(minutes=360))
        to_be_scheduled = queue_packages(to_be_scheduled, old_depwait[suite], datetime.now()+timedelta(minutes=-360))
        to_be_scheduled = queue_packages(to_be_scheduled, old[suite], datetime.now()+timedelta(minutes=720))
        to_be_scheduled = queue_packages(to_be_scheduled, four04[suite], datetime.now())
        schedule_packages(to_be_scheduled)
    # update the scheduled page
    generate_schedule(arch)  # from reproducible_html_indexes
    # build the message text for this arch
    message = ' - ' + arch + ': '
    if msg_untested:
        message += msg_untested + ', '
    if msg_new:
        message += msg_new + ', '
    if msg_404:
        message += msg_404 + ', '
    if msg_old_ftbfs:
        message += msg_old_ftbfs + ', '
    if msg_old_depwait:
        message += msg_old_depwait + ', '
    if msg_old:
        message += msg_old + ', '
    total = [now_queued_here[x] for x in SUITES]
    message += 'for ' + str(sum(total))
    message += ' or ' + '+'.join([str(now_queued_here[x]) for x in SUITES])
    message += ' in total.'
    log.info('Scheduling for architecture ' + arch + ' done.')
    log.info('--------------------------------------------------------------')
    # only notifiy irc if there were packages scheduled in any suite
    for x in SUITES:
        if len(untested[x])+len(new[x])+len(old[x])+len(old_ftbfs[x])+len(old_depwait[x]) > 0:
            return message
    return ''

if __name__ == '__main__':
    log.info('Updating sources tables for all suites.')
    for suite in SUITES:
        update_sources(suite)
        log.info('Sources for suite %s done at %s.', suite, datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    purge_old_pages()
    query = "SELECT count(*) " + \
            "FROM schedule AS p JOIN sources AS s ON s.id=p.package_id " + \
            "WHERE s.architecture='{}'"
    message = ''
    for arch in ARCHS:
        log.info('Scheduling for %s...', arch)
        overall = int(query_db(query.format(arch))[0][0])
        if overall > (MAXIMA[arch]*3):
            log.info('%s packages already scheduled for %s, nothing to do.', overall, arch)
            continue
        log.info('%s packages already scheduled for %s, probably scheduling some '
                 'more...', overall, arch)
        message += scheduler(arch) + '\n'
        log.info('Arch %s scheduled at %s.', arch, datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    if message != '':
        # build the kgb message text
        message = 'Scheduled in ' + '+'.join(SUITES) + ':\n' + message
        log.info(message)
        # irc_msg(message, channel='debian-reproducible-changes')
        # send mail instead of notifying via irc, less intrusive
        msg = MIMEText(message)
        mail_from = 'jenkins@jenkins.debian.net'
        mail_to = 'qa-jenkins-scm@lists.alioth.debian.org'
        msg['From'] = mail_from
        msg['To'] = mail_to
        msg['Subject'] = 'packages scheduled for reproducible Debian'
        s = smtplib.SMTP('localhost')
        s.sendmail(mail_from, [mail_to], msg.as_string())
        s.quit()
