#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
# Based on reproducible_html_notes.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3 python3-yaml
#
# Build html pages based on the content of the notes.git repository

import copy
import popcon
import yaml
from collections import OrderedDict
from math import sqrt
from reproducible_common import *
from reproducible_html_packages import gen_packages_html
from reproducible_html_indexes import build_page

NOTES = 'packages.yml'
ISSUES = 'issues.yml'

NOTESGIT_DESCRIPTION = 'Our notes about issues affecting packages are stored in <a href="https://anonscm.debian.org/git/reproducible/notes.git" target="_parent">notes.git</a> and are targeted at packages in Debian in \'unstable/amd64\' (unless they say otherwise).'

note_html = Template((tab*2).join("""
<table class="body">
  <tr>
    <td>Version annotated:</td>
    <td>$version</td>
  </tr>
  $infos
  <tr>
    <td colspan="2">&nbsp;</td>
  </tr>
  <tr>
    <td colspan="2" style="text-align:right; font-size:0.9em;">
      <p>
       $notesgit_description
      </p>
    </td>
  </tr>
</table>""".splitlines(True)))

note_issues_html = Template((tab*3).join("""
<tr>
  <td>
    Identified issues:
  </td>
  <td class="left">
    $issues
  </td>
</tr>""".splitlines(True)))

note_bugs_html = Template((tab*4).join("""
<tr>
  <td>
    Bugs noted:
  </td>
  <td class="left">
     $bugs
  </td>
</tr>""".splitlines(True)))

note_comments_html = Template((tab*3).join("""
<tr>
  <td>
    Comments:
  </td>
  <td class="left">
    $comments
  </td>
</tr>""".splitlines(True)))

note_issue_html_url = Template((tab*6).join("""
<tr>
  <td>
    URL
  </td>
  <td class="left">
    <a href="$url" target="_blank">$url</a>
  </td>
</tr>""".splitlines(True)))

note_issue_html_desc = Template((tab*6).join("""
<tr>
  <td>
    Description
  </td>
  <td class="left">
     $description
  </td>
</tr>""".splitlines(True)))

note_issue_html = Template((tab*5).join(("""
<table class="body">
  <tr>
    <td>
      Identifier:
    </td>
    <td class="left">
      <a href="%s/${issue}_issue.html" target="_parent">$issue</a>
    </td>
  </tr>
  $issue_info
</table>
""" % ISSUES_URI).splitlines(True)))

issue_html_url = Template((tab*4).join("""
<tr>
  <td>
    URL:
  </td>
  <td class="left">
    <a href="$url">$url</a>
  </td>
</tr>""".splitlines(True)))

issue_html = Template((tab*3).join("""
<table class="body">
  <tr>
    <td style="min-width: 15%">
      Identifier:
    </td>
    <th class="left">
      $issue
    </th>
  </tr>
  <tr>
    <td>
      Suites:
    </td>
    <td class="left">
      $suite_links
    </td>
  </tr>
    $urls
  <tr>
    <td>
      Description:
    </td>
    <td class="left">
      $description
    </td>
  </tr>
  <tr>
    <td>
      Packages in '$suite' known to be affected by this issue:<br />
      (the 1/4 most-popular ones (within this issue) are underlined)
    </td>
    <td class="left">
$affected_pkgs
    </td>
  </tr>
  <tr><td colspan="2">&nbsp;</td></tr>
  <tr>
    <td colspan="2" style="text-align:right; font-size:0.9em;">
      <p>
       $notesgit_description
      </p>
    </td>
  </tr>
</table>""".splitlines(True)))


def load_notes():
    """
    format:
    { 'package_name': {'version': '0.0', 'comments'<etc>}, 'package_name':{} }
    """
    with open(NOTES) as fd:
        possible_notes = yaml.load(fd)
    log.debug("notes loaded. There are " + str(len(possible_notes)) +
                  " package listed")
    notes = copy.copy(possible_notes)
    for package in possible_notes:   # check if every package listed on the notes
        try:                         # actually have been tested
            query = 'SELECT s.name ' + \
                    'FROM results AS r JOIN sources AS s ON r.package_id=s.id ' + \
                    'WHERE s.name="{pkg}" AND r.status != ""'
            query = query.format(pkg=package)
            result = query_db(query)[0]
        except IndexError:
            log.warning("This query produces no results: " + query)
            log.warning("This means there is no tested package with the name " + package + ".")
            del notes[package]
    log.debug("notes checked. There are " + str(len(notes)) +
                  " package listed")
    return notes


