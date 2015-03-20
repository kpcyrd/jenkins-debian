#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
#Based on reproducible_html_all_packages.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build all rb-pkg pages (the pages that describe the package status) using
# code already written in reproducible_html_packages


from reproducible_common import *
from reproducible_html_packages import gen_all_rb_pkg_pages

# produce all packages html
for suite in SUITES:
    gen_all_rb_pkg_pages(suite=suite)


# now find those where debbindiff failed
unreproducible = query_db('SELECT s.name, s.suite, s.architecture, r.version ' +
                          'FROM sources AS s JOIN results AS r ON s.id=r.package_id ' +
                          'WHERE r.status="unreproducible"')

for pkg, suite, arch, version in unreproducible:
    eversion = strip_epoch(version)
    dbd = DBD_PATH + '/' + suite + '/' + arch + '/' + pkg + '_' + \
          eversion + '.debbindiff.html'
    if not os.access(dbd, os.R_OK):
        log.critical(REPRODUCIBLE_URL + '/' + suite + '/' + arch + '/' + pkg +
                     ' is unreproducible, yet it produced no debbindiff output.')
