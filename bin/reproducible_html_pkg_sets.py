#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2016 Valerie Young <spectranaut@riseup.net>
# Based on reproducible_html_pkg_sets.sh:
#           © 2014-2016 Holger Levsen <holger@layer-acht.org>
#           © 2015 Mattia Rizzolo <mattia@debian.org>
# Licensed under GPL-2
#
# Depends: python3, reproducible_common, time, sqlite3, pystache, csv
#
# Build rb-pkg pages (the pages that describe the package status)

from reproducible_common import *

import csv
import time
import sqlite3
import pystache
from collections import OrderedDict

# Templates used for creating package pages
renderer = pystache.Renderer()
pkgset_navigation_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'pkgset_navigation'))
pkgset_details_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'pkgset_details'))
pkg_legend_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'pkg_symbol_legend'))

# we only do stats up until yesterday
YESTERDAY = (datetime.now()-timedelta(days=1)).strftime('%Y-%m-%d')

def gather_meta_stats(suite, arch, pkgset_name):
    pkgset_file = os.path.join(PKGSET_DEF_PATH, 'meta_pkgsets-' + suite,
                               pkgset_name + '.pkgset')

    try:
        with open(pkgset_file) as f:
            pkgset_list = [s.strip() for s in f.readlines()]
    except FileNotFoundError:
        log.warning('No meta package set information exists at ' + pkgset_file)
        return {}

    if not pkgset_list:
        log.warning('No packages listed for package set: ' + pkgset_name)
        return {}

    package_where = "s.name in ('" + ("', '").join(pkgset_list) + "')"
    root_query = """
        SELECT s.name
        FROM results AS r
        JOIN sources AS s ON r.package_id=s.id
        WHERE s.suite='{suite}'
        AND s.architecture='{arch}'
        AND date(r.build_date)<='{date}'
        AND {package_where}
    """.format(suite=suite, arch=arch, date=YESTERDAY,
               package_where=package_where)

    stats = {}
    good = query_db(root_query + "AND r.status = 'reproducible' " +
                    "ORDER BY s.name;")
    stats['good'] = [t[0] for t in good]
    stats['count_good'] = len(stats['good'])

    bad = query_db(root_query + "AND r.status = 'unreproducible'" +
                   "ORDER BY r.build_date;")
    stats['bad'] = [t[0] for t in bad]
    stats['count_bad'] = len(stats['bad'])

    ugly = query_db(root_query + "AND r.status = 'FTBFS'" +
                    "ORDER BY r.build_date;")
    stats['ugly'] = [t[0] for t in ugly]
    stats['count_ugly'] = len(stats['ugly'])

    rest = query_db(root_query + "AND (r.status != 'FTBFS' AND " +
                    "r.status != 'unreproducible' AND " +
                    "r.status != 'reproducible') ORDER BY r.build_date;")
    stats['rest'] = [t[0] for t in rest]
    stats['count_rest'] = len(stats['rest'])

    stats['count_all'] = (stats['count_good'] + stats['count_bad'] +
                         stats['count_ugly'] + stats['count_rest'])
    stats['count_all'] = stats['count_all'] if stats['count_all'] else 1
    stats['percent_good'] = percent(stats['count_good'], stats['count_all'])
    stats['percent_bad'] = percent(stats['count_bad'], stats['count_all'])
    stats['percent_ugly'] = percent(stats['count_ugly'], stats['count_all'])
    stats['percent_rest'] = percent(stats['count_rest'], stats['count_all'])
    return stats


def update_stats(suite, arch, stats, pkgset_name):
    result = query_db("""
            SELECT datum, meta_pkg, suite
            FROM stats_meta_pkg_state
            WHERE datum = '{date}' AND suite = '{suite}'
            AND architecture = '{arch}' AND meta_pkg = '{name}'
        """.format(date=YESTERDAY, suite=suite, arch=arch, name=pkgset_name))

    # if there is not a result for this day, add one
    if not result:
        insert = "INSERT INTO stats_meta_pkg_state VALUES ('{date}', " + \
                 "'{suite}', '{arch}', '{pkgset_name}', '{count_good}', " + \
                 "'{count_bad}', '{count_ugly}', '{count_rest}')"
        query_db(insert.format(date=YESTERDAY, suite=suite, arch=arch,
            pkgset_name=pkgset_name, count_good=stats['count_good'],
            count_bad=stats['count_bad'], count_ugly=stats['count_ugly'],
            count_rest=stats['count_rest']))
        log.info("Updating db entry for meta pkgset %s in %s/%s on %s.",
                 pkgset_name, suite, arch, YESTERDAY)
    else:
        log.debug("Not updating db entry for meta pkgset %s in %s/%s on %s as one exists already.",
                 pkgset_name, suite, arch, YESTERDAY)


