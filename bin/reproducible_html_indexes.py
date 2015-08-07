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
  + `header`: (optional) sane html to be printed on top of the page
  + `header_query`: (optional): the output of this query is put inside "tot" of
    the string above
  + `body`: a list of dicts containing every section that made up the page.
    Every section has:
    - `icon_status`: the name of a icon (see join_status_icon())
    - `icon_link`: a link to hide below the icon
    - `query`: query to perform against the reproducible db to get the list of
      packages to show
    - `text` a string. Template instance with $tot (total of packages listed)
      and $percent (percentage of all packages)
    - `timely`: boolean value to enable to add $count and $count_total to the
      text, where:
      * $percent becomes count/count_total
      * $count_total being the number of all tested packages
      * $count being the len() of the query indicated by `query2`
    - `query2`: useful only if `timely` is True.
    - `nosuite`: if true do not iterate over the suite/archs, use only the
      defaults
  + global: if true, then the page will saved on the root of rb.d.n, and:
    - the query also takes the value "status"
    - force the suite/arch to the defaults
  + notes: if true the query also takes the value "status"

Technically speaking, a page can be empty (we all love nonsense) but every
section must have at least a `query` defining what to file in.
"""

# filter_query is defined in reproducible_common.py and excludes some FTBFS issues
queries = {
    'count_total': 'SELECT COUNT(*) FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}"',
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
    'FTBFS_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "FTBFS" ORDER BY s.name',
    'FTBFS_filtered': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status = "FTBFS" AND r.package_id NOT IN (SELECT n.package_id FROM NOTES AS n WHERE ' + filter_query + ' ) ORDER BY s.name',
    'FTBFS_caused_by_us': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status = "FTBFS" AND r.package_id IN (SELECT n.package_id FROM NOTES AS n WHERE ' + filter_query + ' ) ORDER BY s.name',
    '404_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "404" ORDER BY build_date DESC',
    '404_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "404" ORDER BY name',
    'depwait_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "depwait" ORDER BY build_date DESC',
    'depwait_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "depwait" ORDER BY name',
    'depwait_last24h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "depwait" AND build_date > datetime("now", "-24 hours") ORDER BY name',
    'depwait_last48h': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "depwait" AND build_date > datetime("now", "-48 hours") ORDER BY name',
    'not_for_us_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "not for us" ORDER BY build_date DESC',
    'not_for_us_all_abc': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "not for us" ORDER BY name',
    'blacklisted_all': 'SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND status = "blacklisted" ORDER BY name',
    'notes': 'SELECT s.name FROM sources AS s JOIN notes AS n ON n.package_id=s.id JOIN results AS r ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="{status}" ORDER BY r.build_date DESC',
    'no_notes': 'SELECT s.name FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="{status}" AND s.id NOT IN (SELECT package_id FROM notes) ORDER BY r.build_date DESC',
    'notification': 'SELECT s.name FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.suite="{suite}" AND s.architecture="{arch}" AND r.status="{status}" AND s.notify_maintainer = 1',
}

pages = {
    'reproducible': {
        'title': 'Packages in {suite}/{arch} which built reproducibly',
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
        'title': 'Packages in {suite}/{arch} which failed to build reproducibly',
        'body': [
            {
                'icon_status': 'FTBR',
                'query': 'FTBR_all',
                'text': Template('$tot ($percent%) packages which failed to build reproducibly in $suite/$arch:')
            }
        ]
    },
    'FTBFS': {
        'title': 'Packages in {suite}/{arch} which failed to build from source',
        'body': [
            {
                'icon_status': 'FTBFS',
                'query': 'FTBFS_filtered',
                'text': Template('$tot ($percent%) packages which failed to build from source in $suite/$arch: (this list is filtered and only shows unexpected ftbfs issues - see the list below for expected failures.)')
            },
            {
                'icon_status': 'FTBFS',
                'query': 'FTBFS_caused_by_us',
                'text': Template('$tot ($percent%) packages which failed to build from source in $suite/$arch due to our changes in the toolchain or due to our setup.\n This list includes packages tagged ' + filter_html + '.'),
            }
        ]
    },
    '404': {
        'title': 'Packages in {suite}/{arch} where the sources failed to download',
        'body': [
            {
                'icon_status': '404',
                'query': '404_all',
                'text': Template('$tot ($percent%) packages where the sources failed to download in $suite/$arch:')
            }
        ]
    },
    'depwait': {
        'title': 'Packages in {suite}/{arch} where the build dependencies failed to be satisfied',
        'body': [
            {
                'icon_status': 'depwait',
                'query': 'depwait_all',
                'text': Template('$tot ($percent%) packages where the build dependencies failed to be satisfied. Note that temporary failures to due network problems are automatically rescheduled every 4 hours.')
            }
        ]
    },
    'not_for_us': {
        'title': 'Packages in {suite}/{arch} which should not be build on "amd64"',
        'body': [
            {
                'icon_status': 'not_for_us',
                'query': 'not_for_us_all',
                'text': Template('$tot ($percent%) packages which should not be build in $suite/$arch:')
            }
        ]
    },
    'blacklisted': {
        'title': 'Packages in {suite}/{arch} which have been blacklisted',
        'body': [
            {
                'icon_status': 'blacklisted',
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages which have been blacklisted in $suite/$arch:')
            }
        ]
    },
    'all_abc': {
        'title': 'Alphabetically sorted overview of all tested packages in {suite}/{arch})',
        'body': [
            {
                'icon_status': 'FTBR',
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_all_abc',
                'text': Template('$tot packages ($percent%) failed to build reproducibly in total in $suite/$arch:')
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_all_abc',
                'text': Template('$tot packages ($percent%) failed to build from source in total $suite/$arch:')
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
                'icon_status': 'depwait',
                'icon_link': '/index_depwait.html',
                'query': 'depwait_all_abc',
                'text': Template('$tot ($percent%) source packages failed to satisfy their build-dependencies:')
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
        'title': 'Packages in {suite}/{arch} tested in the last 24h for build reproducibility',
        'body': [
            {
                'icon_status': 'FTBR',
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_last24h',
                'query2': 'FTBR_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build reproducibly in total, $tot of them in the last 24h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last24h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build from source in total, $tot of them  in the last 24h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'depwait',
                'icon_link': '/index_depwait.html',
                'query': 'depwait_last24h',
                'query2': 'depwait_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to satisfy their build-dependencies, $tot of them  in the last 24h in $suite/$arch:'),
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
        'title': 'Packages in {suite}/{arch} tested in the last 48h for build reproducibility',
        'body': [
            {
                'icon_status': 'FTBR',
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_last48h',
                'query2': 'FTBR_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build reproducibly in total, $tot of them in the last 48h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last48h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build from source in total, $tot of them  in the last 48h in $suite/$arch:'),
                'timely': True
            },
            {
                'icon_status': 'depwait',
                'icon_link': '/index_depwait.html',
                'query': 'depwait_last48h',
                'query2': 'depwait_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to satisfy their build-dependencies, $tot of them  in the last 48h in $suite/$arch:'),
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
    },
    'notes': {
        'notes': True,
        'title': 'Packages with notes',
        'header': '<p>There are {tot} packages with notes in {suite}/{arch}.</p>',
        'header_query': 'SELECT count(*) FROM (SELECT * FROM sources AS s JOIN notes AS n ON n.package_id=s.id WHERE s.suite="{suite}" AND s.architecture="{arch}" GROUP BY s.name) AS tmp',
        'body': [
            {
                'icon_status': 'FTBR',
                'db_status': 'unreproducible',
                'icon_link': '/index_FTBR.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot unreproducible packages in $suite/$arch:')
            },
            {
                'icon_status': 'FTBFS',
                'db_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot FTBFS packages in $suite/$arch:')
            },
            {
                'icon_status': 'depwait',
                'db_status': 'depwait',
                'icon_link': '/index_depwait.html',
                'query': 'depwait_all_abc',
                'text': Template('$tot ($percent%) source packages failed to satisfy their build-dependencies:')
            },
            {
                'icon_status': 'not_for_us',
                'db_status': 'not for us',
                'icon_link': '/index_not_for_us.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot not for us packages in $suite/$arch:')
            },
            {
                'icon_status': 'blacklisted',
                'db_status': 'blacklisted',
                'icon_link': '/index_blacklisted.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot blacklisted packages in $suite/$arch:')
            },
            {
                'icon_status': 'reproducible',
                'db_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot reproducible packages in $suite/$arch:')
            }
        ]
    },
    'no_notes': {
        'notes': True,
        'notes_hint': True,
        'title': 'Packages without notes',
        'header': '<p>There are {tot} faulty packages without notes in {suite}/{arch}.{hint}</p>',
        'header_query': 'SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE r.status IN ("unreproducible", "FTBFS", "blacklisted") AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite="{suite}" AND s.architecture="{arch}")',
        'body': [
            {
                'icon_status': 'FTBR',
                'db_status': 'unreproducible',
                'icon_link': '/index_FTBR.html',
                'query': 'no_notes',
                'text': Template('$tot unreproducible packages in $suite/$arch:')
            },
            {
                'icon_status': 'FTBFS',
                'db_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'no_notes',
                'text': Template('$tot FTBFS packages in $suite/$arch:')
            },
            {
                'icon_status': 'blacklisted',
                'db_status': 'blacklisted',
                'icon_link': '/index_blacklisted.html',
                'query': 'no_notes',
                'text': Template('$tot blacklisted packages in $suite/$arch:')
            }
        ]
    },
    'notify': {
        'global': True,
        'notes': True,
        'nosuite': True,
        'title': 'Packages with notification enabled',
        'header': '<p>The following {tot} packages in {suite}/{arch} have notifications enabled. On status changes (e.g. reproducible → unreproducible) the system sends an email to $srcpackage@packages.debian.org, notifying the maintainer and relevant parties.  (You can subscribe through the PTS or Tracker if you are interested in such emails).<br />Please ask us to enable notifications for your package(s) in our IRC channel #debian-reproducible or via <a href="mailto:reproducible-builds@lists.alioth.debian.org">mail</a>!</p>',
        'header_query': 'SELECT COUNT(*) FROM sources WHERE suite="{suite}" AND architecture="{arch}" AND notify_maintainer = 1',
        'body': [
            {
                'icon_status': 'FTBR',
                'db_status': 'unreproducible',
                'icon_link': '/index_FTBR.html',
                'query': 'notification',
                'text': Template('$tot unreproducible packages in $suite/$arch:'),
                'nosuite': True
            },
            {
                'icon_status': 'FTBFS',
                'db_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'notification',
                'text': Template('$tot FTBFS packages in $suite/$arch:'),
                'nosuite': True
            },
            {
                'icon_status': 'reproducible',
                'db_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'notification',
                'text': Template('$tot reproducible packages in $suite/$arch:'),
                'nosuite': True
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


def build_page_section(page, section, suite, arch):
    try:
        if pages[page].get('global') and pages[page]['global']:
            suite = defaultsuite if not suite else suite
            arch = defaultarch if not arch else arch
        if pages[page].get('notes') and pages[page]['notes']:
            query = queries[section['query']].format(
                status=section['db_status'], suite=suite, arch=arch)
        else:
            query = queries[section['query']].format(suite=suite, arch=arch)
        rows = query_db(query)
    except:
        print_critical_message('A query failed: ' + query)
        raise
    html = ''
    footnote = True if rows else False
    if not rows:                            # there are no package in this set
        log.debug('empty query: ' + query)  # do not output anything.
        return (html, footnote)
    html += build_leading_text_section(section, rows, suite, arch)
    html += '<p>\n' + tab + '<code>\n'
    for row in rows:
        pkg = row[0]
        html += tab*2 + link_package(pkg, suite, arch, bugs)
    else:
        html += tab + '</code>\n'
        html += '</p>'
    if section.get('bottom'):
        html += section['bottom']
    html = (tab*2).join(html.splitlines(True))
    return (html, footnote)


def build_page(page, suite=None, arch=None):
    gpage = False
    if pages[page].get('global') and pages[page]['global']:
        gpage = True
        suite = defaultsuite
        arch = defaultarch
    if not gpage and suite and not arch:
        print_critical_message('The architecture was not specified while ' +
                               'building a suite-specific page.')
        sys.exit(1)
    if gpage:
        log.debug('Building the ' + page + ' global index page...')
        title = pages[page]['title']
    else:
        log.debug('Building the ' + page + ' index page for ' + suite + '/' +
                 arch + '...')
        title = pages[page]['title'].format(suite=suite, arch=arch)
    page_sections = pages[page]['body']
    html = ''
    footnote = False
    if pages[page].get('header'):
        if pages[page].get('notes_hint') and pages[page]['notes_hint'] and suite == defaultsuite:
            hint = ' <em>These</em> are the packages with failures that <em>still need to be investigated</em>.'
        else:
            hint = ''
        if pages[page].get('header_query'):
            html += pages[page]['header'].format(
                tot=query_db(pages[page]['header_query'].format(suite=suite, arch=arch))[0][0], suite=suite, arch=arch, hint=hint)
        else:
            html += pages[page].get('header')
    for section in page_sections:
        if gpage:
            if section.get('nosuite') and section['nosuite']:  # only defaults
                html += build_page_section(page, section, None, None)[0]
            else:
                for suite in SUITES:
                    for arch in ARCHS:
                        log.debug('global page §' + section['db_status'] +
                                  ' in ' + page + ' for ' + suite + '/' + arch)
                        html += build_page_section(page, section, suite, arch)[0]
            footnote = True
        else:
            html1, footnote1 = build_page_section(page, section, suite, arch)
            html += html1
            footnote = True if footnote1 else footnote
    if gpage:
        destfile = BASE + '/index_' + page + '.html'
        desturl = REPRODUCIBLE_URL + '/index_' + page + '.html'
        suite = defaultsuite  # used for the links generated by write_html_page
    else:
        destfile = BASE + '/' + suite + '/' + arch + '/index_' + page + '.html'
        desturl = REPRODUCIBLE_URL + '/' + suite + '/' + arch + '/index_' + \
                  page + '.html'
    write_html_page(title=title, body=html, destfile=destfile, suite=suite, style_note=footnote)
    log.info('"' + title + '" now available at ' + desturl)


def generate_schedule():
    """ the schedule is very different than others index pages """
    log.info('Building the schedule index page...')
    title = 'Packages currently scheduled for testing for build reproducibility'
    query = 'SELECT sch.date_scheduled, s.suite, s.architecture, s.name ' + \
            'FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id ' + \
            'WHERE sch.date_build_started = "" ORDER BY sch.date_scheduled'
    text = Template('$tot packages are currently scheduled for testing:')
    html = ''
    rows = query_db(query)
    html += build_leading_text_section({'text': text}, rows, defaultsuite, defaultarch)
    html += '<p><table class="scheduled">\n' + tab
    html += '<tr><th>#</th><th>scheduled at</th><th>suite</th>'
    html += '<th>architecture</th><th>source package</th></tr>\n'
    for row in rows:
        # 0: date_scheduled, 1: suite, 2: arch, 3: pkg name
        pkg = row[3]
        url = RB_PKG_URI + '/' + row[1] + '/' + row[2] + '/' + pkg + '.html'
        html += tab + '<tr><td>&nbsp;</td><td>' + row[0] + '</td>'
        html += '<td>' + row[1] + '</td><td>' + row[2] + '</td><td><code>'
        html += link_package(pkg, row[1], row[2], bugs)
        html += '</code></td></tr>\n'
    html += '</table></p>\n'
    destfile = BASE + '/index_scheduled.html'
    desturl = REPRODUCIBLE_URL + '/index_scheduled.html'
    write_html_page(title=title, body=html, destfile=destfile, style_note=True)


bugs = get_bugs()

if __name__ == '__main__':
    generate_schedule()
    for suite in SUITES:
        for arch in ARCHS:
            for page in pages.keys():
                build_page(page, suite, arch)
