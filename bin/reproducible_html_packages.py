#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2+
#
# Depends: python3 python3-psycopg2
#
# Build rb-pkg pages (the pages that describe the package status)

import psycopg2

from reproducible_common import *

html_package_page = Template((tab*2).join(("""
<table class="head">
    <tr>
        <td>
            <span style="font-size:1.2em;">$package</span> $version
            <a href="/index_$status.html" target="_parent" title="$status">
                <img src="/static/$icon" alt="$status" />
            </a>
            <span style="font-size:0.9em;">at $build_time:</span>
$links
            <a href="https://packages.qa.debian.org/$package" target="main">PTS</a>
            <a href="https://bugs.debian.org/src:$package" target="main">BTS</a>
            <a href="https://sources.debian.net/src/$package/" target="main">sources</a>
            <a href="https://sources.debian.net/src/$package/$version/debian/rules" target="main">debian/rules</a>
        </td>
        <td>
${bugs_links}
        </td>
        <td style="text-align:right; font-size:0.9em;">
            <a href="%s" target="_parent">
                reproducible builds
            </a>
        </td>
    </tr>
</table>
<iframe id="main" name="main" src="${default_view}">
    <p>
        Your browser does not support iframes.
        Use a different one or follow the links above.
    </p>
</iframe>""" % REPRODUCIBLE_URL ).splitlines(True)))


def sizeof_fmt(num):
    for unit in ['B','KB','MB','GB']:
        if abs(num) < 1024.0:
            if unit == 'GB':
                log.error('The size of this file is bigger than 1 GB!')
                log.error('Please check')
            return str(int(round(float("%3f" % num), 0))) + "%s" % (unit)
        num /= 1024.0
    return str(int(round(float("%f" % num), 0))) + "%s" % ('Yi')

def start_udd_connection():
    username = "public-udd-mirror"
    password = "public-udd-mirror"
    host = "public-udd-mirror.xvm.mit.edu"
    port = 5432
    db = "udd"
    try:
        log.debug("Starting connection to the UDD database")
        conn = psycopg2.connect("dbname=" + db +
                               " user=" + username +
                               " host=" + host +
                               " password=" + password)
    except:
        log.error("Erorr connecting to the UDD database replica")
        raise
    conn.set_client_encoding('utf8')
    return conn

def query_udd(query):
    cursor = conn.cursor()
    cursor.execute(query)
    return cursor.fetchall()

def is_virtual_package(package):
    rows = query_udd("""SELECT source FROM sources WHERE source='%s'""" % package)
    if len(rows) > 0:
            return False
    return True

def bug_has_patch(bug):
    query = """SELECT id FROM bugs_tags WHERE id=%s AND tag='patch'""" % bug
    if len(query_udd(query)) > 0:
        return True
    return False

def get_bugs():
    query = """
        SELECT bugs.id, bugs.source, bugs.done
        FROM bugs JOIN bugs_tags on bugs.id = bugs_tags.id
                  JOIN bugs_usertags on bugs_tags.id = bugs_usertags.id
        WHERE bugs_usertags.email = 'reproducible-builds@lists.alioth.debian.org'
        AND bugs.id NOT IN (
            SELECT id
            FROM bugs_usertags
            WHERE email = 'reproducible-builds@lists.alioth.debian.org'
            AND (
                bugs_usertags.tag = 'toolchain'
                OR bugs_usertags.tag = 'infrastructure')
            )
    """
    # returns a list of tuples [(id, source, done)]
    return query_udd(query)

def check_package_status(package):
    """
    This returns a tuple containing status, version and build_date of the last
    version of the package built by jenkins CI
    """
    try:
        query = 'SELECT status,version,build_date ' + \
                'FROM source_packages ' + \
                'WHERE name="%s"' % package
        result = query_db(query)[0]
    except IndexError:
        log.critical('The query produces no results. The query: ' + query)
        raise
    status = str(result[0])
    version = str(result[1])
    build_date = str(result[2])
    return (status, version, build_date)