def load_issues():
    """
    format:
    { 'issue_name': {'description': 'blabla', 'url': 'blabla'} }
    """
    with open(ISSUES) as fd:
        issues = yaml.load(fd)
    log.debug("issues loaded. There are " + str(len(issues)) +
                  " issues listed")
    return issues


def fill_issue_in_note(issue):
    details = issues[issue]
    html = ''
    if 'url' in details:
        html += note_issue_html_url.substitute(url=details['url'])
    if 'description' in details:
        desc = details['description'].replace('\n', '<br />')
        html += note_issue_html_desc.substitute(description=desc)
    else:
        log.warning("The issue " + issue + " misses a description")
    return note_issue_html.substitute(issue=issue, issue_info=html)


def gen_html_note(package, note):
    """
    Given a note as input (as a dict:
    {"package_name": {"version": "0.0.0", "comments": "blablabla",
     "bugs": [111, 222], "issues": ["issue1", "issue2"]}}
    ) it returns the html body
    """
    infos = ''
    # check for issues:
    if 'issues' in note:
        tmp = ''
        for issue in note['issues']:
            tmp += fill_issue_in_note(issue)
            issues_count.setdefault(issue, []).append(note['package'])
        infos += note_issues_html.substitute(issues=tmp)
    # check for bugs:
    if 'bugs' in note:
        bugurls = ''
        for bug in note['bugs']:
            try:
                bug_title = ': "%s"' % bugs[package][bug]['title']
            except KeyError:
                bug_title = ''
            bugurls += '<a href="https://bugs.debian.org/' + str(bug) + \
                       '" target="_parent">' + str(bug) + '</a>' + \
                       get_trailing_bug_icon(bug, bugs, package) + \
                       bug_title + '<br />'
        infos += note_bugs_html.substitute(bugs=bugurls)
    # check for comments:
    if 'comments' in note:
        comment = note['comments']
        comment = url2html.sub(r'<a href="\1">\1</a>', comment)
        comment = comment.replace('\n', '<br />')
        infos += note_comments_html.substitute(comments=comment)
    try:
        return note_html.substitute(version=str(note['version']), infos=infos, notesgit_description=NOTESGIT_DESCRIPTION)
    except KeyError:
        log.warning('You should really include a version in the ' +
              str(note['package']) + ' note')
        return note_html.substitute(version='N/A', infos=infos, notesgit_description=NOTESGIT_DESCRIPTION)


def gen_html_issue(issue, suite):
    """
    Given a issue as input (as a dict:
    {"issue_identifier": {"description": "blablabla", "url": "blabla"}}
    ) it returns the html body
    """
    # links to the issue in other suites
    suite_links = ''
    for i in SUITES:
        if suite_links != '':
            suite_links += ' / '
        if i != suite:
            suite_links += '<a href="' + REPRODUCIBLE_URL + ISSUES_URI + '/' + i + '/' + issue + '_issue.html">' + i + '</a>'
        else:
            suite_links += '<em>' + i + '</em>'
    # check for url:
    if 'url' in issues[issue]:
        url = issue_html_url.substitute(url=issues[issue]['url'])
    else:
        url = ''
    # add affected packages:
    affected = ''
    try:
        arch = 'amd64'
        for status in ['unreproducible', 'FTBFS', 'not for us', 'blacklisted', 'reproducible', 'depwait']:
            pkgs = [x[0] for x in all_pkgs
                    if x[1] == status and x[2] == suite and x[3] == arch and x[0] in issues_count[issue]]
            if not pkgs:
                continue
            affected += tab*4 + '<p>\n'
            affected += tab*5 + '<img src="/static/' + get_status_icon(status)[1] + '"'
            affected += ' alt="' + status + ' icon" />\n'
            affected += tab*5 + str(len(pkgs)) + ' ' + status + ' packages in ' + suite + '/' + arch +':\n'
            affected += tab*5 + '<code>\n'
            pkgs_popcon = issues_popcon_annotate(pkgs)
            for pkg, popcon, is_popular in sorted(pkgs_popcon, key=lambda x: x[0] in bugs):
                affected += tab*6 + link_package(pkg, suite, arch, bugs, popcon, is_popular)
            affected += tab*5 + '</code>\n'
            affected += tab*4 + '</p>\n'
    except KeyError:    # The note is not listed in any package, that is
        affected = '<i>None</i>'
    # check for description:
    try:
        desc = issues[issue]['description']
    except KeyError:
        log.warning('You should really include a description in the ' +
              issue + ' issue')
        desc = 'N/A'
    desc = url2html.sub(r'<a href="\1">\1</a>', desc)
    desc = desc.replace('\n', '<br />')
    return issue_html.substitute(issue=issue, urls=url, description=desc,
                                   affected_pkgs=affected,
                                   suite=suite, suite_links=suite_links,
                                   notesgit_description=NOTESGIT_DESCRIPTION)


