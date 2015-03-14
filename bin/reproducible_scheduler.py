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
import gzip
import deb822
import aptsources.sourceslist
import random
from time import sleep
from random import randint
from subprocess import call
from apt_pkg import version_compare
from urllib.request import urlopen

from reproducible_common import *
from reproducible_html_indexes import build_page
from reproducible_html_packages import gen_packages_html
from reproducible_html_packages import purge_old_pages

def call_apt_update(suite):
    # try three times, before failing the job
    for i in [1, 2, 3]:
        if not call(['schroot', '--directory', '/root', '-u', 'root', \
                     '-c', 'source:jenkins-reproducible-'+suite, '--', \
                     'apt-get', 'update']):
            return
        else:
            log.warning('`apt-get update` failed. Retrying another ' + str(3-i)
                        + ' times.')
            sleep(randint(1, 70) + 30)
    print_critical_message('`apt-get update` for suite ' + suite +
                           ' failed three times in a row, giving up.')
    sys.exit(1)


def update_sources_tables(suite):
    # download the sources file for this suite
    mirror = 'http://ftp.de.debian.org/debian'
    remotefile = mirror + '/dists/' + suite + '/main/source/Sources.gz'
    log.info('Downloading sources file for ' + suite + ': ' + remotefile)
    sources = gzip.decompress(urlopen(remotefile).read()).decode('utf8')
    log.debug('\tdownloaded')
    # extract relevant info (package name and version) from the sources file
    new_pkgs = []
    for src in deb822.Sources.iter_paragraphs(sources.split('\n')):
        pkg = (src['Package'], src['Version'], suite)
        new_pkgs.append(pkg)
    # get the current packages in the database
    query = 'SELECT name, version, suite FROM sources ' + \
            'WHERE suite="{}"'.format(suite)
    cur_pkgs = query_db(query)
    pkgs_to_add = []
    updated_pkgs = []
    different_pkgs = [x for x in new_pkgs if x not in cur_pkgs]
    log.debug('Packages different in the archive and in the db: ' +
              str(different_pkgs))
    for pkg in different_pkgs:
        query = 'SELECT id, version FROM sources ' + \
                'WHERE name="{name}" AND suite="{suite}"'
        query = query.format(name=pkg[0], suite=pkg[2])
        try:
            result = query_db(query)[0]
        except IndexError:  # new package
            pkgs_to_add.append((pkg[0], pkg[1], pkg[2], 'amd64'))
            continue
        pkg_id = result[0]
        old_version = result[1]
        if version_compare(pkg[1], old_version) > 0:
            log.debug('New version: ' + str(pkg) + ' (we had  ' +
                      old_version + ')')
            updated_pkgs.append((pkg_id, pkg[0], pkg[1], pkg[2]))
    # Now actually update the database:
    cursor = conn_db.cursor()
    # updated packages
    log.info('Pushing ' + str(len(updated_pkgs)) + ' updated packages to the database...')
    cursor.executemany('REPLACE INTO sources ' +
                       '(id, name, version, suite, architecture) ' +
                       'VALUES (?, ?, ?, ?, "{arch}")'.format(arch='amd64'),
                       updated_pkgs)
    conn_db.commit()
    # new packages
    log.info('Now inserting ' + str(len(pkgs_to_add)) + ' new sources in the database: ' +
             str(pkgs_to_add))
    cursor.executemany('INSERT INTO sources ' +
                       '(name, version, suite, architecture) ' +
                       'VALUES (?, ?, ?, ?)', pkgs_to_add)
    conn_db.commit()
    # RM'ed packages
    cur_pkgs_name = [x[0] for x in cur_pkgs]
    new_pkgs_name = [x[0] for x in new_pkgs]
    rmed_pkgs = [x for x in cur_pkgs_name if x not in new_pkgs_name]
    log.info('Now deleting ' + str(len(rmed_pkgs)) + ' removed packages: ' + str(rmed_pkgs))
    rmed_pkgs_id = []
    for pkg in rmed_pkgs:
        result = query_db(('SELECT id FROM sources ' +
                          'WHERE name="{name}" ' +
                          'AND suite="{suite}"').format(name=pkg, suite=suite))
        rmed_pkgs_id.extend(result)
    log.debug('removed packages ID: ' + str([str(x[0]) for x in rmed_pkgs_id]))
    cursor.executemany('DELETE FROM sources ' +
                       'WHERE id=?', rmed_pkgs_id)
    cursor.executemany('DELETE FROM results ' +
                       'WHERE package_id=?', rmed_pkgs_id)
    cursor.executemany('DELETE FROM schedule ' +
                       'WHERE package_id=?', rmed_pkgs_id)
    conn_db.commit()
    # finally check whether the db has the correct number of packages
    pkgs_end = query_db('SELECT count(*) FROM sources WHERE suite="%s"' % suite)
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
        gen_packages_html(pkgs_to_add, no_clean=True)


