#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build a page full of CI issues to investigate

from reproducible_common import *


def unrep_with_dbd_issues():
    log.info('running unrep_with_dbd_issues check...')
    without_dbd = []
    bad_dbd = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status="unreproducible"
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + pkg + '_' + \
            eversion + '.debbindiff.html'
        if not os.access(dbd, os.R_OK):
            without_dbd.append((pkg, version, suite, arch))
            log.warning(pkg + '/' + suite + ' (' + version + ') is '
                        'unreproducible without diffoscope file.')
        else:
            log.debug(dbd + ' found.')
            data = open(dbd, 'br').read(3)
            if b'<' not in data:
                bad_dbd.append((pkg, version, suite, arch))
                log.warning(pkg + '/' + suite + ' (' + version + ') has '
                            'diffoscope output, but it does not seem to '
                            'be an html page.')
    return without_dbd, bad_dbd


def not_unrep_with_dbd_file():
    log.info('running not_unrep_with_dbd_file check...')
    bad_pkgs = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status != "unreproducible"
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + pkg + '_' + \
            eversion + '.debbindiff.html'
        if os.access(dbd, os.R_OK):
            bad_pkgs.append((pkg, version, suite, arch))
            log.warning(pkg + '/' + suite + ' (' + version + ') has a '
                        'diffoscope file but it\'s not unreproducible.')
    return bad_pkgs


def lack_rbuild():
    log.info('running lack_rbuild check...')
    bad_pkgs = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status NOT IN ("blacklisted", "")
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        if not pkg_has_rbuild(pkg, version, suite, arch):
            bad_pkgs.append((pkg, version, suite, arch))
            log.warning(pkg + '/' + suite + ' (' + version + ') has been '
                        'built, but a buildlog is missing.')
    return bad_pkgs


def lack_buildinfo():
    log.info('running lack_buildinfo check...')
    bad_pkgs = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status NOT IN
                ("blacklisted", "not for us", "FTBFS", "depwait", "404", "")
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        buildinfo = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + pkg + \
            '_' + eversion + '_' + arch + '.buildinfo'
        if not os.access(buildinfo, os.R_OK):
            bad_pkgs.append((pkg, version, suite, arch))
            log.warning(pkg + '/' + suite + ' (' + version + ') has been '
                        'successfully built, but a .buildinfo is missing')
    return bad_pkgs


def pbuilder_dep_fail():
    log.info('running pbuilder_dep_fail check...')
    bad_pkgs = []
    # we only care about these failures in the testing suite as they happen
    # all the time in other suites, as packages are buggy
    # and specific versions also come and go
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status = "FTBFS" AND s.suite = "testing"
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        rbuild = RBUILD_PATH + '/' + suite + '/' + arch + '/' + pkg + '_' + \
            eversion + '.rbuild.log'
        if os.access(rbuild, os.R_OK):
            log.debug('\tlooking at ' + rbuild)
            with open(rbuild, "br") as fd:
                for line in fd:
                    if re.search(b'E: pbuilder-satisfydepends failed.', line):
                        bad_pkgs.append((pkg, version, suite, arch))
                        log.warning(pkg + '/' + suite + ' (' + version +
                                    ') failed to met its dependencies.')
    return bad_pkgs


def alien_log(directory=None):
    if directory is None:
        bad_files = []
        for path in RBUILD_PATH, LOGS_PATH, DIFFS_PATH:
            bad_files.extend(alien_log(path))
        return bad_files
    log.info('running alien_log check over ' + directory + '...')
    query = '''SELECT s.name
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status != "" AND s.name="{pkg}" AND s.suite="{suite}"
               AND s.architecture="{arch}"
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    bad_files = []
    for root, dirs, files in os.walk(directory):
        if not files:
            continue
        suite, arch = root.rsplit('/', 2)[1:]
        for file in files:
            try:
                pkg, version = file.rsplit('.', 2)[0].rsplit('_', 1)
            except ValueError:
                log.critical(bcolors.FAIL + '/'.join([root, file]) +
                             ' does not seem to be a file that should be there'
                             + bcolors.ENDC)
                continue
            if not query_db(query.format(pkg=pkg, suite=suite, arch=arch)):
                bad_files.append('/'.join([root, file]))
                log.warning('/'.join([root, file]) + ' should not be there')
    return bad_files


def alien_buildinfo():
    log.info('running alien_log check...')
    query = '''SELECT s.name
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status != "" AND s.name="{pkg}" AND s.suite="{suite}"
               AND s.architecture="{arch}"
               AND r.status IN ("reproducible", "unreproducible")
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    bad_files = []
    for root, dirs, files in os.walk(BUILDINFO_PATH):
        if not files:
            continue
        suite, arch = root.rsplit('/', 2)[1:]
        for file in files:
            try:
                pkg, version = file.rsplit('.', 1)[0].split('_')[:2]
            except ValueError:
                log.critical(bcolors.FAIL + '/'.join([root, file]) +
                             ' does not seem to be a file that should be there'
                             + bcolors.ENDC)
                continue
            if not query_db(query.format(pkg=pkg, suite=suite, arch=arch)):
                bad_files.append('/'.join([root, file]))
                log.warning('/'.join([root, file]) + ' should not be there')
    return bad_files