def gen_extra_links(package, version):
    notes = NOTES_PATH + '/' + package + '_note.html'
    rbuild = RBUILD_PATH + '/' + package + '_' + strip_epoch(version) + '.rbuild.log'
    buildinfo = BUILDINFO_PATH + '/' + package + '_' + strip_epoch(version) + '_amd64.buildinfo'
    dbd = DBD_PATH + '/' + package + '_' + strip_epoch(version) + '.debbindiff.html'

    links = ''
    default_view = False
    # check whether there are notes available for this package
    if os.access(notes, os.R_OK):
        url = NOTES_URI + '/' + package + '_note.html'
        links += '<a href="' + url + '" target="main">notes</a>\n'
        default_view = url
    else:
        log.debug('notes not detected at ' + notes)
    if os.access(dbd, os.R_OK):
        url = DBD_URI + '/' + package + '_' + strip_epoch(version) + '.debbindiff.html'
        links += '<a href="' + url + '" target="main">debbindiff</a>\n'
        if not default_view:
            default_view = url
    else:
        log.debug('debbindiff not detetected at ' + dbd)
    if pkg_has_buildinfo(package, version):
        url = BUILDINFO_URI + '/' + package + '_' + strip_epoch(version) + '_amd64.buildinfo'
        links += '<a href="' + url + '" target="main">buildinfo</a>\n'
        if not default_view:
            default_view = url
    else:
        log.debug('buildinfo not detected at ' + buildinfo)
    if os.access(rbuild, os.R_OK):
        url = RBUILD_URI + '/' + package + '_' + strip_epoch(version) + '.rbuild.log'
        log_size = os.stat(rbuild).st_size
        links +='<a href="' + url + '" target="main">rbuild (' + \
                sizeof_fmt(log_size) + ')</a>\n'
        if not default_view:
            default_view = url
    else:
        log.warning('The package ' + package +
                    ' did not produce any buildlog! Check ' + rbuild)
    return (links, default_view)

def parse_bugs(bugs):
    """
    This function returns a dict:
    { "package_name": {
        bug1: {patch: True, done: False},
        bug2: {patch: False, done: False},
       }
    }

    The `bugs` argument is the list of tuples returned by the get_bugs() above
    """
    log.info("finding out which usertagged bugs have been closed or at least have patches")
    packages = {}

    for bug in bugs:
        if bug[1] not in packages:
            packages[bug[1]] = {}
        # bug[0] = bug_id, bug[1] = source_name, bug[2] = who_when_done
        if is_virtual_package(bug[1]):
            continue
        packages[bug[1]][bug[0]] = {'done': False, 'patch': False}
        if bug[2]: # if the bug is done
            packages[bug[1]][bug[0]]['done'] = True
        try:
            if bug_has_patch(bug[0]):
                packages[bug[1]][bug[0]]['patch'] = True
        except KeyError:
            log.error('item: ' + str(bug))
    return packages



def gen_bugs_links(package, bugs):
    html = ''
    if package in bugs:
        for bug in bugs[package]:
            html += '<a href="https://bugs.debian.org/' + str(bug) + \
                    '" target="main" class="'
            if bugs[package][bug]['done']:
                html += 'bug-done '
            if bugs[package][bug]['patch']:
                html += ' bug-patch'
            html += '">#' + str(bug) + '</a> '
            print(package + html)
        return html


def process_packages(packages, no_clean=False):
    """
    generate the /rb-pkg/package.html page
    packages should be a list
    """
    bugs = parse_bugs(get_bugs())
    total = len(packages)
    log.info('Generating the pages of ' + str(total) + ' package(s)')
    for pkg in sorted(packages):
        pkg = str(pkg)
        status, version, build_date = check_package_status(pkg)
        log.info('Generating the page of ' + pkg + ' ' + version +
                 ' builded at ' + build_date)

        links, default_view = gen_extra_links(pkg, version)
        bugs_links = gen_bugs_links(pkg, bugs)
        status, icon = join_status_icon(status, pkg, version)

        html = html_package_page.substitute(package=pkg,
                                            status=status,
                                            version=version,
                                            build_time=build_date,
                                            icon=icon,
                                            links=links,
                                            bugs_links=bugs_links,
                                            default_view=default_view)
        destfile = RB_PKG_PATH + '/' + pkg + '.html'
        desturl = REPRODUCIBLE_URL + RB_PKG_URI + '/' + pkg + '.html'
        title = pkg + ' - reproducible build results'
        write_html_page(title=title, body=html, destfile=destfile,
                        noheader=True, noendpage=True)
        log.info("Package page generated at " + desturl)
    if not no_clean:
        purge_old_pages() # housekeep is always good


def purge_old_pages():
    presents = sorted(os.listdir(RB_PKG_PATH))
    for page in presents:
        pkg = page.rsplit('.', 1)[0]
        log.debug('Checking if ' + page + ' (from ' + pkg + ') is still needed')
        query = 'SELECT name FROM source_packages WHERE name="%s"' % pkg
        result = query_db(query)
        if not result: # actually, the query produces no results
            log.info('There is no package named ' + pkg + ' in the database.' +
                     ' Removing old page.')
            os.remove(RB_PKG_PATH + '/' + page)


try:
    conn = start_udd_connection()
except:
    raise
