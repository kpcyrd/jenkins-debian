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
import pystache
import apt_pkg
apt_pkg.init_system()

# Templates used for creating package pages
renderer = pystache.Renderer();
package_page_template = renderer.load_template(
    TEMPLATE_PATH + '/package_page')
suitearch_section_template = renderer.load_template(
    TEMPLATE_PATH + '/package_suitearch_section')
suitearch_details_template = renderer.load_template(
    TEMPLATE_PATH + '/package_suitearch_details')
status_icon_link_template = renderer.load_template(
    TEMPLATE_PATH + '/status_icon_link')

def sizeof_fmt(num):
    for unit in ['B','KB','MB','GB']:
        if abs(num) < 1024.0:
            if unit == 'GB':
                log.error('The size of this file is bigger than 1 GB!')
                log.error('Please check')
            return str(int(round(float("%3f" % num), 0))) + "%s" % (unit)
        num /= 1024.0
    return str(int(round(float("%f" % num), 0))) + "%s" % ('Yi')


def gen_status_link_icon(status, spokenstatus, icon, suite, arch):
    context = {
        'status': status,
        'spokenstatus': spokenstatus,
        'icon': icon,
        'suite': suite,
        'arch': arch,
        'untested': True if status == 'untested' else False,
    }
    return renderer.render(status_icon_link_template, context)

def get_buildlog_links_context(package, eversion, suite, arch):
    log = suite + '/' + arch + '/' + package + '_' + eversion + '.build2.log.gz'
    diff = suite + '/' + arch + '/' + package + '_' + eversion + '.diff.gz'

    context = {}
    if os.access(LOGS_PATH+'/'+log, os.R_OK):
        context['build2_uri'] = LOGS_URI + '/' + log
        context['build2_size'] = sizeof_fmt(os.stat(LOGS_PATH+'/'+log).st_size)

    if os.access(DIFFS_PATH+'/'+diff, os.R_OK):
        context['diff_uri'] = DIFFS_URI + '/' + diff

    return context


def get_dbd_link_context(package, eversion, suite, arch, status):

    dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + package + '_' + \
          eversion + '.diffoscope.html'
    dbdtxt = DBDTXT_PATH + '/' + suite + '/' + arch + '/' + package + '_' + \
             eversion + '.diffoscope.txt.gz'
    dbd_url = DBD_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
              eversion + '.diffoscope.html'
    dbdtxt_url = DBDTXT_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
                eversion + '.diffoscope.txt'

    context = {}
    if os.access(dbd, os.R_OK):
        context['dbd_url'] = dbd_url
        if os.access(dbdtxt, os.R_OK):
            context['dbdtxt_url'] = dbdtxt_url
    else:
        if status == 'unreproducible' and not args.ignore_missing_files:
            log.critical(DEBIAN_URL + '/' + suite + '/' + arch + '/' + package +
                         ' is unreproducible, but without diffoscope output.')
    return context, dbd_url


def gen_suitearch_details(package, version, suite, arch, status, spokenstatus,
                          build_date):
    eversion = strip_epoch(version)
    buildinfo_file = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + package + \
                '_' + eversion + '_' + arch + '.buildinfo'

    context = {}
    default_view = ''

    # Make notes the default default view
    notes_file = NOTES_PATH + '/' + package + '_note.html'
    notes_uri = NOTES_URI + '/' + package + '_note.html'
    if os.access(notes_file, os.R_OK):
        default_view = notes_uri

    # Get summary context
    context['status_html'] = gen_status_link_icon(status, spokenstatus, None,
                                                  suite, arch)
    context['build_date'] =  build_date

    default_view = ''
    # Get diffoscope differences context
    dbd = get_dbd_link_context(package, eversion, suite, arch, status)
    if dbd[0]:
        context['dbd'] = dbd[0]
        default_view = default_view if default_view else dbd[1]

    # Get buildinfo context
    if pkg_has_buildinfo(package, version, suite, arch):
        url = BUILDINFO_URI + '/' + suite + '/' + arch + '/' + package + \
              '_' + eversion + '_' + arch + '.buildinfo'
        context['buildinfo_uri'] = url
        default_view = default_view if default_view else url
    elif not args.ignore_missing_files and status not in \
        ('untested', 'blacklisted', 'FTBFS', 'not for us', 'depwait', '404'):
            log.critical('buildinfo not detected at ' + buildinfo_file)

    # Get rbuild, build2 and build diffs context
    rbuild = pkg_has_rbuild(package, version, suite, arch)
    if rbuild:  # being a tuple (rbuild path, size), empty if non existant
        url = RBUILD_URI + '/' + suite + '/' + arch + '/' + package + '_' + \
              eversion + '.rbuild.log'  # apache ignores the trailing .gz
        context['rbuild_uri'] = url
        context['rbuild_size'] = sizeof_fmt(rbuild[1])
        default_view = default_view if default_view else url
        context['buildlogs'] = get_buildlog_links_context(package, eversion,
                                                          suite, arch)
    elif status not in ('untested', 'blacklisted') and \
         not args.ignore_missing_files:
        log.critical(DEBIAN_URL  + '/' + suite + '/' + arch + '/' + package +
                     ' didn\'t produce a buildlog, even though it has been built.')

    context['has_buildloginfo'] = 'buildinfo_uri' in context or \
                                  'buildlogs' in context or \
                                  'rbuild_uri' in context

    default_view = '/untested.html' if not default_view else default_view
    suitearch_details_html = renderer.render(suitearch_details_template, context)
    return (suitearch_details_html, default_view)


