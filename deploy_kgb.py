#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3 python3-yaml
#
# Generates the kgb client configuration, using the passwords listed in the
# file pointed by `secrets`.

import os
import yaml

secrets = '/srv/jenkins/kgb/secrets.yml'
outputs = '/srv/jenkins/kgb/'

with open(secrets) as fd:
    passwords = yaml.load(fd)

channels = [
    {'name': 'debian-boot', 'id': 'jenkins-debian-boot'},
    {'name': 'debian-bootstrap', 'id': 'jenkins-debian-bootstrap'},
    {'name': 'debian-cinnamon', 'id': 'jenkins-debian-cinnamon'},
    {'name': 'debian-edu', 'id': 'jenkins-debian-edu'},
    {'name': 'debian-haskell', 'id': 'jenkins-debian-haskell'},
    {'name': 'debian-qa', 'id': 'jenkins-debian-qa'},
    {'name': 'debian-reproducible', 'id': 'jenkins-debian-reproducible'},
    {'name': 'debian-ruby', 'id': 'pkg-ruby-extras'},
    {'name': 'dvswitch', 'id': 'jenkins-dvswitch'},
]

template = """repo-id: '{repo_id}'
password: {password}
use-irc-notices: 1
servers:
   # KGB-0, run by dmn@debian.org
 - uri: http://kgb.ktnx.org:9418/
   # KGB-1, run by tincho@debian.org
 - uri: http://kgb.tincho.org:9418/
   # KGB-2, run by gregoa@debian.org
 - uri: http://colleen.colgarra.priv.at:8080/
status-dir: /srv/jenkins/kgb/client-status/
"""

for chan in channels:
    print('Producing conf for #' + chan['name'] + '...')
    conf = template.format(repo_id=chan['id'],
                           password=passwords[chan['name']])
    if not os.access(outputs, os.R_OK):
        try:
            os.makedirs(outputs, exist_ok=True)
        except OSError as e:
            if e.errno == 17:  # that's "file exists" error
                print('ERROR: the output directory ' + outputs +
                      ' has bad permissions')
            raise
    if not os.access(outputs, os.W_OK):
            print('ERROR: the output directory ' + outputs +
                  ' has bad permissions')
            raise OSError
    filename = outputs + chan['name'] + '.conf'
    with open(filename, 'w') as fd:
        fd.write(conf)

print('All kgb configurations generated successfully')
