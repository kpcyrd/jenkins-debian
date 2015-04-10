#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
# Based on various reproducible_* files © 2014-2015 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Track the database schema and changes to it. Also allow simple creation
# and migration of it.

from reproducible_common import *

now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")


# the original schema is here
db_schema = [
    {
        'name': 'rb_schema',
        'query': ['''CREATE TABLE rb_schema
                     (version INTEGER NOT NULL,
                      date TEXT NOT NULL,
                      PRIMARY KEY (version))''',
                  'INSERT INTO rb_schema VALUES ("1", "''' + now + '")']
    },
    {
        'name': 'source_packages',
        'query': ['''CREATE TABLE source_packages
                     (name TEXT NOT NULL,
                      version TEXT NOT NULL,
                      status TEXT NOT NULL
                      CHECK
                        (status IN
                            ("blacklisted", "FTBFS", "reproducible",
                             "unreproducible", "404", "not for us")
                        ),
                      build_date TEXT NOT NULL,
                      PRIMARY KEY (name))''']
    },
    {
        'name': 'sources_scheduled',
        'query': ['''CREATE TABLE sources_scheduled
                     (name TEXT NOT NULL,
                      date_scheduled TEXT NOT NULL,
                      date_build_started TEXT NOT NULL,
                      PRIMARY KEY (name))''']
    },
    {
        'name': 'sources',
        'query': ['''CREATE TABLE sources
                     (name TEXT NOT NULL,
                      version TEXT NOT NULL)''']
    },
    {
        'name': 'stats_pkg_state',
        'query': ['''CREATE TABLE stats_pkg_state
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      untested INTEGER,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_builds_per_day',
        'query': ['''CREATE TABLE stats_builds_per_day
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_builds_age',
        'query': ['''CREATE TABLE stats_builds_age
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      oldest_reproducible REAL,
                      oldest_unreproducible REAL,
                      oldest_FTBFS REAL,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_bugs',
        'query': ['''CREATE TABLE stats_bugs
                     (datum TEXT NOT NULL,
                      open_toolchain INTEGER,
                      done_toolchain INTEGER,
                      open_infrastructure INTEGER,
                      done_infrastructure INTEGER,
                      open_timestamps INTEGER,
                      done_timestamps INTEGER,
                      open_fileordering INTEGER,
                      done_fileordering INTEGER,
                      open_buildpath INTEGER,
                      done_buildpath INTEGER,
                      open_username INTEGER,
                      done_username INTEGER,
                      open_hostname INTEGER,
                      done_hostname INTEGER,
                      open_uname INTEGER,
                      done_uname INTEGER,
                      open_randomness INTEGER,
                      done_randomness INTEGER,
                      open_buildinfo INTEGER,
                      done_buildinfo INTEGER,
                      open_cpu INTEGER,
                      done_cpu INTEGER,
                      open_signatures INTEGER,
                      done_signatures INTEGER,
                      open_environment INTEGER,
                      one_environment INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_notes',
        'query': ['''CREATE TABLE stats_notes
                     (datum TEXT NOT NULL,
                      packages_with_notes INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_issues',
        'query': ['''CREATE TABLE stats_issues
                     (datum TEXT NOT NULL,
                      known_issues INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_meta_pkg_state',
        'query': ['''CREATE TABLE stats_meta_pkg_state
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      meta_pkg TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum, suite, meta_pkg))''']
    }
]

# and here are some queries, split by update, that can be used to
# update the live schema
schema_updates = {
    1: ['INSERT INTO rb_schema VALUES ("1", "' + now + '")'],
    2: [  # do a funny dance to add an id, suite and architecture values to
          # the `suites` table
        '''CREATE TABLE sources_new_tmp
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT,
            architecture TEXT,
            UNIQUE (name, suite, architecture)
            ON CONFLICT REPLACE)''',
        '''CREATE TABLE sources_new
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            UNIQUE (name, suite, architecture)
            ON CONFLICT REPLACE)''',
        'INSERT INTO sources_new_tmp (name, version) SELECT * FROM sources',
        'UPDATE sources_new_tmp SET suite="sid", architecture="amd64"',
        'INSERT INTO sources_new SELECT * FROM sources_new_tmp',
        'DROP TABLE sources_new_tmp',
        'DROP TABLE sources',
        'ALTER TABLE sources_new RENAME TO sources',
        # now that we have an id in `sources` rework all tables to join
        # against this table, and avoid duplicating data
        # `schedule`:
        '''CREATE TABLE schedule
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            date_scheduled TEXT NOT NULL,
            date_build_started TEXT NOT NULL,
            save_artifacts INTEGER DEFAULT 0,
            UNIQUE (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''INSERT INTO schedule (package_id, date_scheduled, date_build_started)
           SELECT s.id, p.date_scheduled, p.date_build_started
           FROM sources AS s JOIN sources_scheduled AS p ON s.name = p.name''',
        'DROP TABLE sources_scheduled',
        # `results`:
        '''CREATE TABLE results
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            version TEXT NOT NULL,
            status TEXT,
            build_date TEXT,
            build_duration TEXT DEFAULT '0',
            UNIQUE (package_id)
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''INSERT INTO results (package_id, version, status, build_date)
           SELECT s.id, r.version, r.status, r.build_date
           FROM sources AS s JOIN source_packages as r ON s.name = r.name''',
        'DROP TABLE source_packages',
        # `stats_builds`: (completely new table where we save every build)
        '''CREATE TABLE stats_build
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            status TEXT NOT NULL,
            build_date TEXT NOT NULL,
            build_duration TEXT NOT NULL,
            UNIQUE (name, version, suite, architecture, build_date))''',
        'INSERT INTO rb_schema VALUES ("2", "' + now + '")'],
    3: [ # add columns to stats_bugs for new usertag umask
        '''ALTER TABLE stats_bugs ADD COLUMN open_umask INTEGER''',
        '''ALTER TABLE stats_bugs ADD COLUMN done_umask INTEGER''',
        'INSERT INTO rb_schema VALUES ("3", "' + now + '")'],
    4: [ # stats_pkg_state needs (datum, suite) as primary key
        '''CREATE TABLE stats_pkg_state_tmp
           (datum TEXT NOT NULL,
            suite TEXT NOT NULL,
            untested INTEGER,
            reproducible INTEGER,
            unreproducible INTEGER,
            FTBFS INTEGER,
            other INTEGER,
            PRIMARY KEY (datum, suite))''',
        '''INSERT INTO stats_pkg_state_tmp (datum, suite, untested,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, untested, reproducible, unreproducible,
            FTBFS, other FROM stats_pkg_state;''',
        '''DROP TABLE stats_pkg_state;''',
        '''ALTER TABLE stats_pkg_state_tmp RENAME TO stats_pkg_state;''',
        'INSERT INTO rb_schema VALUES ("4", "' + now + '")'],
    5: [ # stats_builds_per_day needs (datum, suite) as primary key
        '''CREATE TABLE stats_builds_per_day_tmp
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum, suite))''',
        '''INSERT INTO stats_builds_per_day_tmp (datum, suite,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, reproducible, unreproducible,
            FTBFS, other FROM stats_builds_per_day;''',
        '''DROP TABLE stats_builds_per_day;''',
        '''ALTER TABLE stats_builds_per_day_tmp RENAME TO stats_builds_per_day;''',
        'INSERT INTO rb_schema VALUES ("5", "' + now + '")'],
    6: [ # stats_builds_age needs (datum, suite) as primary key
        '''CREATE TABLE stats_builds_age_tmp
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      oldest_reproducible REAL,
                      oldest_unreproducible REAL,
                      oldest_FTBFS REAL,
                      PRIMARY KEY (datum, suite))''',
        '''INSERT INTO stats_builds_age_tmp (datum, suite,
            oldest_reproducible, oldest_unreproducible, oldest_FTBFS)
            SELECT datum, suite, oldest_reproducible, oldest_unreproducible,
            oldest_FTBFS FROM stats_builds_age;''',
        '''DROP TABLE stats_builds_age;''',
        '''ALTER TABLE stats_builds_age_tmp RENAME TO stats_builds_age;''',
        'INSERT INTO rb_schema VALUES ("6", "' + now + '")'],
    7: [ # change build_duration field in results and stats_build from str to int
        '''CREATE TABLE stats_build_tmp
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            status TEXT NOT NULL,
            build_date TEXT NOT NULL,
            build_duration INTEGER NOT NULL,
            UNIQUE (name, version, suite, architecture, build_date))''',
        'INSERT INTO stats_build_tmp SELECT * FROM stats_build',
        'DROP TABLE stats_build',
        'ALTER TABLE stats_build_tmp RENAME TO stats_build',
        '''CREATE TABLE results_tmp
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            version TEXT NOT NULL,
            status TEXT,
            build_date TEXT,
            build_duration INTEGER DEFAULT '0',
            UNIQUE (package_id)
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        'INSERT INTO results_tmp SELECT * FROM results',
        'DROP TABLE results',
        'ALTER TABLE results_tmp RENAME TO results',
        'INSERT INTO rb_schema VALUES ("7", "' + now + '")'],
    8: [ # add default value to stats_bugs to get a full 'done vs open bugs' graph
        '''CREATE TABLE stats_bugs_tmp
           (datum TEXT NOT NULL,
            open_toolchain INTEGER DEFAULT '0',
            done_toolchain INTEGER DEFAULT '0',
            open_infrastructure INTEGER DEFAULT '0',
            done_infrastructure INTEGER DEFAULT '0',
            open_timestamps INTEGER DEFAULT '0',
            done_timestamps INTEGER DEFAULT '0',
            open_fileordering INTEGER DEFAULT '0',
            done_fileordering INTEGER DEFAULT '0',
            open_buildpath INTEGER DEFAULT '0',
            done_buildpath INTEGER DEFAULT '0',
            open_username INTEGER DEFAULT '0',
            done_username INTEGER DEFAULT '0',
            open_hostname INTEGER DEFAULT '0',
            done_hostname INTEGER DEFAULT '0',
            open_uname INTEGER DEFAULT '0',
            done_uname INTEGER DEFAULT '0',
            open_randomness INTEGER DEFAULT '0',
            done_randomness INTEGER DEFAULT '0',
            open_buildinfo INTEGER DEFAULT '0',
            done_buildinfo INTEGER DEFAULT '0',
            open_cpu INTEGER DEFAULT '0',
            done_cpu INTEGER DEFAULT '0',
            open_signatures INTEGER DEFAULT '0',
            done_signatures INTEGER DEFAULT '0',
            open_environment INTEGER DEFAULT '0',
            done_environment INTEGER DEFAULT '0',
            open_umask INTEGER DEFAULT '0',
            done_umask INTEGER DEFAULT '0',
            PRIMARY KEY (datum))''',
        'INSERT INTO stats_bugs_tmp SELECT * FROM stats_bugs',
        'DROP TABLE stats_bugs',
        'ALTER TABLE stats_bugs_tmp RENAME TO stats_bugs',
        'INSERT INTO rb_schema VALUES ("8", "' + now + '")'],
    9: [ # rename "sid" to "unstable"
        'UPDATE sources SET suite = "unstable" WHERE suite = "sid"',
        'UPDATE stats_build SET suite = "unstable" WHERE suite = "sid"',
        'UPDATE stats_pkg_state SET suite = "unstable" WHERE suite = "sid"',
        'UPDATE stats_builds_per_day SET suite = "unstable" WHERE suite = "sid"',
        'UPDATE stats_builds_age SET suite = "unstable" WHERE suite = "sid"',
        'UPDATE stats_meta_pkg_state SET suite = "unstable" WHERE suite = "sid"',
        'INSERT INTO rb_schema VALUES ("9", "' + now + '")'],
    10: [ # add the notes and issues tables
        '''CREATE TABLE notes (
            package_id INTEGER,
            version TEXT NOT NULL,
            issues TEXT,
            bugs TEXT,
            comments TEXT,
            PRIMARY KEY (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''CREATE TABLE issues (
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            url TEXT,
            PRIMARY KEY (name))''',
        'INSERT INTO rb_schema VALUES ("10", "' + now + '")'],
    11: [ # table with removed packages, to enable the maintenance job to do clean up
        '''CREATE TABLE removed_packages (
            name TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            PRIMARY KEY (name, suite, architecture))''',
        'INSERT INTO rb_schema VALUES ("11", "' + now + '")'],
}


def db_create_tables():
    """
    Check whether all tables are present, and create them if not.
    The check is done against sqlite_master, a reserved sqlite table
    containing all database metadata.
    """
    changed = False
    for table in db_schema:
        query = 'SELECT name FROM sqlite_master WHERE name="{}"'
        query = query.format(table['name'])
        if not query_db(query):
            log.warning(table['name'] + ' does not exists. Creating...')
            for query in table['query']:
                log.info('\t' + re.sub(' +', ' ', query.replace('\n', ' ')))
                query_db(query)
                changed = True
    return changed


def db_update():
    """
    Update the database schema.
    Get a list of queries to perform from schema_updates.
    The need for an update is detected by checking the biggest value in the
    rb_schema table against the biggest value in the schema_updates dictionary.
    """
    current = query_db('SELECT MAX(version) FROM rb_schema')[0][0]
    if not current:
        log.warning('This is probably a new database, there are no ' +
                    'previous updates noted')
        current = 0
    last = max(schema_updates.keys())
    if current == last:
        return False
    if current > last:
        print_critiacal_message('The active database schema is higher than' +
                                '  the last update available.\nPlease check!')
        sys.exit(1)
    log.info('Found schema updates.')
    for update in range(current+1, last+1):
        log.info('Applying database update #' + str(update) + '. Queries:')
        startTime = datetime.datetime.now()
        for query in schema_updates[update]:
            log.info('\t' + query)
            query_db(query)
        log.info(str(len(schema_updates[update])) + ' queries executed in ' +
                 str(datetime.datetime.now() - startTime))
    return True


if __name__ == '__main__':
    changed_created = False
    try:
        if not query_db('SELECT * FROM rb_schema'):
            changed_create = db_create_tables()
    except:
        log.error('There is no rb_schema table in the database.')
        log.error('Will run a full db_create_tables().')
        changed_created = db_create_tables()
    changed = db_update()
    if changed or changed_created:
        log.info('Total execution time: ' + str(datetime.datetime.now() -
                 datetime.datetime.strptime(now, "%Y-%m-%d-%H-%M-%S")))
    else:
        log.info('No pending updates.')
