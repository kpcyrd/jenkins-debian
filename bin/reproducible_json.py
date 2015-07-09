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
# Build the reproducible.json file, to provide a nice datasource

from reproducible_common import *

import json
import os
import tempfile


output = []

log.info('Creating json dump of current reproducible status')

# filter_query is defined in reproducible_common.py and excludes some FTBFS issues
query = 'SELECT s.name, r.version, s.suite, s.architecture, r.status, r.build_date ' + \
        'FROM results AS r JOIN sources AS s ON r.package_id = s.id '+ \
        'WHERE status != "" AND (( status != "FTBFS" ) OR ' \
        ' ( status = "FTBFS" and r.package_id NOT IN (SELECT n.package_id FROM NOTES AS n WHERE ' + filter_query + ' )))'

result = sorted(query_db(query))
log.info('\tprocessing ' + str(len(result)))

keys = ['package', 'version', 'suite', 'architecture', 'status', 'build_date']
for row in result:
    pkg = dict(zip(keys, row))
    log.debug(pkg)
    output.append(pkg)

tmpfile = tempfile.mkstemp(dir=os.path.dirname(REPRODUCIBLE_JSON))[1]

with open(tmpfile, 'w') as fd:
    json.dump(output, fd, indent=4, sort_keys=True)

os.rename(tmpfile, REPRODUCIBLE_JSON)
os.chmod(REPRODUCIBLE_JSON, 0o644)

log.info(REPRODUCIBLE_URL + '/reproducible.json has been updated.')