def purge_old_notes(notes):
    removed_pages = []
    to_rebuild = []
    presents = sorted(os.listdir(NOTES_PATH))
    for page in presents:
        pkg = page.rsplit('_', 1)[0]
        log.debug('Checking if ' + page + ' (from ' + pkg + ') is still needed')
        if pkg not in notes:
            log.info('There are no notes for ' + pkg + '. Removing old page.')
            os.remove(NOTES_PATH + '/' + page)
            removed_pages.append(pkg)
    for pkg in removed_pages:
        for suite in SUITES:
            try:
                query = 'SELECT s.name ' + \
                        'FROM results AS r JOIN sources AS s ON r.package_id=s.id ' + \
                        'WHERE s.name="{pkg}" AND r.status != "" AND s.suite="{suite}"'
                query = query.format(pkg=pkg, suite=suite)
                to_rebuild.append(query_db(query)[0][0])
            except IndexError:  # the package is not tested. this can happen if
                pass            # a package got removed from the archive
    if to_rebuild:
        gen_packages_html([Package(x) for x in to_rebuild])


def purge_old_issues(issues):
    for root, dirs, files in os.walk(ISSUES_PATH):
        if not files:
            continue
        for file in files:
            try:
                issue = file.rsplit('_', 1)[0]
            except ValueError:
                log.critical('/'.join([root, file]) + ' does not seems like '
                             + 'a file that should be there')
                sys.exit(1)
            if issue not in issues:
                log.warning('removing ' + '/'.join([root, file]) + '...')
                os.remove('/'.join([root, file]))


def iterate_over_notes(notes):
    num_notes = str(len(notes))
    i = 0
    for package in sorted(notes):
        log.debug('iterating over notes... ' + str(i) + '/' + num_notes)
        note = notes[package]
        note['package'] = package
        log.debug('\t' + str(note))
        html = gen_html_note(package, note)

        title = 'Notes for ' + package + ' - reproducible builds result'
        destfile = NOTES_PATH + '/' + package + '_note.html'
        write_html_page(title=title, body=html, destfile=destfile)

        desturl = REPRODUCIBLE_URL + NOTES_URI + '/' + package + '_note.html'
        log.debug("Note created: " + desturl)
        i = i + 1
    log.info('Created ' + str(i) + ' note pages.')


def iterate_over_issues(issues):
    num_issues = str(len(issues))
    for suite in SUITES:
        i = 0
        for issue in sorted(issues):
            log.debug('iterating over issues in ' + suite +'... ' + str(i) + '/' + num_issues)
            log.debug('\t' + str(issue))
            html = gen_html_issue(issue, suite)

            title = 'Notes about issue ' + issue + ' in ' + suite
            destfile = ISSUES_PATH + '/' + suite + '/' + issue + '_issue.html'
            left_nav_html = create_main_navigation(displayed_page='issues')
            write_html_page(title=title, body=html, destfile=destfile,
                            style_note=True, left_nav_html=left_nav_html)

            desturl = REPRODUCIBLE_URL + ISSUES_URI + '/' + suite + '/' + issue + '_issue.html'
            log.debug("Issue created: " + desturl)
            i = i + 1
        log.info('Created ' + str(i) + ' issue pages for ' + suite)