def print_schedule_result(suite, criteria, packages):
    '''
    `packages` is the usual list-of-tuples returned by SQL queries,
    where the first item is the id and the second one the package name
    '''
    log.info('--------------------------------------------------------------')
    log.info('Criteria: ' + criteria)
    log.info('Suite:    ' + suite)
    log.info('Amount:   ' + str(len(packages)))
    log.info('Packages: ' + ' '.join([x[1] for x in packages]))


def schedule_packages(packages, date):
    date = date.strftime('%Y-%m-%d %H:%M')
    pkgs = [(x[0], date) for x in packages]
    log.debug('IDs about to be scheduled: ' + str([x[0] for x in packages]))
    query = 'INSERT INTO schedule ' + \
            '(package_id, date_scheduled, date_build_started) ' + \
            'VALUES (?, ?, "")'
    cursor = conn_db.cursor()
    cursor.executemany(query, pkgs)
    conn_db.commit()
    log.info('--------------------------------------------------------------')
    log.info('The following ' + str(len(pkgs)) + ' source packages have ' +
             'been scheduled at ' + date + ': ' + ' '.join([str(x[1]) for x in packages]))
    log.info('--------------------------------------------------------------')


def scheduler_untested_packages(suite, limit):
    criteria = 'not tested before, randomly sorted'
    query = """SELECT DISTINCT sources.id, sources.name FROM sources
               WHERE sources.suite='{suite}'
               AND sources.id NOT IN
                       (SELECT schedule.package_id FROM schedule)
               AND sources.id NOT IN
                       (SELECT results.package_id FROM results)
               ORDER BY random()
               LIMIT {limit}""".format(suite=suite, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, criteria, packages)
    return packages


def scheduler_new_versions(suite, limit):
    criteria = 'tested before, new version available, sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name
               FROM sources AS s JOIN results AS r ON s.id = r.package_id
               WHERE s.suite='{suite}'
               AND s.version != r.version
               AND r.status != 'blacklisted'
               AND s.id IN (SELECT package_id FROM results)
               AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
               ORDER BY r.build_date
               LIMIT {limit}""".format(suite=suite, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, criteria, packages)
    return packages


def scheduler_old_versions(suite, limit):
    criteria = 'tested at least two weeks ago, no new version available, ' + \
               'sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                WHERE s.suite='{suite}'
                AND r.version = s.version
                AND r.status != 'blacklisted'
                AND r.build_date < datetime('now', '-14 day')
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                ORDER BY r.build_date
                LIMIT {limit}""".format(suite=suite, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, criteria, packages)
    return packages


