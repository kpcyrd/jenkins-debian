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
from reproducible_html_indexes import generate_schedule
from reproducible_html_packages import gen_packages_html
from reproducible_html_packages import purge_old_pages

def call_apt_update(suite):
    # try three times, before failing the job
    for i in [1, 2, 3]:
        to_call =['schroot', '--directory', '/root', '-u', 'root', \
                  '-c', 'source:jenkins-reproducible-'+suite, '--', \
                  'apt-get', 'update']
        log.debug('calling ' + ' '.join(to_call))
        if not call(to_call):
            return
        else:
            log.warning('`apt-get update` failed. Retrying another ' + str(3-i)
                        + ' times.')
            sleep(randint(1, 70) + 30)
    print_critical_message('`apt-get update` for suite ' + suite +
                           ' failed three times in a row, giving up.')
    sys.exit(1)


def update_sources(suite):
    # download the sources file for this suite
    mirror = 'http://ftp.de.debian.org/debian'
    remotefile = mirror + '/dists/' + suite + '/main/source/Sources.xz'
    log.info('Downloading sources file for %s: %s', suite, remotefile)
    sources = lzma.decompress(urlopen(remotefile).read()).decode('utf8')
    log.debug('\tdownloaded')
    for arch in ARCHS:
        log.info('Updating sources for %s/%s...', suite, arch)
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
    cursor.executemany('DELETE FROM sources ' +
                       'WHERE id=?', rmed_pkgs_id)
    cursor.executemany('DELETE FROM results ' +
                       'WHERE package_id=?', rmed_pkgs_id)
    cursor.executemany('DELETE FROM schedule ' +
                       'WHERE package_id=?', rmed_pkgs_id)
    cursor.executemany('INSERT INTO removed_packages '  +
                       '(name, suite, architecture) ' +
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


def queue_packages(all_pkgs, packages, date):
    date = date.strftime('%Y-%m-%d %H:%M')
    pkgs = [x for x in packages if x[0] not in all_pkgs]
    log.info('--------------------------------------------------------------')
    log.info('The following ' + str(len(pkgs)) + ' source packages have ' +
             'been queued up for scheduling at ' + date + ': ' +
             ' '.join([str(x[1]) for x in pkgs]))
    log.info('--------------------------------------------------------------')
    all_pkgs.update({x[0]: date for x in pkgs})
    return all_pkgs


def schedule_packages(packages):
    pkgs = ((x, packages[x]) for x in packages)
    log.debug('IDs about to be scheduled: ' + str(x[0] for x in pkgs))
    query = 'INSERT INTO schedule ' + \
            '(package_id, date_scheduled, date_build_started) ' + \
            'VALUES (?, ?, "")'
    cursor = conn_db.cursor()
    cursor.executemany(query, pkgs)
    conn_db.commit()


def add_up_numbers(package_type):
    package_type_sum = '+'.join([str(len(package_type[x])) for x in SUITES])
    if package_type_sum == '0+0+0':
        package_type_sum = '0'
    return package_type_sum


def query_untested_packages(suite, limit):
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


def query_new_versions(suite, limit):
    criteria = 'tested before, new version available, sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name, s.version, r.version
               FROM sources AS s JOIN results AS r ON s.id = r.package_id
               WHERE s.suite='{suite}'
               AND s.version != r.version
               AND r.status != 'blacklisted'
               AND s.id IN (SELECT package_id FROM results)
               AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
               ORDER BY r.build_date
               LIMIT {limit}""".format(suite=suite, limit=limit)
    pkgs = query_db(query)
    # this is to avoid costant rescheduling of packages in our exp repository
    packages = [(x[0], x[1]) for x in pkgs if version_compare(x[2], x[3]) > 0]
    print_schedule_result(suite, criteria, packages)
    return packages


def query_old_ftbfs_versions(suite, limit):
    criteria = 'status ftbfs, no bug filed, tested at least ten days ago, ' + \
               'no new version available, sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                JOIN notes AS n ON n.package_id=s.id
                WHERE s.suite='{suite}'
                AND r.status = 'FTBFS'
                AND ( n.bugs = '[]' OR n.bugs IS NULL )
                AND r.build_date < datetime('now', '-10 day')
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                ORDER BY r.build_date
                LIMIT {limit}""".format(suite=suite, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, criteria, packages)
    return packages


def query_old_versions(suite, limit):
    criteria = 'tested at least two weeks ago, no new version available, ' + \
               'sorted by last build date'
    query = """SELECT DISTINCT s.id, s.name
                FROM sources AS s JOIN results AS r ON s.id = r.package_id
                WHERE s.suite='{suite}'
                AND r.status != 'blacklisted'
                AND r.build_date < datetime('now', '-14 day')
                AND s.id NOT IN (SELECT schedule.package_id FROM schedule)
                ORDER BY r.build_date
                LIMIT {limit}""".format(suite=suite, limit=limit)
    packages = query_db(query)
    print_schedule_result(suite, criteria, packages)
    return packages


def schedule_untested_packages(total):
    packages = {}
    for suite in SUITES:
        log.info('Requesting 444 untested packages in ' + suite + '...')
        packages[suite] = query_untested_packages(suite, 444)
        log.info('Received ' + str(len(packages[suite])) +
                 ' untested packages in ' + suite + ' to schedule.')
    log.info('==============================================================')
    if add_up_numbers(packages) != '0':
        msg = add_up_numbers(packages) + ' new packages'
    else:
        msg = ''
    return packages, msg


def schedule_new_versions(total):
    packages = {}
    if total <= 100:
        many_new = 250
    elif total <= 200:
        many_new = 200
    else:
        many_new = 150
    for suite in SUITES:
        log.info('Requesting ' + str(many_new) + ' new versions in ' + suite + '...')
        packages[suite] = query_new_versions(suite, many_new)
        log.info('Received ' + str(len(packages[suite])) + ' new packages in ' + suite + ' to schedule.')
    log.info('==============================================================')
    if add_up_numbers(packages) != '0':
        msg = add_up_numbers(packages) + ' with new versions'
    else:
        msg = ''
    return packages, msg


def schedule_old_ftbfs_versions(total):
    packages = {}
    if total <= 250:
        old_ftbfs = 42
    elif total <= 350:
        old_ftbfs = 23
    else:
        old_ftbfs = 0
    for suite in SUITES:
        if suite == 'experimental':
            old_ftbfs = 0  # experiemental rarely get's fixed over time...
        log.info('Requesting ' + str(old_ftbfs) + ' old ftbfs packages in ' + suite + '...')
        packages[suite] = query_old_ftbfs_versions(suite, old_ftbfs)
        log.info('Received ' + str(len(packages[suite])) + ' old ftbfs packages in ' + suite + ' to schedule.')
    log.info('==============================================================')
    if add_up_numbers(packages) != '0':
        msg = add_up_numbers(packages) + ' ftbfs versions without bugs filed'
    else:
        msg = ''
    return packages, msg


def schedule_old_versions(total):
    packages = {}
    if total <= 300:
        many_old_base = 35 # multiplied by 20 or 10 or 1, see below
    elif total <= 400:
        many_old_base = 25 # also...
    else:
        many_old_base = 0  # ...
    for suite in SUITES:
        if suite == 'unstable':
            suite_many_old = int(many_old_base*5) # unstable changes the most and is most relevant ### was 20, lowered due to gcc5 transition
        elif suite == 'testing':
            suite_many_old = int(many_old_base*25)  # re-schedule testing less than unstable as we care more more about unstable (atm) ### was 10, raised due to gcc5...
        else:
            suite_many_old = int(many_old_base)    # experimental is roughly one twentieth of the size of the other suites
        log.info('Requesting ' + str(suite_many_old) + ' old packages in ' + suite + '...')
        packages[suite] = query_old_versions(suite, suite_many_old)
        log.info('Received ' + str(len(packages[suite])) + ' old packages in ' + suite + ' to schedule.')
    log.info('==============================================================')
    if add_up_numbers(packages) != '0':
        msg = add_up_numbers(packages) + ' known versions'
    else:
        msg = ''
    return packages, msg


def scheduler():
    query = 'SELECT count(*) ' + \
            'FROM schedule AS p JOIN sources AS s ON p.package_id=s.id '
    total = int(query_db(query)[0][0])
    log.info('Currently scheduled packages in all suites: ' + str(total))
    if total > 750:
        generate_schedule()  # from reproducible_html_indexes
        log.info(str(total) + ' packages already scheduled' +
                 ', nothing to do here.')
        return
    else:
        log.info(str(total) + ' packages already scheduled' +
                 ', scheduling some more...')
        log.info('==============================================================')
    untested, msg_untested = schedule_untested_packages(total)
    new, msg_new  = schedule_new_versions(total+len(untested))
    old_ftbfs, msg_old_ftbfs  = schedule_old_ftbfs_versions(total+len(untested)+len(new))
    old, msg_old  = schedule_old_versions(total+len(untested)+len(new)+len(old_ftbfs))

    now_queued_here = {}
    # make sure to schedule packages in unstable first
    # (but keep the view ordering everywhere else)
    priotized_suite_order = ['unstable']
    for suite in SUITES:
        if suite not in priotized_suite_order:
            priotized_suite_order.append(suite)
    for suite in priotized_suite_order:
        query = 'SELECT count(*) ' + \
                'FROM schedule AS p JOIN sources AS s ON p.package_id=s.id ' + \
                'WHERE s.suite="{suite}"'.format(suite=suite)
        now_queued_here[suite] = int(query_db(query)[0][0]) + \
                        len(untested[suite]+new[suite]+old[suite])
        # schedule packages differently in the queue...
        to_be_scheduled = queue_packages({}, untested[suite], datetime.now())
        assert(isinstance(to_be_scheduled, dict))
        to_be_scheduled = queue_packages(to_be_scheduled, new[suite], datetime.now()+timedelta(minutes=-720))
        to_be_scheduled = queue_packages(to_be_scheduled, old_ftbfs[suite], datetime.now()+timedelta(minutes=360))
        to_be_scheduled = queue_packages(to_be_scheduled, old[suite], datetime.now()+timedelta(minutes=720))
        schedule_packages(to_be_scheduled)
        log.info('### Suite ' + suite + ' done ###')
        log.info('==============================================================')
    # update the scheduled page
    generate_schedule()  # from reproducible_html_indexes
    # build the kgb message text
    message = 'Scheduled in ' + '+'.join(SUITES) + ': '
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
    message += ', for ' + str(sum(total)) + ' or ' + \
              '+'.join([str(now_queued_here[x]) for x in SUITES]) + ' packages in total.'
    log.info('\n\n\n')
    log.info(message)
    # only notifiy irc if there were packages scheduled in any suite
    for x in SUITES:
        if len(untested[x])+len(new[x])+len(old[x]) > 0:
            irc_msg(message)
            break


if __name__ == '__main__':
    log.info('Updating schroots and sources tables for all suites.')
    for suite in SUITES:
        call_apt_update(suite)
        update_sources(suite)
    purge_old_pages()
    try:
        overall = int(query_db('SELECT count(*) FROM schedule')[0][0])
    except:
        overall = 9999
    if overall > 750:
        log.info(str(overall) + ' packages already scheduled, nothing to do.')
        sys.exit()
    log.info(str(overall) + ' packages already scheduled, scheduling some more...')
    scheduler()
