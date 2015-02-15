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

Technically speaking, a package can be empty (we all love nonsense) but every
section must have at least a `query` defining what to file in.
"""

queries = {
    'scheduled': 'SELECT name FROM sources_scheduled ORDER BY date_scheduled',
    'reproducible_all': 'SELECT name FROM source_packages WHERE status = "reproducible" ORDER BY build_date DESC',
    'reproducible_last24h': 'SELECT name FROM source_packages WHERE status = "reproducible" AND build_date > datetime("now", "-24 hours") ORDER BY build_date DESC',
    'reproducible_last48h': 'SELECT name FROM source_packages WHERE status = "reproducible" AND build_date > datetime("now", "-48 hours") ORDER BY build_date DESC',
    'reproducible_all_abc': 'SELECT name FROM source_packages WHERE status = "reproducible" ORDER BY name',
    'FTBR_all': 'SELECT name FROM source_packages WHERE status = "unreproducible" ORDER BY build_date DESC',
    'FTBR_last24h': 'SELECT name FROM source_packages WHERE status = "unreproducible" AND build_date > datetime("now", "-24 hours") ORDER BY build_date DESC',
    'FTBR_last48h': 'SELECT name FROM source_packages WHERE status = "unreproducible" AND build_date > datetime("now", "-48 hours") ORDER BY build_date DESC',
    'FTBR_all_abc': 'SELECT name FROM source_packages WHERE status = "unreproducible" ORDER BY name',
    'FTBFS_all': 'SELECT name FROM source_packages WHERE status = "FTBFS" ORDER BY build_date DESC',
    'FTBFS_last24h': 'SELECT name FROM source_packages WHERE status = "FTBFS" AND build_date > datetime("now", "-24 hours") ORDER BY build_date DESC',
    'FTBFS_last48h': 'SELECT name FROM source_packages WHERE status = "FTBFS" AND build_date > datetime("now", "-48 hours") ORDER BY build_date DESC',
    'FTBFS_all_abc': 'SELECT name FROM source_packages WHERE status = "FTBFS" ORDER BY name',
    '404_all': 'SELECT name FROM source_packages WHERE status = "404" ORDER BY build_date DESC',
    '404_all_abc': 'SELECT name FROM source_packages WHERE status = "404" ORDER BY name',
    'not_for_us_all': 'SELECT name FROM source_packages WHERE status = "not for us" ORDER BY build_date DESC',
    'not_for_us_all_abc': 'SELECT name FROM source_packages WHERE status = "not for us" ORDER BY name',
    'blacklisted_all': 'SELECT name FROM source_packages WHERE status = "blacklisted" ORDER BY name'
}

pages = {
    'reproducible': {
        'title': 'Overview of packages which built reproducibly',
        'body': [
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_all',
                'text': Template('$tot ($percent%) packages which built reproducibly:')
            }
        ]
    },
    'FTBR': {
        'title': 'Overview of packages which failed to build reproducibly',
        'body': [
            {
                'icon_status': 'FTBR',
                'query': 'FTBR_all',
                'text': Template('$tot ($percent%) packages which failed to build reproducibly:')
            }
        ]
    },
    'FTBFS': {
        'title': 'Overview of packages which failed to build from source',
        'body': [
            {
                'icon_status': 'FTBFS',
                'query': 'FTBFS_all',
                'text': Template('$tot ($percent%) packages where the sources failed to download:')
            }
        ]
    },
    '404': {
        'title': 'Overview of packages where the sources failed to download',
        'body': [
            {
                'icon_status': '404',
                'query': '404_all',
                'text': Template('$tot ($percent%) packages which failed to build from source:')
            }
        ]
    },
    'not_for_us': {
        'title': 'Overview of packages which should not be build on "amd64"',
        'body': [
            {
                'icon_status': 'not_for_us',
                'query': 'not_for_us_all',
                'text': Template('$tot ($percent%) packages which should not be build on "amd64":')
            }
        ]
    },
    'blacklisted': {
        'title': 'Overview of packages which have been blacklisted',
        'body': [
            {
                'icon_status': 'blacklisted',
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages which have been blacklisted:')
            }
        ]
    },
    'schduled': {
        'title': 'Overview of packages currently scheduled for testing for build reproducibility',
        'body': [
            {
                'query': 'scheduled',
                'text': Template('$tot packages are currently scheduled for testing:')
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
                'text': Template('$tot packages ($percent%) failed to built reproducibly in total:')
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_all_abc',
                'text': Template('$tot packages ($percent%) failed to built from source in total:')
            },
            {
                'icon_status': 'not_for_us',
                'icon_link': '/index_not_for_us.html',
                'query': 'not_for_us_all_abc',
                'text': Template('$tot ($percent%) packages which are neither Architecture: "any", "all", "amd64", "linux-any", "linux-amd64" nor "any-amd64":')
            },
            {
                'icon_status': '404',
                'icon_link': '/index_404.html',
                'query': '404_all_abc',
                'text': Template('$tot ($percent%) source packages could not be downloaded:')
            },
            {
                'icon_status': 'blacklisted',
                'icon_link': '/index_blacklisted.html',
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages are blacklisted and will not be tested here:')
            },
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_all_abc',
                'text': Template('$tot ($percent%) packages successfully built reproducibly:')
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
                'text': Template('$count packages ($percent% of ${count_total}) ' + \
                                 'failed to built reproducibly in total, $tot of them in the last 24h:'),
                'timely': True
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last24h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' + \
                                 'failed to built from source in total, $tot of them  in the last 24h:'),
                'timely': True
            },
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_last24h',
                'query2': 'reproducible_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' + \
                                 'successfully built reproducibly in total, $tot of them in the last 24h:'),
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
                'text': Template('$count packages ($percent% of ${count_total}) ' + \
                                 'failed to built reproducibly in total, $tot of them in the last 48h:'),
                'timely': True
            },
            {
                'icon_status': 'FTBFS',
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last48h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' + \
                                 'failed to built from source in total, $tot of them  in the last 48h:'),
                'timely': True
            },
            {
                'icon_status': 'reproducible',
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_last48h',
                'query2': 'reproducible_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' + \
                                 'successfully built reproducibly in total, $tot of them in the last 48h:'),
                'timely': True
            },
        ]
    }
}


def build_leading_text_section(section, rows):
    html = '<p>\n' + tab
    total = len(rows)
    percent = round(((total/count_total)*100), 1)  # count_total is
    try:                                           # defined in common
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
        count = len(query_db(queries[section['query2']]))
        percent = round(((count/count_total)*100), 1)
        html += section['text'].substitute(tot=total, percent=percent,
                                           count_total=count_total,
                                           count=count)
    elif section.get('text'):
        html += section['text'].substitute(tot=total, percent=percent)
    else:
        log.warning('There is no text for this section')
    html += '\n</p>\n'
    return html


def build_page_section(section):
    try:
        rows = query_db(queries[section['query']])
        # remember: this is a list of tuples! so while looping the package
        # name will be pkg[0] and not simply pkg.
    except:
        print_critical_message('A query failed: ' + queries[section['query']])
        raise
    html = ''
    if not rows:     # there are no package in this set
        return html  # do not output anything on the page.
    html += build_leading_text_section(section, rows)
    html += '<p>\n' + tab + '<code>\n'
    for pkg in rows:
        url = RB_PKG_URI + '/' + pkg[0] + '.html'
        html += tab*2 + '<a href="' + url + '" class="'
        if package_has_notes(pkg[0]):
            html += 'noted'
        else:
            html += 'package'
        html += '">' + pkg[0] + '</a>'
        html += get_trailing_icon(pkg[0], bugs) + '\n'
    html += tab + '</code>\n'
    html += '</p>'
    html = (tab*2).join(html.splitlines(True))
    return html


def build_page(page):
    log.info('Building the ' + page + ' index page...')
    html = ''
    for section in pages[page]['body']:
        html += build_page_section(section)
    try:
        title = pages[page]['title']
    except KeyError:
        title = page
    destfilename = page
    destfile = BASE + '/index_' + destfilename + '.html'
    desturl = REPRODUCIBLE_URL + '/index_' + destfilename + '.html'
    write_html_page(title=title, body=html, destfile=destfile, style_note=True)
    log.info('"' + title + '" now available at ' + desturl)


if __name__ == '__main__':
    bugs = get_bugs()
    print(bugs)
    for page in pages.keys():
        build_page(page)
