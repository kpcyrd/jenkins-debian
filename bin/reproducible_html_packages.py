#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2+
#
# Depends: python3
#
# Build rb-pkg pages (the pages that describe the package status)


from reproducible_common import *

html_package_page = Template((tab*2).join(("""
<table class="head">
    <tr>
        <td>
            <span style="font-size:1.2em;">$package</span> $version
            <a href="/index_$status.html" target="_parent" title="$status">
                <img src="/userContent/static/$icon" alt="$status" />
            </a>
            <span style="font-size:0.9em;">at $build_time:</span>
$links
            <a href="/userContent/rbuild/${package}_$version.rbuild.log" target="main">rbuild ($rbuild_size)</a>
            <a href="https://packages.qa.debian.org/$package" target="main">PTS</a>
            <a href="https://bugs.debian.org/src:$package" target="main">BTS</a>
            <a href="https://sources.debian.net/src/$package/" target="main">sources</a>
            <a href="https://sources.debian.net/src/$package/$version/debian/rules" target="main">debian/rules</a>
        </td>
        <td style="text-align:right; font-size:0.9em;">
            <a href="%s" target="_parent">
                reproducible builds
            </a>
        </td>
    </tr>
</table>
<iframe name="main" src="${default_view}" width="100%%" height="98%%" frameborder="0">
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
    buildinfo = BUILDINFO_PATH + '/' + package + '_' + version + '_amd64.buildinfo'
    dbd = DBD_PATH + '/' + package + '_' + version + '.debbindiff.html'

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
        url = DBD_URI + '/' + package + '_' + version + '.debbindiff.html'
        links += '<a href="' + url + '" target="main">debbindiff</a>\n'
        if not default_view:
            default_view = url
    else:
        log.debug('debbindiff not detetected at ' + dbd)
    if os.access(buildinfo, os.R_OK):
        url = BUILDINFO_URI + '/' + package + '_' + version + '_amd64.buildinfo'
        links += '<a href="' + url + '" target="main">buildinfo</a>\n'
        if not default_view:
            default_view = url
    else:
        log.debug('buildinfo not detected at ' + buildinfo)
    return (links, default_view)


def process_packages(packages):
    """
    generate the /rb-pkg/package.html page
    packages should be a list
    """
    total = len(packages)
    log.info('Generating the pages of ' + str(total) + ' package(s)')
    for pkg in sorted(packages):
        pkg = str(pkg)
        status, version, build_date = check_package_status(pkg)
        log.info('Generating the page of ' + pkg + ' ' + version +
                 ' builded at ' + build_date)

        rbuild = RBUILD_PATH + '/' + pkg + '_' + version + '.rbuild.log'
        links, default_view = gen_extra_links(pkg, version)

        if not default_view: # this is only possible only if there are no notes,
                             # debbindiff or buildinfo files
            default_view = RBUILD_URI + '/' + pkg + '_' + version + '.rbuild.log'
        try:
            log_size = os.stat(rbuild).st_size
        except OSError:
            log.warning('The package ' + pkg +
                        ' did not produce any buildlog! Check ' + rbuild)
            log_size = 0
            pass
        status, icon = join_status_icon(status, pkg, version)
        html = html_package_page.substitute(package=pkg,
                                            status=status,
                                            version=version,
                                            build_time=build_date,
                                            icon=icon,
                                            links=links,
                                            rbuild_size=sizeof_fmt(log_size),
                                            default_view=default_view)
        destfile = RB_PKG_PATH + '/' + pkg + '.html'
        desturl = REPRODUCIBLE_URL + RB_PKG_URI + '/' + pkg + '.html'
        title = pkg + ' reproducible build results'
        write_html_page(title=title, body=html, destfile=destfile,
                        noheader=True, nofooter=True, noendpage=True)
        log.info("Package page generated at " + desturl)
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
