#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
# Based on reproducible_json.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build the reproducible.json and reproducibe-tracker.json files, to provide nice datasources

from reproducible_common import *

from apt_pkg import version_compare
import aptsources.sourceslist
import json
import os
import tempfile


output = []
output4tracker = []

log.info('Creating json dump of current reproducible status')

# filter_query is defined in reproducible_common.py and excludes some FTBFS issues
query = 'SELECT s.name, r.version, s.suite, s.architecture, r.status, r.build_date ' + \
        'FROM results AS r JOIN sources AS s ON r.package_id = s.id '+ \
        'WHERE status != "" AND status NOT IN ("not for us", "404", "blacklisted" ) AND (( status != "FTBFS" ) OR ' \
        ' ( status = "FTBFS" and r.package_id NOT IN (SELECT n.package_id FROM NOTES AS n WHERE ' + filter_query + ' )))'

result = sorted(query_db(query))
log.info('\tprocessing ' + str(len(result)))

keys = ['package', 'version', 'suite', 'architecture', 'status', 'build_date']
crossarchkeys = ['package', 'version', 'suite', 'status']
archdetailkeys = ['architecture', 'version', 'status', 'build_date']

# crossarch is a dictionary of all packages used to build a summary of the
# package's test results across all archs (for suite=unstable only)
crossarch = {}

crossarchversions = {}
for row in result:
    pkg = dict(zip(keys, row))
    log.debug(pkg)
    output.append(pkg)

    # tracker.d.o should only care about results in unstable
    if pkg['suite'] == 'unstable':

        package = pkg['package']
        if package in crossarch:
            # compare statuses to get cross-arch package status
            status1 = crossarch[package]['status']
            status2 = pkg['status']
            newstatus = ''

            # compare the versions (only keep most up to date!)
            version1 = crossarch[package]['version']
            version2 = pkg['version']
            versionscompared = version_compare(version1, version2);

            # if version1 > version2,
            # skip the package results we are currently inspecting
            if (versionscompared > 0):
                continue

            # if version1 < version2,
            # delete the package results with the older version
            elif (versionscompared < 0):
                newstatus = status2
                # remove the old package information from the list
                archlist = crossarch[package]['architecture_details']
                newarchlist = [a for a in archlist if a['version'] != version1]
                crossarch[package]['architecture_details'] = newarchlist

            # if version1 == version 2,
            # we are comparing status for the same (most recent) version
            else:
                if 'FTBFS' in [status1, status2]:
                    newstatus = 'FTBFS'
                elif 'unreproducible' in [status1, status2]:
                    newstatus = 'unreproducible'
                elif 'reproducible' in [status1, status2]:
                    newstatus = 'reproducible'
                else:
                    newstatus = 'depwait'

            # update the crossarch status and version
            crossarch[package]['status'] = newstatus
            crossarch[package]['version'] = version2

            # add arch specific test results to architecture_details list
            newarchdetails = {key:pkg[key] for key in archdetailkeys}
            crossarch[package]['architecture_details'].append(newarchdetails)


        else:
            # add package to crossarch
            crossarch[package] = {key:pkg[key] for key in crossarchkeys}
            crossarch[package]['architecture_details'] = \
                [{key:pkg[key] for key in archdetailkeys}]

output4tracker = list(crossarch.values())

# normal json
tmpfile = tempfile.mkstemp(dir=os.path.dirname(REPRODUCIBLE_JSON))[1]
with open(tmpfile, 'w') as fd:
    json.dump(output, fd, indent=4, sort_keys=True)
os.rename(tmpfile, REPRODUCIBLE_JSON)
os.chmod(REPRODUCIBLE_JSON, 0o644)

# json for tracker.d.o, thanks to #785531
tmpfile = tempfile.mkstemp(dir=os.path.dirname(REPRODUCIBLE_TRACKER_JSON))[1]
with open(tmpfile, 'w') as fd:
    json.dump(output4tracker, fd, indent=4, sort_keys=True)
os.rename(tmpfile, REPRODUCIBLE_TRACKER_JSON)
os.chmod(REPRODUCIBLE_TRACKER_JSON, 0o644)

log.info(REPRODUCIBLE_URL + '/reproducible.json and /reproducible-tracker.json have been updated.')

