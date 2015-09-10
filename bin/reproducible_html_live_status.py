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
    query = 'SELECT s.id, s.name, s.version, s.suite, s.architecture, ' + \
            'p.scheduler, p.date_scheduled, p.date_build_started, ' + \
            'r.status, r.version, r.build_duration, p.builder, p.notify ' + \
            'FROM sources AS s JOIN schedule AS p ON p.package_id=s.id LEFT JOIN results AS r ON s.id=r.package_id ' + \
            'WHERE p.date_build_started != "" OR p.notify != "" ' + \
            'ORDER BY p.date_build_started DESC'
    html = ''
    rows = query_db(query)
    html += '<p>If there are more than 21 rows shown here, the list includes stale builds... we\'re working on it. Stay tuned.<table class="scheduled">\n' + tab
    html += '<tr><th>#</th><th>src pkg id</th><th>name</th><th>version</th>'
    html += '<th>suite</th><th>arch</th><th>scheduled by</th>'
    html += '<th>scheduled on</th><th>build started</th><th>status</th>'
    html += '<th>version building</th><th>previous build duration</th><th>builder job</th><th>notify</th>'
    html += '</tr>\n'
    for row in rows:
        pkg = row[1]
        arch = row[4]
        suite = row[3]
        html += tab + '<tr><td>&nbsp;</td><td>' + str(row[0]) + '</td>'
        html += '<td><code>'
        html += link_package(pkg, suite, arch)
        html += '</code></td><td>' + str(row[2]) + '</td><td>' + str(row[3]) + '</td>'
        html += '<td>' + str(row[4]) + '</td><td>' + str(row[5]) + '</td><td>' + str(row[6]) + '</td>'
        html += '<td>' + str(row[7]) + '</td><td>' + str(row[8]) + '</td><td>' + str(row[9]) + '</td>'
        html += '<td>' + str(row[10]) + '</td><td><a href="https://jenkins.debian.net/job/reproducible_builder_' + str(row[11]) + '/console">' + str(row[11]) + '</a></td><td>' + str(row[12]) + '</td>'
        html += '</tr>\n'
    html += '</table></p>\n'
    destfile = BASE + '/live_status.html'
    desturl = REPRODUCIBLE_URL + '/live_status.html'
    write_html_page(title=title, body=html, destfile=destfile)
    log.info("Package page generated at " + desturl)

if __name__ == '__main__':
    generate_live_status()

