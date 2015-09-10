#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
# based on ~jenkins.d.n:~mattia/status.sh by Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#

from reproducible_common import *

def generate_live_status():
    """ the schedule pages are very different than others index pages """
    log.info('Building live status page...')
    title = 'Live status of reproducible.debian.net'
    query = 'SELECT s.id, s.name, s.version, s.suite, s.architecture AS arch, ' + \
            'p.scheduler, p.date_scheduled as "scheduled on", p.date_build_started AS "build started on", ' + \
            'r.status, r.version, r.build_duration AS duration, p.builder, p.notify' + \
            'FROM sources AS s JOIN schedule AS p ON p.package_id=s.id LEFT JOIN results AS r ON s.id=r.package_id' + \
            'WHERE p.scheduler != "" OR p.date_build_started != "" OR p.notify != ""' + \
            'ORDER BY date_scheduled desc;'
    html = ''
    rows = query_db(query)
    html += '<p><table class="scheduled">\n' + tab
    html += '<tr><th>#</th><th>src pkg id</th><th>name</th><th>version</th>'
    html += '<th>suite</th><th>arch</th><th>scheduled by</th>'
    html += '<th>scheduled on</th><th>build started</th><th>status</th>'
    html += '<tr><th>version building</th><th>previous build duration</th><th>builder job</th><th>notify</th>'
    html += '</tr>\n'
    for row in rows:
        pkg = row[1]
        arch = row[4]
        suite = row[3]
        url = RB_PKG_URI + '/' + suite + '/' + arch + '/' + pkg + '.html'
        html += tab + '<tr><td>&nbsp;</td><td>' + row[0] + '</td>'
        html += '<td><code>'
        html += link_package(pkg, suite, arch)
        html += '</code></td>'
        html += '<td>' + row[1] + '</td><td>' + row[2] + '</td><td>' + row[3] + '</td>'
        html += '<td>' + row[4] + '</td><td>' + row[5] + '</td><td>' + row[6] + '</td>'
        html += '<td>' + row[7] + '</td><td>' + row[8] + '</td><td>' + row[9] + '</td>'
        html += '<td>' + row[10] + '</td><td>' + row[11] + '</td><td>' + row[12] + '</td>'
        html += '</tr>\n'
    html += '</table></p>\n'
    destfile = BASE + '/live_status.html'
    desturl = REPRODUCIBLE_URL + '/live_status.html'
    write_html_page(title=title, body=html, destfile=destfile, style_note=True)

if __name__ == '__main__':
    generate_live_status

