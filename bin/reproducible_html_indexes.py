#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Based on reproducible_html_indexes.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build quite all index_* pages

from reproducible_common import *

"""
Reference doc for the folowing lists:

* queries is just a list of queries. They are referred further below.
  + every query must return only a list of package names (excpet count_total)
* pages is just a list of pages. It is actually a dictionary, where every
  element is a page. Every page has:
  + `title`: The page title
  + `body`: a list of dicts containing every section that made up the page.
    Every section has:
    - `icon_status`: the name of a icon (see join_status_icon())
    - `icon_link`: a link to hide below the icon
    - `query`: query to perform against the reproducible db to get the list of
      packages to show
    - `text` a string.Template instance with $tot (total of packages listed)
      and $percent (percentual on all sid packages)
    - `timely`: boolean value to enable to add $count and $count_total to the
      text, where:
      * $percent becomes count/count_total
      * $count_total being the number of all tested packages
      * $count being the len() of the query indicated by `query2`
    - `query2`: useful only if `timely` is True.
* global_pages is another list of pages. They follows the same structure of
  "normal" pages, but with a difference: every section is building for every
  (suite, arch) and the page itself is placed outside of any suite/arch
  directory.

Technically speaking, a package can be empty (we all love nonsense) but every
section must have at least a `query` defining what to file in.
"""

queries = {
    'count_total': 'SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}"',
    'scheduled': 'SELECT s.name FROM schedule AS p JOIN sources AS s ON p.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" ORDER BY p.date_scheduled',
    'reproducible_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="reproducible" ORDER BY r.build_date DESC',
    'reproducible_last24h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="reproducible" AND r.build_date > datetime("now", "-24 hours") ORDER BY r.build_date DESC',
    'reproducible_last48h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="reproducible" AND r.build_date > datetime("now", "-48 hours") ORDER BY r.build_date DESC',
    'reproducible_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="reproducible" ORDER BY name',
    'FTBR_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "unreproducible" ORDER BY build_date DESC',
    'FTBR_last24h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "unreproducible" AND build_date > datetime("now", "-24 hours") ORDER BY build_date DESC',
    'FTBR_last48h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "unreproducible" AND build_date > datetime("now", "-48 hours") ORDER BY build_date DESC',
    'FTBR_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "unreproducible" ORDER BY name',
    'FTBFS_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "FTBFS" ORDER BY build_date DESC',
    'FTBFS_last24h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "FTBFS" AND build_date > datetime("now", "-24 hours") ORDER BY build_date DESC',
    'FTBFS_last48h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "FTBFS" AND build_date > datetime("now", "-48 hours") ORDER BY build_date DESC',
    'FTBFS_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "FTBFS" ORDER BY name',
    '404_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "404" ORDER BY build_date DESC',
    '404_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "404" ORDER BY name',
    'not_for_us_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "not for us" ORDER BY build_date DESC',
    'not_for_us_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "not for us" ORDER BY name',
    'blacklisted_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "blacklisted" ORDER BY name'
}

pages = {
    'reproducible': {
        'title': 'Overview of packages in which built reproducibly',
        'body': [
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_all',
                'text': Template('$tot ($percent%) packages which built reproducibly in $suite/$arch:')
            }
        ]
    },
    'FTBR': {
        'title': 'Overview of packages which failed to build reproducibly',
        'body': [
            {
                'icon_status': 'FTBR',
                'query': 'FTBR_all',
                'text': Template('$tot ($percent%) packages which failed to build reproducibly in $suite/$arch:')
            }
        ]
    },
    'FTBFS': {
        'title': 'Overview of packages which failed to build from source',
        'body': [
            {
                'icon_status': 'FTBFS',
                'query': 'FTBFS_all',
                'text': Template('$tot ($percent%) packages where the sources failed to download in $suite/$arch:')
            }
        ]
    },
    '404': {
        'title': 'Overview of packages where the sources failed to download',
        'body': [
            {
                'icon_status': '404',
                'query': '404_all',
                'text': Template('$tot ($percent%) packages which failed to build from source in $suite/$arch:')
            }
        ]
    },
    'not_for_us': {
        'title': 'Overview of packages which should not be build on "amd64"',
        'body': [
            {
                'icon_status': 'not_for_us',
                'query': 'not_for_us_all',
                'text': Template('$tot ($percent%) packages which should not be build in $suite/$arch:')
            }
        ]
    },
    'blacklisted': {
        'title': 'Overview of packages which have been blacklisted',
        'body': [
            {
                'icon_status': 'blacklisted',
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages which have been blacklisted in $suite/$arch:')
            }
        ]
    },
    'scheduled': {
        'title': 'Overview of packages currently scheduled for testing for build reproducibility',
        'body': [
            {
                'query': 'scheduled',
                'text': Template('$tot packages are currently scheduled for testing in $suite/$arch:')
            },
            {
                'text': Template('A <a href="/index_scheduled.html">full scheduling overview</a> is also available.')
            }
        ]
    },
    'all_abc': {
        'title': 'Overview of reproducible builds of all tested packages (sorted alphabetically)',
        'body': [
            {
                'icon_status': 'FTBR',
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_all_abc',
                'text': Template('$tot packages ($percent%) failed to built reproducibly in total in $suite/$arch:')
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_all_abc',
                'text': Template('$tot packages ($percent%) failed to built from source in total $suite/$arch:')
            },
            {
                'icon_status': 'not_for_us',
                'icon_link': '/index_not_for_us.html',
                'query': 'not_for_us_all_abc',
                'text': Template('$tot ($percent%) packages which should not be build in $suite/$arch:')
            },
            {
                'icon_status': '404',
                'icon_link': '/index_404.html',
                'query': '404_all_abc',
                'text': Template('$tot ($percent%) source packages could not be downloaded in $suite/$arch:')
            },
            {
                'icon_status': 'blacklisted',
                'icon_link': '/index_blacklisted.html',
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages are blacklisted and will not be tested in $suite/$arch:')
            },
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_all_abc',
                'text': Template('$tot ($percent%) packages successfully built reproducibly in $suite/$arch:')
            },
        ]
    },
    'last_24h': {
        'title': 'Overview of reproducible builds of packages tested in the last 24h',
        'body': [
            {
                'icon_status': 'FTBR',
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_last24h',
                'query2': 'FTBR_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to built reproducibly in total, $tot of them in the last 24h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last24h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to built from source in total, $tot of them  in the last 24h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_last24h',
                'query2': 'reproducible_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'successfully built reproducibly in total, $tot of them in the last 24h in $suite/$arch:'),
                'timely': True
            },
        ]
    },
    'last_48h': {
        'title': 'Overview of reproducible builds of packages tested in the last 48h',
        'body': [
            {
                'icon_status': 'FTBR',
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_last48h',
                'query2': 'FTBR_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to built reproducibly in total, $tot of them in the last 48h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last48h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to built from source in total, $tot of them  in the last 48h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_last48h',
                'query2': 'reproducible_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'successfully built reproducibly in total, $tot of them in the last 48h in $suite/$arch:'),
                'timely': True
            },
        ]
    }
}