def determine_reproducibility(status1, version1, status2, version2):
    newstatus = ''
    versionscompared = apt_pkg.version_compare(version1, version2);

    # if version1 > version2,
    # ignore the older package (version2)
    if (versionscompared > 0):
        return status1, version1

    # if version1 < version2,
    # ignore the older package (version1)
    elif (versionscompared < 0):
        return status2, version2

    # if version1 == version 2,
    # we are comparing status for the same (most recent) version
    else:
        if status1 == 'reproducible' and status2 == 'reproducible':
            return 'reproducible', version1
        else:
            return 'not_reproducible', version1


def gen_suitearch_section(package, current_suite, current_arch):
    # keep track of whether the package is entirely reproducible
    final_version = ''
    final_status = ''

    default_view = ''
    context = {}
    context['architectures'] = []
    for a in ARCHS:

        suites = []
        for s in SUITES:

            status = package.get_status(s, a)
            if not status:  # The package is not available in that suite/arch
                continue
            version = package.get_tested_version(s, a)

            if not final_version or not final_status:
                final_version = version
                final_status = status
            else:
                final_status, final_version = determine_reproducibility(
                    final_status, final_version, status, version)

            build_date = package.get_build_date(s, a)
            status, icon, spokenstatus = get_status_icon(status)

            if not (build_date and status != 'blacklisted'):
                build_date = ''

            li_classes = ['suite']
            if s == current_suite and a == current_arch:
                li_classes.append('active')
            package_uri = ('{}/{}/{}/{}.html').format(RB_PKG_URI, s, a, package.name)

            suitearch_details_html = ''
            if (s == current_suite and a == current_arch):
                suitearch_details_html, default_view = gen_suitearch_details(
                    package.name, version, s, a, status, spokenstatus, build_date)

            suites.append({
                'status': status,
                'version': version,
                'build_date': build_date,
                'icon': icon,
                'spokenstatus': spokenstatus,
                'li_classes': ' '.join(li_classes),
                'arch': a,
                'suite': s,
                'untested': status == 'untested',
                'current_suitearch': s == current_suite and a == current_arch,
                'package_uri': package_uri,
                'suitearch_details_html': suitearch_details_html,
            })

        if len(suites):
            context['architectures'].append({
                'arch': a,
                'suites': suites,
            })

    html = renderer.render(suitearch_section_template, context)
    reproducible = True if final_status == 'reproducible' else False
    return html, default_view, reproducible

def shorten_if_debiannet(hostname):
    if hostname[-11:] == '.debian.net':
        hostname = hostname[:-11]
    return hostname

def gen_history_page(package):
    keys = ('build date', 'version', 'suite', 'architecture', 'result',
        'build duration', 'node1', 'node2', 'job', 'schedule message')
    try:
        head = package.history[0]
    except IndexError:
        html = '<p>No historical data available for this package.</p>'
    else:
        html = '<table>\n{tab}<tr>\n{tab}{tab}'.format(tab=tab)
        for i in keys:
            html += '<th>{}</th>'.format(i)
        html += '\n{tab}</tr>'.format(tab=tab)
        for record in package.history:
            # remove trailing .debian.net from hostnames
            record['node1'] = shorten_if_debiannet(record['node1'])
            record['node2'] = shorten_if_debiannet(record['node2'])
            # add icon to result
            status, icon, spokenstatus = get_status_icon(record['result'])
            result_html = spokenstatus + ' <img src="/static/{icon}" alt="{spokenstatus}" title="{spokenstatus}"/>'
            record['result'] = result_html.format(icon=icon, spokenstatus=spokenstatus)
            # human formatting of build duration
            record['build duration'] = convert_into_hms_string(
                int(record['build duration']))
            html += '\n{tab}<tr>\n{tab}{tab}'.format(tab=tab)
            for i in keys:
                html += '<td>{}</td>'.format(record[i])
            html += '\n{tab}</tr>'.format(tab=tab)
        html += '</table>'
    destfile = os.path.join(HISTORY_PATH, package.name+'.html')
    title = 'build history of {}'.format(package.name)
    write_html_page(title=title, body=html, destfile=destfile,
                    noheader=True, noendpage=True)


def gen_packages_html(packages, no_clean=False):
    """
    generate the /rb-pkg/package.html pages.
    packages should be a list of Package objects.
    """
    total = len(packages)
    log.debug('Generating the pages of ' + str(total) + ' package(s)')
    for package in sorted(packages, key=lambda x: x.name):
        assert isinstance(package, Package)
        gen_history_page(package)
        pkg = package.name

        notes_uri = ''
        notes_file = NOTES_PATH + '/' + pkg + '_note.html'
        if os.access(notes_file, os.R_OK):
            notes_uri = NOTES_URI + '/' + pkg + '_note.html'

        for suite in SUITES:
            for arch in ARCHS:

                status = package.get_status(suite, arch)
                version = package.get_tested_version(suite, arch)
                build_date = package.get_build_date(suite, arch)
                if status == False:  # the package is not in the checked suite
                    continue
                log.debug('Generating the page of %s/%s/%s @ %s built at %s',
                          pkg, suite, arch, version, build_date)

                suitearch_section_html, default_view, reproducible = \
                    gen_suitearch_section(package, suite, arch)

                history = '{}/{}.html'.format(HISTORY_URI, pkg)
                project_links = html_project_links.substitute()

                html = renderer.render(package_page_template, {
                    'package': pkg,
                    'suite': suite,
                    'arch': arch,
                    'version': version,
                    'history': history,
                    'notes_uri': notes_uri,
                    'notify_maintainer': package.notify_maint,
                    'suitearch_section_html': suitearch_section_html,
                    'project_links_html': project_links,
                    'default_view': default_view,
                    'reproducible': reproducible,
                    'dashboard_url': DEBIAN_URL,
                })

                destfile = RB_PKG_PATH + '/' + suite + '/' + arch + '/' + \
                           pkg + '.html'
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

