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

query = 'SELECT s.name, r.version, s.suite, s.architecture, r.status, r.build_date ' + \
        'FROM results AS r JOIN sources AS s ON r.package_id = s.id '+ \
        'WHERE status != "" AND status != "unreproducible"'
result = sorted(query_db(query))
log.info('\tprocessing ' + str(len(result)))

keys = ['package', 'version', 'suite', 'architecture', 'status', 'build_date']
for row in result:
    pkg = dict(zip(keys, row))
    log.debug(pkg)
    output.append(pkg)

tmpfile = tempfile.NamedTemporaryFile(dir=os.path.dirname(REPRODUCIBLE_JSON))

with open(tmpfile.name, 'w') as fd:
    json.dump(output, fd, indent=4, sort_keys=True)

os.rename(tmpfile.name, REPRODUCIBLE_JSON)
os.chmod(REPRODUCIBLE_JSON, 0o644)

log.info(REPRODUCIBLE_URL + '/reproducible.json has been updated.')

