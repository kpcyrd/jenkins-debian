#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2016 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2016-2017 Holger Levsen <holger@layer-acht.org>
#
# Licensed under GPL-2
#
# Depends: python3
#
# Build a page full of CI issues to investigate

from reproducible_common import *
import time
import os.path

def unrep_with_dbd_issues():
    log.info('running unrep_with_dbd_issues check...')
    without_dbd = []
    bad_dbd = []
    sources_without_dbd = set()
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status='unreproducible'
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + pkg + '_' + \
            eversion + '.diffoscope.html'
        if not os.access(dbd, os.R_OK):
            without_dbd.append((pkg, version, suite, arch))
            sources_without_dbd.add(pkg)
            log.warning(suite + '/' + arch + '/' + pkg + ' (' + version + ') is '
                        'unreproducible without diffoscope file.')
        else:
            log.debug(dbd + ' found.')
            data = open(dbd, 'br').read(3)
            if b'<' not in data:
                bad_dbd.append((pkg, version, suite, arch))
                log.warning(suite + '/' + arch + '/' + pkg + ' (' + version + ') has '
                            'diffoscope output, but it does not seem to '
                            'be an HTML page.')
                sources_without_dbd.add(pkg)
    return without_dbd, bad_dbd, sources_without_dbd

def count_pkgs(pkgs_to_count=[]):
    counted_pkgs = []
    for pkg, version, suite, arch in pkgs_to_count:
         if pkg not in counted_pkgs:
             counted_pkgs.append(pkg)
    return len(counted_pkgs)

def not_unrep_with_dbd_file():
    log.info('running not_unrep_with_dbd_file check...')
    bad_pkgs = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status != 'unreproducible'
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + pkg + '_' + \
            eversion + '.diffoscope.html'
        if os.access(dbd, os.R_OK):
            bad_pkgs.append((pkg, version, suite, arch))
            log.warning(dbd + ' exists but ' + suite + '/' + arch + '/' + pkg + ' (' + version + ')'
                        ' is not unreproducible.')
    return bad_pkgs


def lack_rbuild():
    log.info('running lack_rbuild check...')
    bad_pkgs = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status NOT IN ('blacklisted', '')
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        if not pkg_has_rbuild(pkg, version, suite, arch):
            bad_pkgs.append((pkg, version, suite, arch))
            log.warning(suite + '/' + arch + '/' + pkg + ' (' + version + ') has been '
                        'built, but a buildlog is missing.')
    return bad_pkgs


def lack_buildinfo():
    log.info('running lack_buildinfo check...')
    bad_pkgs = []
    query = '''SELECT s.name, r.version, s.suite, s.architecture
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status NOT IN
                ('blacklisted', 'not for us', 'FTBFS', 'depwait', '404', '')
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    results = query_db(query)
    for pkg, version, suite, arch in results:
        eversion = strip_epoch(version)
        buildinfo = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + pkg + \
            '_' + eversion + '_' + arch + '.buildinfo'
        if not os.access(buildinfo, os.R_OK):
            bad_pkgs.append((pkg, version, suite, arch))
            log.warning(suite + '/' + arch + '/' + pkg + ' (' + version + ') has been '
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
               WHERE r.status = 'FTBFS' AND s.suite = 'testing'
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
                        log.warning(suite + '/' + arch + '/' + pkg + ' (' + version +
                                    ') failed to satisfy its dependencies.')
    return bad_pkgs


def alien_log(directory=None):
    if directory is None:
        bad_files = []
        for path in RBUILD_PATH, LOGS_PATH, DIFFS_PATH:
            bad_files.extend(alien_log(path))
        return bad_files
    log.info('running alien_log check over ' + directory + '...')
    query = '''SELECT r.version
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status != '' AND s.name='{pkg}' AND s.suite='{suite}'
               AND s.architecture='{arch}'
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    bad_files = []
    for root, dirs, files in os.walk(directory):
        if not files:
            continue
        suite, arch = root.rsplit('/', 2)[1:]
        for file in files:
            # different file have differnt name patterns and different splitting needs
            if file.endswith('.diff.gz'):
                rsplit_level = 2
            elif file.endswith('.gz'):
                rsplit_level = 3
            else:
                rsplit_level = 2
            try:
                pkg, version = file.rsplit('.', rsplit_level)[0].rsplit('_', 1)
            except ValueError:
                log.critical(bcolors.FAIL + '/'.join([root, file]) +
                             ' does not seem to be a file that should be there'
                             + bcolors.ENDC)
                continue
            try:
                rversion = query_db(query.format(pkg=pkg, suite=suite, arch=arch))[0][0]
            except IndexError:  # that package is not known (or not yet tested)
                rversion = ''   # continue towards the "bad file" path
            if strip_epoch(rversion) != version:
                try:
                    if os.path.getmtime('/'.join([root, file]))<time.time()-86400:
                        os.remove('/'.join([root, file]))
                        log.warning('/'.join([root, file]) + ' should not be there and and was older than a day so it was removed.')
                    else:
                        bad_files.append('/'.join([root, file]))
                        log.info('/'.join([root, file]) + ' should not be there, but is also less than 24h old and will probably soon be gone. Probably diffoscope is running on that package right now.')
                except FileNotFoundError:
                    pass  # that bad file is already gone.
    return bad_files