global_pages = {
    'scheduled': {
        'title': 'Overview of packages currently scheduled for testing for build reproducibility',
        'body': [
            {
                'query': 'scheduled',
                'text': Template('$tot packages are currently scheduled for testing in $suite/$arch:')
            }
        ]
    }
}


def build_leading_text_section(section, rows, suite, arch):
    html = '<p>\n' + tab
    total = len(rows)
    count_total = int(query_db(queries['count_total'].format(suite=suite, arch=arch))[0][0])
    try:
        percent = round(((total/count_total)*100), 1)
    except ZeroDivisionError:
        log.error('Looks like there are either no tested package or no ' +
                  'packages available at all. Maybe it\'s a new database?')
        percent = 0.0
    try:
        html += '<a href="' + section['icon_link'] + '" target="_parent">'
        no_icon_link = False
    except KeyError:
        no_icon_link = True  # to avoid closing the </a> tag below
    if section.get('icon_status'):
        html += '<img src="/static/'
        html += join_status_icon(section['icon_status'])[1]
        html += '" alt="reproducible icon" />'
    if not no_icon_link:
        html += '</a>'
    html += '\n' + tab
    if section.get('text') and section.get('timely') and section['timely']:
        count = len(query_db(queries[section['query2']].format(suite=suite, arch=arch)))
        percent = round(((count/count_total)*100), 1)
        html += section['text'].substitute(tot=total, percent=percent,
                                           count_total=count_total,
                                           count=count, suite=suite, arch=arch)
    elif section.get('text'):
        html += section['text'].substitute(tot=total, percent=percent,
                                           suite=suite, arch=arch)
    else:
        log.warning('There is no text for this section')
    html += '\n</p>\n'
    return html


def build_page_section(section, suite, arch):
    try:
        rows = query_db(queries[section['query']].format(suite=suite, arch=arch))
    except:
        print_critical_message('A query failed: ' + queries[section['query']])
        raise
    html = ''
    if not rows:     # there are no package in this set
        return html  # do not output anything on the page.
    html += build_leading_text_section(section, rows, suite, arch)
    html += '<p>\n' + tab + '<code>\n'
    for row in rows:
        pkg = row[0]
        url = RB_PKG_URI + '/' + suite + '/' + arch + '/' + pkg + '.html'
        html += tab*2 + '<a href="' + url + '" class="'
        if package_has_notes(pkg):
            html += 'noted'
        else:
            html += 'package'
        html += '">' + pkg + '</a>'
        html += get_trailing_icon(pkg, bugs) + '\n'
    html += tab + '</code>\n'
    html += '</p>'
    html = (tab*2).join(html.splitlines(True))
    return html


def build_page(page, suite=None, arch=None):
    if not suite:  # global page
        log.info('Building the ' + page + ' global index page...')
    else:
        log.info('Building the ' + page + ' index page for ' + suite + '/' +
                 arch + '...')
    html = ''
    for section in pages[page]['body']:
        if not suite:  # global page
            for lsuite in SUITES:
                for larch in ARCHES:
                    html += build_page_section(section, lsuite, larch)
        else:
            html += build_page_section(section, suite, arch)
    try:
        title = pages[page]['title']
    except KeyError:
        title = page
    if not suite:  # global page
        destfile = BASE + '/index_' + page + '.html'
        desturl = REPRODUCIBLE_URL + '/index_' + page + '.html'
    else:
        destfile = BASE + '/' + suite + '/' + arch + '/index_' + page + '.html'
        desturl = REPRODUCIBLE_URL + '/' + suite + '/' + arch + '/index_' + \
                  page + '.html'
    write_html_page(title=title, body=html, destfile=destfile, suite=suite, style_note=True)
    log.info('"' + title + '" now available at ' + desturl)


bugs = get_bugs()

if __name__ == '__main__':
    for suite in SUITES:
        for arch in ARCHES:
            for page in pages.keys():
                build_page(page, suite, arch)
    for page in global_pages.keys():
        build_page(page)