def create_pkgset_navigation(suite, arch, view=None):
    # Group the package sets by section
    sections = OrderedDict()
    for index in range(1, len(META_PKGSET)+1):
        pkgset_name = META_PKGSET[index][0]
        pkgset_section = META_PKGSET[index][1]
        pkgset = {
            'class': "active" if pkgset_name == view else "",
            'pkgset_name': pkgset_name,
        }
        thumb_file, thumb_href = stats_thumb_file_href(suite, arch, pkgset_name)
        # if the graph image doesn't exist, don't include it in the context
        if os.access(thumb_file, os.R_OK):
            pkgset['thumb'] = thumb_href
        # add the package set to the appropriate section
        sections.setdefault(pkgset_section, []).append(pkgset)

    context = {
        'suite': suite,
        'arch': arch,
        'pkgset_page': True if view else False
    }
    context['package_set_sections'] = \
        [{'section': s, 'pkgsets': sections[s]} for s in sections]
    return renderer.render(pkgset_navigation_template, context)


def create_index_page(suite, arch):
    title = 'Package sets in %s/%s' % (suite, arch)
    body = create_pkgset_navigation(suite, arch)
    destfile = os.path.join(DEBIAN_BASE, suite, arch,
                            "index_pkg_sets.html")
    suite_arch_nav_template = DEBIAN_URI + \
                              '/{{suite}}/{{arch}}/index_pkg_sets.html'
    left_nav_html = create_main_navigation(
        suite=suite,
        arch=arch,
        displayed_page='pkg_set',
        suite_arch_nav_template=suite_arch_nav_template,
        ignore_experimental=True,
    )
    log.info("Creating pkgset index page for %s/%s.",
             suite, arch)
    write_html_page(title=title, body=body, destfile=destfile,
                    left_nav_html=left_nav_html)


def gen_other_arch_context(archs, suite, pkgset_name):
    context = []
    page = "pkg_set_" + pkgset_name + ".html"
    for arch in archs:
        context.append({
            'arch': arch,
            'link': "/".join(['/debian', suite, arch, page])
        })
    return context


def stats_png_file_href(suite, arch, pkgset_name):
    return (os.path.join(DEBIAN_BASE, suite, arch, 'stats_meta_pkg_state_' +
                         pkgset_name + '.png'),
            "/".join(["/debian", suite, arch, 'stats_meta_pkg_state_' +
                      pkgset_name + '.png'])
    )


def stats_thumb_file_href(suite, arch, pkgset_name):
    return (os.path.join(DEBIAN_BASE, suite, arch, 'stats_meta_pkg_state_' +
                         pkgset_name + '-thumbnail.png'),
            "/".join(["/debian", suite, arch, 'stats_meta_pkg_state_' +
                      pkgset_name + '-thumbnail.png'])
    )