def scheduler():
    query = 'SELECT count(*) ' + \
            'FROM schedule AS p JOIN sources AS s ON p.package_id=s.id '
    total = int(query_db(query)[0][0])
    log.info('Currently scheduled packages in all suites: ' + str(total))
    if total > 250:
        build_page('scheduled')  # from reproducible_html_indexes
        log.info(str(total) + ' packages already scheduled' +
                 ', nothing to do here.')
        return
    else:
        log.info(str(total) + ' packages already scheduled' +
                 ', scheduling some more...')
        log.info('==============================================================')
    # untested packages
    untested = {}
    for suite in SUITES:
        log.info('Requesting 250 untested packages in ' + suite + '...')
        untested[suite] = scheduler_untested_packages(suite, 250)
        total += len(untested[suite])
        log.info('Received ' + str(len(untested[suite])) + ' untested packages in ' + suite + ' to schedule.')
    log.info('==============================================================')

    # packages with new versions
    new = {}
    if total <= 100:
        many_new = 100
    elif total <= 200:
        many_new = 75
    else:
        many_new = 50
    log.info('Requesting ' + str(many_new) + ' new versions in ' + suite + '...')
    for suite in SUITES:
        new[suite] = scheduler_new_versions(suite, many_new)
        total += len(new[suite])
        log.info('Received ' + str(len(new[suite])) + ' new packages in ' + suite + ' to schedule.')
    log.info('==============================================================')

    # old packages
    old = {}
    if total <= 250:
        many_old = 25 # multiplied by 10, usually, see below
    elif total <= 350:
        many_old = 17 # also...
    elif total <= 450:
        many_old = 10 # ...
    else:
        many_old = 1  # ...
    for suite in SUITES:
        if suite != 'experimental':
            many_old = many_old*10 # experimental is roughly one tenth of the size of the other suites
        log.info('Requesting ' + str(many_old) + ' old packages in ' + suite + '...')
        old[suite] = scheduler_old_versions(suite, many_old)
        total += len(old[suite])
        log.info('Received ' + str(len(old[suite])) + ' old packages in ' + suite + ' to schedule.')
    log.info('==============================================================')

    now_queued_here = {}
    for suite in SUITES:
        query = 'SELECT count(*) ' + \
                'FROM schedule AS p JOIN sources AS s ON p.package_id=s.id ' + \
                'WHERE s.suite="{suite}"'.format(suite=suite)
        now_queued_here[suite] = int(query_db(query)[0][0]) + len(untested[suite]+new[suite]+old[suite])
        # schedule packages differently in the queue...
        schedule_packages(untested[suite], datetime.datetime.now())
        schedule_packages(new[suite], datetime.datetime.now()+datetime.timedelta(minutes=-720))
        schedule_packages(old[suite], datetime.datetime.now()+datetime.timedelta(minutes=720))
        log.info('### Suite ' + suite + ' done ###')
        log.info('==============================================================')
    # update the scheduled page
    build_page('scheduled')  # from reproducible_html_indexes, build global page
    # build the kgb message text
    message = 'Scheduled in ' + '+'.join(SUITES) + ': ' + \
              '+'.join([str(len(untested[x])) for x in SUITES]) + ' new and untested packages, ' + \
              '+'.join([str(len(new[x])) for x in SUITES]) + ' packages with new versions and ' + \
              '+'.join([str(len(old[x])) for x in SUITES]) + ' old packages with the same version, ' + \
              'for ' + str(total) + ' or ' + \
              '+'.join([str(now_queued_here[x]) for x in SUITES]) + ' packages in total.'
    log.info(message)
    kgb = ['kgb-client', '--conf', '/srv/jenkins/kgb/debian-reproducible.conf',
           '--relay-msg']
    kgb.extend(message.split())
    call(kgb)
    log.info('\n\n\n')
    log.info(message)


if __name__ == '__main__':
    log.info('Updating schroots and sources tables for all suites.')
    for suite in SUITES:
        call_apt_update(suite)
        update_sources_tables(suite)
    purge_old_pages()
    try:
        overall = int(query_db('SELECT count(*) FROM schedule')[0][0])
    except:
        overall = 9999
    if overall > 250:
        log.info(str(overall) + ' packages already scheduled, nothing to do.')
        sys.exit()
    log.info(str(overall) + ' packages already scheduled, scheduling some more...')
    scheduler()
