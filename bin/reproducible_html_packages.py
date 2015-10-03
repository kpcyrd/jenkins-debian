#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Based on reproducible_html_packages.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build rb-pkg pages (the pages that describe the package status)

from reproducible_common import *

html_package_page = Template((tab*2).join(("""
<header class="head">
    <h2 class="package-name">$package</h2>
    <ul class="menu">
        <li><ul class="children">
          <li>$version <a href="/index_notify.html" target="_parent">
            <span class="notification" title="Notifications for this package are enabled. Every reproducibility related status change will be emailed to the maintainers">$notify_maintainer</span></a></li>
          <li>$suite/$arch </li>
          <li>$status </li>
          <li><span class="build-time">$build_time</span></li>
          $links
        </ul></li>
        <li>
            <a href="https://tracker.debian.org/$package">PTS</a>
            <a href="https://bugs.debian.org/src:$package">BTS</a>
        </li>
        <li>
            <a href="https://sources.debian.net/src/$package/$version/">sources</a>
            <a href="https://sources.debian.net/src/$package/$version/debian">debian/</a>
            <ul class="children">
                <li><a href="https://sources.debian.net/src/$package/$version/debian/changelog">changelog</a></li>
                <li><a href="https://sources.debian.net/src/$package/$version/debian/control">control</a></li>
                <li><a href="https://sources.debian.net/src/$package/$version/debian/rules">rules</a></li>
            </ul>
        </li>
    </ul>

${suites_links}

    <ul class="reproducible-links">
        Reproducible Builds project links
        <li>
            <a href="%s">Dashboard</a><br />
            <a href="https://wiki.debian.org/ReproducibleBuilds">Wiki</a><br />
            <a href="https://reproducible.debian.net/howto">HowTo</a>
        </li>
    </ul>
</header>

<iframe id="main" name="main" tabindex="1" src="${default_view}">
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


def gen_status_link_icon(status, icon, suite, arch):
    html = """
        <a href="/{suite}/{arch}/index_{status}.html" target="_parent" title="{status}">
            <img src="/static/{icon}" alt="{status}"></a>

        <a href="/{suite}/{arch}/index_{status}.html" target="_parent" title="{status}">
            {status}</a>
    """

    # There are no indices for untested packages
    if status == 'untested':
        html = '<img src="/static/{icon}" alt="{status}"> {status}'

    return html.format(status=status, icon=icon, suite=suite, arch=arch)


def link_buildlogs(package, eversion, suite, arch):
    html = ''
    log = suite + '/' + arch + '/' + package + '_' + eversion + '.build2.log.gz'
    diff = suite + '/' + arch + '/' + package + '_' + eversion + '.diff.gz'
    if os.access(LOGS_PATH+'/'+log, os.R_OK):
        uri = LOGS_URI + '/' + log
        size = sizeof_fmt(os.stat(LOGS_PATH+'/'+log).st_size)
        html += '<a href="' + uri + '" target="main">build2 (' + size + ')</a>\n'
    if os.access(DIFFS_PATH+'/'+diff, os.R_OK):
        uri = DIFFS_URI + '/' + diff
        html += '<a href="' + uri + '" target="main">diff</a>\n'
    return html


def link_diffs(package, eversion, suite, arch, status):
    html = ''
    dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + package + '_' + \
          eversion + '.debbindiff.html'
    dbdtxt = DBDTXT_PATH + '/' + suite + '/' + arch + '/' + package + '_' + \
             eversion + '.debbindiff.txt.gz'
    dbd_url = DBD_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
              eversion + '.debbindiff.html'
    dbdtxt_url = DBDTXT_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
                eversion + '.debbindiff.txt'
    if os.access(dbd, os.R_OK):
        html += '<li><a href="' + dbd_url + '" target="main">differences</a>\n'
        if os.access(dbdtxt, os.R_OK):
            html += '<a href="' + dbdtxt_url + '" target="main">(txt)</a>\n'
        html += '</li>\n'
    else:
        log.debug('debbindiff not detetected at ' + dbd)
        if status == 'unreproducible' and not args.ignore_missing_files:
            log.critical(REPRODUCIBLE_URL + '/' + suite + '/' + arch + '/' + package +
                         ' is unreproducible, but without diffoscope output.')
    return html, dbd_url


def gen_extra_links(package, version, suite, arch, status):
    eversion = strip_epoch(version)
    notes = NOTES_PATH + '/' + package + '_note.html'
    buildinfo = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + package + \
                '_' + eversion + '_' + arch + '.buildinfo'

    links = ''
    default_view = ''
    if os.access(notes, os.R_OK):
        url = NOTES_URI + '/' + package + '_note.html'
        links += '<li><a href="' + url + '" target="main">notes</a></li>\n'
        default_view = url
    else:
        log.debug('notes not detected at ' + notes)
    dbd = link_diffs(package, eversion, suite, arch, status)
    links += dbd[0] if dbd[0] else ''
    if dbd[0] and not default_view:
            default_view = dbd[1]
    if pkg_has_buildinfo(package, version, suite, arch):
        url = BUILDINFO_URI + '/' + suite + '/' + arch + '/' + package + \
              '_' + eversion + '_' + arch + '.buildinfo'
        links += '<li><a href="' + url + '" target="main">buildinfo</a></li>\n'
        if not default_view:
            default_view = url
    elif not args.ignore_missing_files and status not in \
        ('untested', 'blacklisted', 'FTBFS', 'not for us', 'depwait', '404'):
            log.critical('buildinfo not detected at ' + buildinfo)
    rbuild = pkg_has_rbuild(package, version, suite, arch)
    if rbuild:  # being a tuple (rbuild path, size), empty if non existant
        url = RBUILD_URI + '/' + suite + '/' + arch + '/' + package + '_' + \
              eversion + '.rbuild.log'  # apache ignores the trailing .gz
        links +='<li><a href="' + url + '" target="main">rbuild (' + \
                sizeof_fmt(rbuild[1]) + ')</a>\n'
        if not default_view:
            default_view = url
        links += link_buildlogs(package, eversion, suite, arch) + '</li>\n'
    elif status not in ('untested', 'blacklisted') and not args.ignore_missing_files:
        log.critical(REPRODUCIBLE_URL  + '/' + suite + '/' + arch + '/' + package +
                     ' didn\'t produce a buildlog, even though it has been built.')
    default_view = '/untested.html' if not default_view else default_view
    return (links, default_view)


def gen_suites_links(package, current_suite, current_arch):
    html = '<ul>\n'
    for a in ARCHS:
        html += tab + '<li>{}\n'.format(a)
        html += tab + '<ul class="children">\n'
        for s in SUITES:
            if a == 'armhf' and s != 'unstable':
                continue
            status = package.get_status(s, a)
            if not status:  # The package is not available in that suite/arch
                continue
            version = package.get_tested_version(s, a)
            build_date = package.get_build_date(s, a)
            if build_date and status != 'blacklisted':
                build_date = ' on ' + build_date
            else:
                build_date = ''
            li_classes = ['suite']
            if s == current_suite and a == current_arch:
                li_classes.append('active')
            html += '<li class="' + ' '.join(li_classes) + '">\n' + tab
            if s != current_suite or a != current_arch or status != 'untested':
                prefix = '<a href="/{}/{}/index_{}.html">'.format(s, a, status)
                suffix = '</a>\n'
            else:
                prefix = ''
                suffix = '\n'
            icon = prefix + '<img src="/static/{icon}" alt="{status}" title="{status}"/>' + suffix
            html += icon.format(icon=join_status_icon(status)[1], status=status)
            html += (tab*2 + ' <a href="{}/{}/{}/{}.html" target="_parent"' + \
                     ' title="{}: {}{}">{}</a> in <a href="/{}/{}/" target="_parent">{}</a>\n').format(RB_PKG_URI,
                     s, a, package.name, status, version, build_date, version, s, a, s)
            html += '</li>\n'
        html += tab + '</ul></li>'
    html += '</ul>\n'
    return tab*5 + (tab*7).join(html.splitlines(True))


def gen_packages_html(packages, no_clean=False):
    """
    generate the /rb-pkg/package.html pages.
    packages should be a list of Package objects.
    """
    total = len(packages)
    log.debug('Generating the pages of ' + str(total) + ' package(s)')
    for package in sorted(packages, key=lambda x: x.name):
        assert isinstance(package, Package)
        pkg = package.name
        for suite in SUITES:
            for arch in ARCHS:
                if arch == 'armhf' and suite != 'unstable':
                    continue
                status = package.get_status(suite, arch)
                version = package.get_tested_version(suite, arch)
                build_date = package.get_build_date(suite, arch)
                if build_date and status != 'blacklisted':
                    build_date = 'at ' + build_date
                else:
                    build_date = ''
                if status == False:  # the package is not in the checked suite
                    continue
                log.debug('Generating the page of %s/%s/%s @ %s built at %s',
                          pkg, suite, arch, version, build_date)

                links, default_view = gen_extra_links(
                    pkg, version, suite, arch, status)
                suites_links = gen_suites_links(package, suite, arch)
                status, icon = join_status_icon(status, pkg, version)
                status = gen_status_link_icon(status, icon, suite, arch)

                html = html_package_page.substitute(
                    package=pkg,
                    suite=suite,
                    arch=arch,
                    status=status,
                    version=version,
                    build_time=build_date,
                    links=links,
                    notify_maintainer=package.notify_maint,
                    suites_links=suites_links,
                    default_view=default_view)
                destfile = RB_PKG_PATH + '/' + suite + '/' + arch + '/' + pkg + '.html'
                desturl = REPRODUCIBLE_URL + RB_PKG_URI + '/' + suite + \
                          '/' + arch + '/' + pkg + '.html'
                title = pkg + ' - reproducible build results'
                write_html_page(title=title, body=html, destfile=destfile,
                                noheader=True, noendpage=True, packages=True)
                log.debug("Package page generated at " + desturl)
    if not no_clean:
        purge_old_pages()  # housekeep is always good


def gen_all_rb_pkg_pages(no_clean=False):
    query = 'SELECT DISTINCT name FROM sources'
    rows = query_db(query)
    pkgs = [Package(str(i[0]), no_notes=True) for i in rows]
    log.info('Processing all %s package from all suites/architectures',
             len(pkgs))
    gen_packages_html(pkgs, no_clean=True)  # we clean at the end
    purge_old_pages()


def purge_old_pages():
    for suite in SUITES:
        for arch in ARCHS:
            if arch == 'armhf' and suite != 'unstable':
                continue
            log.info('Removing old pages from ' + suite + '/' + arch + '.')
            try:
                presents = sorted(os.listdir(RB_PKG_PATH + '/' + suite + '/' +
                                  arch))
            except OSError as e:
                if e.errno != errno.ENOENT:  # that's 'No such file or
                    raise                    # directory' error (errno 17)
                presents = []
            log.debug('page presents: ' + str(presents))
            for page in presents:
                pkg = page.rsplit('.', 1)[0]
                query = 'SELECT s.name ' + \
                    'FROM sources AS s ' + \
                    'WHERE s.name="{name}" ' + \
                    'AND s.suite="{suite}" AND s.architecture="{arch}"'
                query = query.format(name=pkg, suite=suite, arch=arch)
                result = query_db(query)
                if not result: # actually, the query produces no results
                    log.info('There is no package named ' + pkg + ' from ' +
                             suite + '/' + arch + ' in the database. ' +
                             'Removing old page.')
                    os.remove(RB_PKG_PATH + '/' + suite + '/' + arch + '/' +
                              page)

