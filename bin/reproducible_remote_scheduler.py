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
import os
import re
import sys
import time
from sqlalchemy import sql
from reproducible_common import (
    # Use an explicit list rather than a star import, because the previous code had
    # a mysterious comment about not being able to do a star import prior to
    # parsing the command line, & debugging the mystery via edit-compile-h01ger-run
    # detours is not practical.
    SUITES, ARCHS,
    bcolors,
    query_db, db_table, sql, conn_db,
    datetime, timedelta,
    irc_msg,
)
from reproducible_common import log

def packages_matching_criteria(arch, suite, criteria):
    "Return a list of packages in (SUITE, ARCH) matching the given CRITERIA."
    # TODO: Rewrite this function to query all suites/archs in one go
    issue, status, built_after, built_before = criteria
    del criteria

    formatter = dict(suite=suite, arch=arch, notes_table='')
    log.info('Querying packages with given issues/status...')
    query = "SELECT s.name " + \
            "FROM sources AS s, {notes_table} results AS r " + \
            "WHERE r.package_id=s.id " + \
            "AND s.architecture= '{arch}' " + \
            "AND s.suite = '{suite}' AND r.status != 'blacklisted' "
    if issue:
        query += "AND n.package_id=s.id AND n.issues LIKE '%%{issue}%%' "
        formatter['issue'] = issue
        formatter['notes_table'] = "notes AS n,"
    if status:
        query += "AND r.status = '{status}'"
        formatter['status'] = status
    if built_after:
        query += "AND r.build_date > '{built_after}' "
        formatter['built_after'] = built_after
    if built_before:
        query += "AND r.build_date < '{built_before}' "
        formatter['built_before'] = built_before
    results = query_db(query.format_map(formatter))
    results = [x for (x,) in results]
    log.info('Selected packages: ' + ' '.join(results))
    return results

def parse_args():
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
                        'considered null-separated and coming from stdin.')
    parser.add_argument('-k', '--keep-artifacts',  action='store_true',
                       help='Save artifacts (for further offline study).')
    parser.add_argument('-n', '--notify', action='store_true',
                       help='Notify the channel when the build finishes.')
    parser.add_argument('-d', '--noisy', action='store_true', help='Also notify when ' +
                        'the build starts, linking to the build url.')
    parser.add_argument('-m', '--message', default='',
                        help='A text to be sent to the IRC channel when notifying' +
                        ' about the scheduling.')
    parser.add_argument('-r', '--status', required=False,
                        help='Schedule all package with this status.')
    parser.add_argument('-i', '--issue', required=False,
                        help='Schedule all packages with this issue.')
    parser.add_argument('-t', '--after', required=False,
                        help='Schedule all packages built after this date.')
    parser.add_argument('-b', '--before', required=False,
                        help='Schedule all packages built before this date.')
    parser.add_argument('-a', '--architecture', required=False, default='amd64',
                        help='Specify the architectures to schedule in ' +
                        '(space or comma separated).' +
                        "Default: 'amd64'.")
    parser.add_argument('-s', '--suite', required=False, default='unstable',
                        help="Specify the suites to schedule in (space or comma separated). Default: 'unstable'.")
    parser.add_argument('packages', metavar='package', nargs='*',
                        help='Space seperated list of packages to reschedule.')
    scheduling_args = parser.parse_known_args()[0]
    if scheduling_args.null:
        scheduling_args = parser.parse_known_args(sys.stdin.read().split('\0'))[0]
    scheduling_args.packages = [x for x in scheduling_args.packages if x]
    if scheduling_args.noisy:
        scheduling_args.notify = True

    # this variable is expected to come from the remote host
    try:
        requester = os.environ['LC_USER']
    except KeyError:
        log.critical(bcolors.FAIL + 'You should use the provided script to '
                     'schedule packages. Ask in #debian-reproducible if you have '
                     'trouble with that.' + bcolors.ENDC)
        sys.exit(1)

    # this variable is set by reproducible scripts and so it only available in calls made on the local host (=main node)
    try:
        local = True if os.environ['LOCAL_CALL'] == 'true' else False
    except KeyError:
        local = False

    # Shorter names
    suites = [x.strip() for x in re.compile(r'[, \t]').split(scheduling_args.suite or "")]
    suites = [x for x in suites if x]
    archs = [x.strip() for x in re.compile(r'[, \t]').split(scheduling_args.architecture or "")]
    archs = [x for x in archs if x]
    reason = scheduling_args.message
    issue = scheduling_args.issue
    status = scheduling_args.status
    built_after = scheduling_args.after
    built_before = scheduling_args.before
    packages = scheduling_args.packages
    artifacts = scheduling_args.keep_artifacts
    notify = scheduling_args.notify
    notify_on_start = scheduling_args.noisy
    dry_run = scheduling_args.dry_run

    log.debug('Requester: ' + requester)
    log.debug('Dry run: ' + str(dry_run))
    log.debug('Local call: ' + str(local))
    log.debug('Reason: ' + reason)
    log.debug('Artifacts: ' + str(artifacts))
    log.debug('Notify: ' + str(notify))
    log.debug('Debug url: ' + str(notify_on_start))
    log.debug('Issue: ' + issue if issue else str(None))
    log.debug('Status: ' + status if status else str(None))
    log.debug('Date: after ' + built_after if built_after else str(None) +
              ' before ' + built_before if built_before else str(None))
    log.debug('Suites: ' + repr(suites))
    log.debug('Architectures: ' + repr(archs))
    log.debug('Packages: ' + ' '.join(packages))

    if not suites[0]:
        log.critical('You need to specify the suite name')
        sys.exit(1)

    if set(suites) - set(SUITES): # Some command-line suites don't exist.
        log.critical('Some of the specified suites %r are not being tested.', suites)
        log.critical('Please choose among ' + ', '.join(SUITES) + '.')
        sys.exit(1)

    if set(archs) - set(ARCHS): # Some command-line archs don't exist.
        log.critical('Some of the specified archs %r are not being tested.', archs)
        log.critical('Please choose among' + ', '.join(ARCHS) + '.')
        sys.exit(1)

    if issue or status or built_after or built_before:
        # Note: this .extend() operation modifies scheduling_args.packages, which
        #       is used by rest()
        for suite in suites:
            for arch in archs:
                packages.extend(
                  packages_matching_criteria(
                    arch,
                    suite,
                    (issue, status, built_after, built_before),
                  )
                )
            del arch
        del suite

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

    if notify_on_start:
        log.info('The channel will be notified when the build starts')

    return scheduling_args, requester, local, suites, archs

