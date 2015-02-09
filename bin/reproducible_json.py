#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Based on reproducible_json.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build the reproducible.json file, to provide a nice datasource

from reproducible_common import *

import json

result = sorted(query_db('SELECT name, version, status , build_date ' +
                         'FROM source_packages ' +
                         'WHERE status != ""'))
count = int(query_db('SELECT COUNT(name) FROM source_packages ' +
                           'WHERE status != ""')[0][0])

log.info('processing ' + str(count) + ' package to create .json output')

all_pkgs = []
keys = ['package', 'version', 'status', 'build_date']
for row in result:
    pkg = dict(zip(keys, row))
    pkg['suite'] = 'sid'
    all_pkgs.append(pkg)

with open(REPRODUCIBLE_JSON, 'w') as fd:
    json.dump(all_pkgs, fd, indent=4, sort_keys=True)

log.info(REPRODUCIBLE_URL + '/reproducible.json has been updated.')