def alien_buildinfo():
    log.info('running alien_buildinfo check...')
    query = '''SELECT r.version
               FROM sources AS s JOIN results AS r ON r.package_id=s.id
               WHERE r.status != '' AND s.name='{pkg}' AND s.suite='{suite}'
               AND s.architecture='{arch}'
               AND r.status IN ('reproducible', 'unreproducible')
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
            try:
                rversion = query_db(query.format(pkg=pkg, suite=suite, arch=arch))[0][0]
            except IndexError:  # that package is not known (or not yet tested)
                rversion = ''   # continue towards the "bad file" path
            if strip_epoch(rversion) != version:
                try:
                    if os.path.getmtime('/'.join([root, file]))<time.time()-86400:
                        os.remove('/'.join([root, file]))
                        log.warning('/'.join([root, file]) + ' should not be there and and was older than a day so it was removed.')
                    else:
                        bad_files.append('/'.join([root, file]))
                        log.info('/'.join([root, file]) + ' should not be there, but is also less than 24h old and will probably soon be gone.')
                except FileNotFoundError:
                    pass  # that bad file is already gone.
    return bad_files


def alien_dbd(directory=None):
    if directory is None:
        bad_files = []
        for path in DBD_PATH, DBDTXT_PATH:
            bad_files.extend(alien_log(path))
        return bad_files


def alien_rbpkg():
    log.info('running alien_rbpkg check...')
    query = '''SELECT s.name
               FROM sources AS s
               WHERE s.name='{pkg}' AND s.suite='{suite}'
               AND s.architecture='{arch}'
               ORDER BY s.name ASC, s.suite DESC, s.architecture ASC'''
    bad_files = []
    for root, dirs, files in os.walk(RB_PKG_PATH):
        if not files:
            continue
        # Extract the "suite" and "arch" from the directory structure
        if os.path.split(root)[1] == 'diffoscope-results':
            # We are presently inspecting package pages in the
            # RB_PKG_PATH/{{suite}}/{{arch}}/diffoscope-results directory
            suite, arch = os.path.split(root)[0].rsplit('/', 2)[1:]
        else:
            # We are presently inspecting package pages in the
            # RB_PKG_PATH/{{suite}}/{{arch}}/ directory
            suite, arch = root.rsplit('/', 2)[1:]
        for file in files:
            pkg = file.rsplit('.', 1)[0]
            if not query_db(query.format(pkg=pkg, suite=suite, arch=arch)):
                bad_files.append('/'.join([root, file]))
                log.warning('/'.join([root, file]) + ' should not be there')
    return bad_files


def alien_history():
    log.info('running alien_history check...')
    result = query_db('SELECT DISTINCT name FROM sources')
    actual_packages = [x[0] for x in result]
    bad_files = []
    for f in sorted(os.listdir(HISTORY_PATH)):
        full_path = os.path.join(HISTORY_PATH, f)
        if f.rsplit('.', 1)[0] not in actual_packages and not os.path.isdir(full_path):
            bad_files.append(full_path)
            os.remove(full_path)
            log.warning('%s should not be there so it has been removed.', full_path)
    return bad_files


def _gen_packages_html(header, pkgs):
    html = ''
    if pkgs:
        html = '<p><b>' + str(len(pkgs)) + '</b> '
        html += header
        html += '<br/><pre>\n'
        for pkg in pkgs:
            html += tab + link_package(pkg[0], pkg[2], pkg[3]).strip()
            html += ' (' + pkg[1] + ' in ' + pkg[2] + '/' + pkg[3] + ')\n'
        html += '</pre></p>\n'
    return html

def _gen_files_html(header, entries):
    html = ''
    if entries:
        html = '<p><b>' + str(len(entries)) + '</b> '
        html += header
        html += '<br/><pre>\n'
        for entry in entries:
            html += tab + entry + '\n'
        html += '</pre></p>\n'
    return html

def create_breakages_graph(png_file, main_label):
    png_fullpath = os.path.join(DEBIAN_BASE, png_file)
    table = "stats_breakages"
    columns = ["datum", "diffoscope_timeouts", "diffoscope_crashes"]
    query = "SELECT {fields} FROM {table} ORDER BY datum".format(
        fields=", ".join(columns), table=table)
    result = query_db(query)
    result_rearranged = [dict(zip(columns, row)) for row in result]

    with create_temp_file(mode='w') as f:
        csv_tmp_file = f.name
        csv_writer = csv.DictWriter(f, columns)
        csv_writer.writeheader()
        csv_writer.writerows(result_rearranged)
        f.flush()

        graph_command = os.path.join(BIN_PATH, "make_graph.py")
        y_label = "Amount (packages)"
        log.info("Creating graph for stats_breakges.")
        check_call([graph_command, csv_tmp_file, png_fullpath, '2', main_label,
                    y_label, '1920', '960'])


def update_stats_breakages(diffoscope_timeouts, diffoscope_crashes):
    # we only do stats up until yesterday
    YESTERDAY = (datetime.now()-timedelta(days=1)).strftime('%Y-%m-%d')

    result = query_db("""
            SELECT datum, diffoscope_timeouts, diffoscope_crashes
            FROM stats_breakages
            WHERE datum = '{date}'
        """.format(date=YESTERDAY))

    # if there is not a result for this day, add one
    if not result:
        insert = "INSERT INTO stats_breakages VALUES ('{date}', " + \
                 "'{diffoscope_timeouts}', '{diffoscope_crashes}')"
        query_db(insert.format(date=YESTERDAY, diffoscope_timeouts=diffoscope_timeouts, diffoscope_crashes=diffoscope_crashes))
        log.info("Updating db table stats_breakages on %s with %s timeouts and %s crashes.",
                 YESTERDAY, diffoscope_timeouts, diffoscope_crashes)
    else:
        log.debug("Not updating db table stats_breakages as it already has data for %s.",
                 YESTERDAY)


def gen_html():
    html = ''
    # pbuilder-satisfydepends failed
    broken_pkgs = pbuilder_dep_fail()
    if broken_pkgs != []:
        html += '<h3>Breakage caused by broken packages</h3>'
        html += _gen_packages_html('failed to satisfy their build-dependencies:',
                         broken_pkgs)
    # diffoscope troubles
    html += '<h2>Breakage involving diffscope</h2>'
    without_dbd, bad_dbd, sources_without_dbd = unrep_with_dbd_issues()
    html += str(len(sources_without_dbd))
    html += ' source packages on which diffoscope ran into timeouts ('
    html += str(count_pkgs(bad_dbd)) + ') or crashed ('
    html += str(count_pkgs(without_dbd)) + ') or sometimes both.'
    # gather stats and add graph
    update_stats_breakages(count_pkgs(bad_dbd), count_pkgs(without_dbd))
    png_file = 'stats_breakages.png'
    main_label = "source packages causing Diffoscope to timeout and crash"
    create_breakages_graph(png_file, main_label)
    html += '<br> <a href="/debian/' + png_file + '"><img src="/debian/'
    html += png_file + '" alt="' + main_label + '"></a>'
    # link artifacts
    html += '<br/> <a href="https://tests.reproducible-builds.org/debian/artifacts/">Artifacts diffoscope crashed</a> on are available for 48h for download.'

    html += _gen_packages_html('are marked as unreproducible, but there is no ' +
                         'diffoscope output - so probably diffoscope ' +
                         'crashed:', without_dbd)
    html += _gen_packages_html('are marked as unreproducible, but their ' +
                         'diffoscope output does not seem to be an html ' +
                         'file - so probably diffoscope ran into a ' +
                         'timeout:', bad_dbd)
    # files that should not be there (e.g. removed packages without cleanup)
    html += '<h2>Breakage on jenkins.debian.net</h2>'
    html += _gen_files_html('log files that should not be there (and which will be deleted once they are older than 24h):',
                         entries=alien_log())
    html += _gen_files_html('diffoscope files that should not be there:',
                         entries=alien_dbd())
    html += _gen_files_html('rb-pkg pages that should not be there:',
                         entries=alien_rbpkg())
    html += _gen_files_html('buildinfo files that should not be there (and which will be deleted once they are older than 24h):',
                         entries=alien_buildinfo())
    html += _gen_files_html('history pages that should not be there and thus have been removed:',
                         entries=alien_history())
    # diffoscope reports where they shouldn't be
    html += _gen_packages_html('are not marked as unreproducible, but they ' +
                         'have a diffoscope file:', not_unrep_with_dbd_file())
    # missing files
    html += _gen_packages_html('have been built but don\'t have a buildlog:',
                         lack_rbuild())
    html += _gen_packages_html('have been built but don\'t have a .buildinfo file:',
                         lack_buildinfo())
    return html


if __name__ == '__main__':
    bugs = get_bugs()
    html = '<p>This page lists unexpected things a human should look at and '
    html += 'fix, like packages with an incoherent status or files that '
    html += 'should not be there. Some of these breakages are caused by '
    html += 'bugs in <a href="https://anonscm.debian.org/git/reproducible/diffoscope.git">diffoscope</a> '
    html += 'while others are probably due to bugs in the scripts run by jenkins. '
    html += '<em>Please help making this page empty!</em></p>\n'
    breakages = gen_html()
    if breakages:
        html += breakages
    else:
        html += '<p><b>COOL!!!</b> Everything is GOOD and not a single issue was '
        html += 'detected. <i>Enjoy!</i></p>'
    title = 'Breakage on the Debian pages of tests.reproducible-builds.org'
    destfile = DEBIAN_BASE + '/index_breakages.html'
    desturl = DEBIAN_URL + '/index_breakages.html'

    left_nav_html = create_main_navigation(displayed_page='breakages')
    write_html_page(title, html, destfile, style_note=True,
                    left_nav_html=left_nav_html)
    log.info('Breakages page created at ' + desturl)