def rest(scheduling_args, requester, local, suite, arch):
    "Actually schedule a package for a single suite on a single arch."

    # Shorter names
    reason = scheduling_args.message
    issue = scheduling_args.issue
    status = scheduling_args.status
    built_after = scheduling_args.after
    built_before = scheduling_args.before
    packages = scheduling_args.packages
    artifacts = scheduling_args.keep_artifacts
    notify = scheduling_args.notify
    notify_on_start = scheduling_args.noisy
    dry_run = scheduling_args.dry_run

    log.info("Scheduling packages in %s/%s", arch, suite)

    ids = []
    pkgs = []

    query1 = """SELECT id FROM sources WHERE name='{pkg}' AND suite='{suite}'
                AND architecture='{arch}'"""
    query2 = """SELECT p.date_build_started
                FROM sources AS s JOIN schedule as p ON p.package_id=s.id
                WHERE p.package_id='{id}'"""
    for pkg in set(packages):
        # test whether the package actually exists
        result = query_db(query1.format(pkg=pkg, suite=suite, arch=arch))
        # tests whether the package is already building
        try:
            result2 = query_db(query2.format(id=result[0][0]))
        except IndexError:
            log.error('%sThe package %s is not available in %s/%s%s',
                  bcolors.FAIL, pkg, suite, arch, bcolors.ENDC)
            continue
        try:
            if not result2[0][0]:
                ids.append(result[0][0])
                pkgs.append(pkg)
            else:
                log.warning(bcolors.WARN + 'The package ' + pkg + ' is ' +
                    'already building, not scheduling it.' + bcolors.ENDC)
        except IndexError:
            # it's not in the schedule
            ids.append(result[0][0])
            pkgs.append(pkg)

    def compose_irc_message():
        "One-shot closure to limit scope of the following local variables."
        blablabla = '✂…' if len(' '.join(pkgs)) > 257 else ''
        packages_txt = str(len(ids)) + ' packages ' if len(pkgs) > 1 else ''
        trailing = ' - artifacts will be preserved' if artifacts else ''
        trailing += ' - with irc notification' if notify else ''
        trailing += ' - notify on start too' if notify_on_start else ''

        message = requester + ' scheduled ' + packages_txt + \
            'in ' + suite + '/' + arch
        if reason:
            message += ', reason: \'' + reason + '\''
        message += ': ' + ' '.join(pkgs)[0:256] + blablabla + trailing
        return message
    message = compose_irc_message()
    del compose_irc_message

    # these packages are manually scheduled, so should have high priority,
    # so schedule them in the past, so they are picked earlier :)
    # the current date is subtracted twice, so it sorts before early scheduling
    # schedule on the full hour so we can recognize them easily
    epoch = int(time.time())
    now = datetime.now()
    days = int(now.strftime('%j'))*2
    hours = int(now.strftime('%H'))*2
    minutes = int(now.strftime('%M'))
    time_delta = timedelta(days=days, hours=hours, minutes=minutes)
    date = (now - time_delta).strftime('%Y-%m-%d %H:%M')
    log.debug('date_scheduled = ' + date + ' time_delta = ' + str(time_delta))


    # a single person can't schedule more than 500 packages in the same day; this
    # is actually easy to bypass, but let's give some trust to the Debian people
    query = """SELECT count(*) FROM manual_scheduler
               WHERE requester = '{}' AND date_request > '{}'"""
    try:
        amount = int(query_db(query.format(requester, int(time.time()-86400)))[0][0])
    except IndexError:
        amount = 0
    log.debug(requester + ' already scheduled ' + str(amount) + ' packages today')
    if amount + len(ids) > 500 and not local:
        log.error(bcolors.FAIL + 'You have exceeded the maximum number of manual ' +
                  'reschedulings allowed for a day. Please ask in ' +
                  '#debian-reproducible if you need to schedule more packages.' +
                  bcolors.ENDC)
        sys.exit(1)


    # do the actual scheduling
    add_to_schedule = []
    update_schedule = []
    save_schedule = []
    artifacts_value = 1 if artifacts else 0
    if notify_on_start:
        do_notify = 2
    elif notify or artifacts:
        do_notify = 1
    else:
        do_notify = 0

    schedule_table = db_table('schedule')
    if ids:
        existing_pkg_ids = dict(query_db(sql.select([
            schedule_table.c.package_id,
            schedule_table.c.id,
        ]).where(schedule_table.c.package_id.in_(ids))))

    for id in ids:
        if id in existing_pkg_ids:
            update_schedule.append({
                'update_id': existing_pkg_ids[id],
                'package_id': id,
                'date_scheduled': date,
                'save_artifacts': artifacts_value,
                'notify': str(do_notify),
                'scheduler': requester,
            })
        else:
            add_to_schedule.append({
                'package_id': id,
                'date_scheduled': date,
                'save_artifacts': artifacts_value,
                'notify': str(do_notify),
                'scheduler': requester,
            })

        save_schedule.append({
            'package_id': id,
            'requester': requester,
            'date_request': epoch,
        })

    log.debug('Packages about to be scheduled: ' + str(add_to_schedule)
              + str(update_schedule))

    update_schedule_query = schedule_table.update().\
                            where(schedule_table.c.id == sql.bindparam('update_id'))
    insert_schedule_query = schedule_table.insert()
    insert_manual_query = db_table('manual_scheduler').insert()

    if not dry_run:
        transaction = conn_db.begin()
        if add_to_schedule:
            conn_db.execute(insert_schedule_query, add_to_schedule)
        if update_schedule:
            conn_db.execute(update_schedule_query, update_schedule)
        if save_schedule:
            conn_db.execute(insert_manual_query, save_schedule)
        transaction.commit()
    else:
        log.info('Ran with --dry-run, scheduled nothing')

    log.info(bcolors.GOOD + message + bcolors.ENDC)
    if not (local and requester == "jenkins maintenance job") and len(ids) != 0:
        if not dry_run:
            irc_msg(message)

    from reproducible_html_live_status import generate_schedule
    generate_schedule(arch)  # update the HTML page

def main():
    scheduling_args, requester, local, suites, archs = parse_args()
    for suite in suites:
        for arch in archs:
            rest(scheduling_args, requester, local, suite, arch)
        del arch
    del suite

if __name__ == '__main__':
    main()