def alien_dbd(directory=None):
    if directory is None:
        bad_files = []
        for path in DBD_PATH, DBDTXT_PATH:
            bad_files.extend(alien_log(path))
        return bad_files
    log.info('running alien_dbd check...')
    query = '''SELECT r.status
               FROM sources AS s JOIN results AS r on r.package_id=s.id
               WHERE s.name="{pkg}" AND s.suite="{suite}"
               AND s.architecture="{arch}"
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    bad_files = []
    for root, dirs, files in os.walk(directory):
        if not files:
            continue
        suite, arch = root.rsplit('/', 2)[1:]
        for file in files:
            try:
                pkg, version = file.rsplit('.', 2)[0].rsplit('_', 1)
            except ValueError:
                log.critical(bcolors.FAIL + '/'.join([root, file]) +
                             ' does not seem to be a file that should be there'
                             + bcolors.ENDC)
            result = query_db(query.format(pkg=pkg, suite=suite, arch=arch))
            try:
                if result[0][0] != 'unreproducible':
                    bad_files.append('/'.join([root, file]) + ' (' +
                                     str(result[0][0]) + ' package)')
                    log.warning('/'.join([root, file]) + ' should not be '
                                'there (' + str(result[0][0]) + ' package)')
            except IndexError:
                bad_files.append('/'.join([root, file]) + ' (' +
                                 'missing package)')
                log.warning(bcolors.WARN + '/'.join([root, file]) + ' should '
                            'not be there (missing package)' + bcolors.ENDC)
    return bad_files


def alien_rbpkg():
    log.info('running alien_rbpkg check...')
    query = '''SELECT s.name
               FROM sources AS s
               WHERE s.name="{pkg}" AND s.suite="{suite}"
               AND s.architecture="{arch}"
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    bad_files = []
    for root, dirs, files in os.walk(RB_PKG_PATH):
        if not files:
            continue
        suite, arch = root.rsplit('/', 2)[1:]
        for file in files:
            pkg = file.rsplit('.', 1)[0]
            if not query_db(query.format(pkg=pkg, suite=suite, arch=arch)):
                bad_files.append('/'.join([root, file]))
                log.warning('/'.join([root, file]) + ' should not be there')
    return bad_files


def _gen_section(header, pkgs, entries=None):
    if not pkgs and not entries:
        return ''
    if pkgs:
        html = '<p><b>' + str(len(pkgs)) + '</b> '
        html += header
        html += '<br/><pre>\n'
        for pkg in pkgs:
            html += tab + link_package(pkg[0], pkg[2], pkg[3]).strip()
            html += ' (' + pkg[1] + ' in ' + pkg[2] + '/' + pkg[3] + ')\n'
    elif entries:
        html = '<p><b>' + str(len(entries)) + '</b> '
        html += header
        html += '<br/><pre>\n'
        for entry in entries:
            html += tab + entry + '\n'
    html += '</pre></p>\n'
    return html


def gen_html():
    html = ''
    # files that should not be there (e.g. removed package without cleanup)
    html += _gen_section('log files that should not be there', None,
                         entries=alien_log())
    html += _gen_section('diffoscope files that should not be there:', None,
                         entries=alien_dbd())
    html += _gen_section('rb-pkg pages that should not be there:', None,
                         entries=alien_rbpkg())
    html += _gen_section('buildinfo files that should not be there:', None,
                         entries=alien_buildinfo())
    # diffoscope report where it shouldn't be
    html += _gen_section('are not marked as unreproducible, but they ' +
                         'have a diffoscope file:', not_unrep_with_dbd_file())
    # missing files
    html += _gen_section('are built but don\'t have a buildlog:',
                         lack_rbuild())
    html += _gen_section('are built but don\'t have a .buildinfo file:',
                         lack_buildinfo())
    # diffoscope troubles
    without_dbd, bad_dbd = unrep_with_dbd_issues()
    html += _gen_section('are marked as unreproducible, but without ' +
                         'diffoscope output - so probably diffoscope ' +
                         'crashed:', without_dbd)
    html += _gen_section('are marked as unreproducible, but their ' +
                         'diffoscope output does not seem to be an html ' +
                         'file - so probably diffoscope ran into a ' +
                         'timeout:', bad_dbd)
    # pbuilder-satisfydepends failed
    html += _gen_section('failed to match their build-dependencies:',
                         pbuilder_dep_fail())
    return html


if __name__ == '__main__':
    bugs = get_bugs()
    html = '<p>This page lists unexpected things a human should look at and '
    html += 'fix, like packages with an incoherent status or files that '
    html += 'should not be there. '
    html += '<em>Please help making this page empty!</em></p>\n'
    breakages = gen_html()
    if breakages:
        html += breakages
    else:
        html += '<p><b>COOL!!!</b> Everything is GOOD and not a single issue was '
        html += 'detected. <i>Enjoy!</i></p>'
    title = 'Breakages on reproducible.debian.net'
    destfile = BASE + '/index_breakages.html'
    desturl = REPRODUCIBLE_URL + '/index_breakages.html'
    write_html_page(title, html, destfile, style_note=True)
    log.info('Breackages page created at ' + desturl)