def create_pkgset_page_and_graphs(suite, arch, stats, pkgset_name):
    html_body = ""
    html_body += create_pkgset_navigation(suite, arch, pkgset_name)
    pkgset_context = ({
        'pkgset_name': pkgset_name,
        'suite': suite,
        'arch': arch,
        'pkg_symbol_legend_html':
            renderer.render(pkg_legend_template, {}),
    })

    png_file, png_href = stats_png_file_href(suite, arch, pkgset_name)
    thumb_file, thumb_href = stats_thumb_file_href(suite, arch, pkgset_name)
    yesterday_timestamp = (datetime.now()-timedelta(days=1)).timestamp()

    if ( not os.access(png_file, os.R_OK) or
         os.stat(png_file).st_mtime < yesterday_timestamp ):
        create_pkgset_graph(png_file, suite, arch, pkgset_name)
        check_call(['convert', png_file, '-adaptive-resize', '160x80',
                    thumb_file])

    pkgset_context['png'] = png_href
    other_archs = [a for a in ARCHS if a != arch]
    pkgset_context['other_archs']= \
        gen_other_arch_context(other_archs, suite, pkgset_name)

    pkgset_context['status_details'] = []

    status_cutename_descriptions = [
        ('unreproducible', 'bad', 'failed to build reproducibly'),
        ('FTBFS', 'ugly', 'failed to build from source'),
        ('rest', 'rest',
         'are either blacklisted, not for us or cannot be downloaded'),
        ('reproducible', 'good', 'successfully build reproducibly'),
    ]

    for (status, cutename, description) in status_cutename_descriptions:
        icon_html = ''
        if status == 'rest':
            for s in ['not_for_us', 'blacklisted', '404']:
                s, icon, spokenstatus = get_status_icon(s)
                icon_html += gen_status_link_icon(s, None, icon, suite, arch)
        else:
            status, icon, spokenstatus = get_status_icon(status)
            icon_html = gen_status_link_icon(status, None, icon, suite, arch)

        details_context = {
            'icon_html': icon_html,
            'description': description,
            'package_list_html': link_packages(stats[cutename], suite, arch, bugs),
            'status_count': stats["count_" + cutename],
            'status_percent': stats["percent_" + cutename],
        }

        if (status in ('reproducible', 'unreproducible') or
                stats["count_" + cutename] != 0):
            pkgset_context['status_details'].append(details_context)

    html_body += renderer.render(pkgset_details_template, pkgset_context)
    title = '%s package set for %s/%s' % \
            (pkgset_name, suite, arch)
    page = "pkg_set_" + pkgset_name + ".html"
    destfile = os.path.join(DEBIAN_BASE, suite, arch, page)
    suite_arch_nav_template = DEBIAN_URI + '/{{suite}}/{{arch}}/' + page
    left_nav_html = create_main_navigation(
        suite=suite,
        arch=arch,
        displayed_page='pkg_set',
        suite_arch_nav_template=suite_arch_nav_template,
        ignore_experimental=True,
    )
    log.info("Creating meta pkgset page for %s in %s/%s.",
              pkgset_name, suite, arch)
    write_html_page(title=title, body=html_body, destfile=destfile,
                    left_nav_html=left_nav_html, include_pkgset_js=True)


def create_pkgset_graph(png_file, suite, arch, pkgset_name):
    table = "stats_meta_pkg_state"
    columns = ["datum", "reproducible", "unreproducible", "FTBFS", "other"]
    where = "WHERE suite = '%s' AND architecture = '%s' AND meta_pkg = '%s'" % \
            (suite, arch, pkgset_name)
    if arch == 'i386':
        # i386 only has pkg sets since later to make nicer graphs
        # (date added in commit 7f2525f7)
        where += " AND datum >= '2016-05-06'"
    query = "SELECT {fields} FROM {table} {where} ORDER BY datum".format(
        fields=", ".join(columns), table=table, where=where)
    result = query_db(query)
    result_rearranged = [dict(zip(columns, row)) for row in result]

    with create_temp_file(mode='w') as f:
        csv_tmp_file = f.name
        csv_writer = csv.DictWriter(f, columns)
        csv_writer.writeheader()
        csv_writer.writerows(result_rearranged)
        f.flush()

        graph_command = os.path.join(BIN_PATH, "make_graph.py")
        main_label = "Reproducibility status for packages in " + suite + \
                     " from " + pkgset_name
        y_label = "Amount (" + pkgset_name + " packages)"
        log.info("Creating graph for meta pkgset %s in %s/%s.",
                  pkgset_name, suite, arch)
        check_call([graph_command, csv_tmp_file, png_file, '4', main_label,
                    y_label, '1920', '960'])


bugs = get_bugs()
for arch in ARCHS:
    for suite in SUITES:
        if suite == 'experimental':
            continue
        create_index_page(suite, arch)
        for index in META_PKGSET:
            pkgset_name = META_PKGSET[index][0]
            stats = gather_meta_stats(suite, arch, pkgset_name)
            if (stats):
                update_stats(suite, arch, stats, pkgset_name)
                create_pkgset_page_and_graphs(suite, arch, stats, pkgset_name)