def issues_popcon_annotate(issues_list):
    # outputs [(package, popcon, is_popular)] where is_popular True if it's
    # in the upper 1/4 of issues_list, i.e. a relative measure
    n = len(issues_list)
    popcon_dict = dict((p, 0) for p in issues_list)
    popcon_dict.update(popcon.package(*issues_list))
    issues = sorted(popcon_dict.items(), key=lambda p: p[0])
    issues_by_popcon = sorted(issues, key=lambda p: p[1], reverse=True)
    issues_with_popcon = [(p[0], p[1], i<n/4) for i, p in enumerate(issues_by_popcon)]
    return sorted(issues_with_popcon, key=lambda p: p[0])


def sort_issues(scorefunc, issue):
    try:
        return (-scorefunc(issues_count[issue]), issue)
    except KeyError:    # there are no packages affected by this issue
        return (0, issue)


def index_issues(issues, scorefuncs):
    firstscorefunc = next(iter(scorefuncs.values()))
    templ = "\n<table class=\"body\">\n" + tab + "<tr>\n" + tab*2 + "<th>\n" \
          + tab*3 + "Identified issues\n" + tab*2 + "</th>\n" + tab*2 + "<th>\n" \
          + "".join(
            tab*3 + k + "\n" + tab*2 + "</th>\n" + tab*2 + "<th>\n"
            for k in scorefuncs.keys()) \
          + tab*3 + "Affected packages<br/>\n" \
          + tab*3 + "(the 1/4 most-popular ones (within the issue) are underlined)\n" \
          + tab*2 + "</th>\n" + tab + "</tr>\n"
    html = (tab*2).join(templ.splitlines(True))
    for issue in sorted(issues, key=lambda issue: sort_issues(firstscorefunc, issue)):
        html += tab*3 + '<tr>\n'
        html += tab*4 + '<td><a href="' + ISSUES_URI + '/' + defaultsuite + \
                '/'+ issue + '_issue.html">' + issue.replace("_", " ") + '</a></td>\n'
        issues_list = issues_count.get(issue, [])
        for scorefunc in scorefuncs.values():
            html += tab*4 + '<td><b>' + str(scorefunc(issues_list)) + '</b></td>\n'
        html += tab*4 + '<td>\n'
        issues_with_popcon = issues_popcon_annotate(issues_list)
        issue_strings = [
            '<span %stitle="popcon score: %s">%s</span>' % (
                'class="package-popular" ' if p[2] else '', p[1], p[0]
            ) for p in issues_with_popcon]
        html += tab*5 + ', '.join(issue_strings) + '\n'
        html += tab*4 + '</td>\n'
        html += tab*3 + '</tr>\n'
    html += tab*2 + '</table>\n'
    html += tab*2 + '<p>For a total of <b>' + \
            str(len([x for x in notes if notes[x].get('issues')])) + \
            '</b> packages categorized in <b>' + str(len(issues)) + \
            '</b> issues.</p>'
    html += tab*2 + '<p>' + NOTESGIT_DESCRIPTION + '</p>'
    title = 'Known issues related to reproducible builds'
    destfile = DEBIAN_BASE + '/index_issues.html'
    desturl = DEBIAN_URL + '/index_issues.html'
    left_nav_html = create_main_navigation(displayed_page='issues')
    write_html_page(title=title, body=html, destfile=destfile,
                    left_nav_html=left_nav_html)
    log.info('Issues index now available at ' + desturl)


if __name__ == '__main__':
    all_pkgs = query_db('SELECT s.name, r.status, s.suite, s.architecture ' +
                        'FROM results AS r JOIN sources AS s ON r.package_id=s.id ' +
                        'ORDER BY s.name')
    issues_count = {}
    bugs = get_bugs()
    notes = load_notes()
    issues = load_issues()
    iterate_over_notes(notes)
    iterate_over_issues(issues)
    index_issues(issues, OrderedDict([
        ("Sum of packages' popcon scores",
         lambda l: sum(popcon.package(*l).values())),
        ("Sum of square-roots of packages' popcon scores",
         lambda l: int(sum(map(sqrt, popcon.package(*l).values())))),
        ("Number of packages",
         len),
    ]))
    purge_old_notes(notes)
    purge_old_issues(issues)
    gen_packages_html([Package(x) for x in notes])
    for suite in SUITES:
        for arch in ARCHS:
            build_page('notes', suite, arch)
            build_page('no_notes', suite, arch)
            build_page('FTBFS', suite, arch)
