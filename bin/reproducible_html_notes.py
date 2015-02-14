#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Based on reproducible_html_notes.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3 python3-yaml
#
# Build html pages based on the content of the notes.git repository

import yaml
from reproducible_common import *
from reproducible_html_packages import process_packages

NOTES = 'packages.yml'
ISSUES = 'issues.yml'

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
        Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git" target="_parent">notes.git</a>.
      </p>
    </td>
  </tr>
</table>""".splitlines(True)))
note_issues_html = Template((tab*3).join("""
<tr>
  <td>
    Identified issues:
  </td>
  <td>
    $issues
  </td>
</tr>""".splitlines(True)))
note_bugs_html = Template((tab*4).join("""
<tr>
  <td>
    Bugs noted:
  </td>
  <td>
     $bugs
  </td>
</tr>""".splitlines(True)))
note_comments_html = Template((tab*3).join("""
<tr>
  <td>
    Comments:
  </td>
  <td>
    $comments
  </td>
</tr>""".splitlines(True)))

note_issue_html_url = Template((tab*6).join("""
<tr>
  <td>
    URL
  </td>
  <td>
    <a href="$url" target="_blank">$url</a>
  </td>
</tr>""".splitlines(True)))
note_issue_html_desc = Template((tab*6).join("""
<tr>
  <td>
    Description
  </td>
  <td>
     $description
  </td>
</tr>""".splitlines(True)))
note_issue_html = Template((tab*5).join(("""
<table class="body">
  <tr>
    <td>
      Identifier:
    </td>
    <td>
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
  <td>
    <a href="$url">$url</a>
  </td>
</tr>""".splitlines(True)))
issue_html = Template((tab*3).join("""
<table class="body">
  <tr>
    <td>
      Identifier:
    </td>
    <th>
      $issue
    </th>
  </tr>
    $urls
  <tr>
    <td>
      Description:
    </td>
    <td>
      $description
    </td>
  </tr>
  <tr>
    <td>
      Packages known to be affected by this issue:
    </td>
    <td>
$affected_pkgs
    </td>
  </tr>
  <tr><td colspan="2">&nbsp;</td></tr>
  <tr>
    <td colspan="2" style="text-align:right; font-size:0.9em;">
      <p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git" target="_parent">notes.git</a>.</p>
    </td>
  </tr>
</table>""".splitlines(True)))


def load_notes():
    """
    format:
    { 'package_name': {'version': '0.0', 'comments'<etc>}, 'package_name':{} }
    """
    with open(NOTES) as fd:
        notes = yaml.load(fd)
    log.debug("notes loaded. There are " + str(len(notes)) +
                  " package listed")
    for package in notes:   # check if every pacakge listed on the notes
        try:                # actually have been tested
            query = 'SELECT name ' + \
                    'FROM source_packages ' + \
                    'WHERE name="%s"' % package
            result = query_db(query)[0]
        except IndexError:
            print_critical_message('This query produces no results: ' + query +
                    '\nThis means there is no tested package with the name ' +
                    package + '.')
            raise
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


def gen_html_note(note):
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
            try:
                issues_count[issue].append(note['package'])
            except KeyError:
                issues_count[issue] = [note['package']]
        infos += note_issues_html.substitute(issues=tmp)
    # check for bugs:
    if 'bugs' in note:
        bugurls = ''
        for bug in note['bugs']:
            bugurls += '<a href="https://bugs.debian.org/' + str(bug) + \
                       '" target="_parent">' + str(bug) + '</a><br />'
        infos += note_bugs_html.substitute(bugs=bugurls)
    # check for comments:
    if 'comments' in note:
        comment = note['comments']
        comment = url2html.sub(r'<a href="\1">\1</a>', comment)
        comment = comment.replace('\n', '<br />')
        infos += note_comments_html.substitute(comments=comment)
    try:
        return note_html.substitute(version=str(note['version']), infos=infos)
    except KeyError:
        log.warning('You should really include a version in the ' +
              str(note['package']) + ' note')
        return note_html.substitute(version='N/A', infos=infos)

def gen_html_issue(issue):
    """
    Given a issue as input (as a dict:
    {"issue_identifier": {"description": "blablabla", "url": "blabla"}}
    ) it returns the html body
    """
    # check for url:
    if 'url' in issues[issue]:
        url = issue_html_url.substitute(url=issues[issue]['url'])
    else:
        url = ''
    # add affected packages:
    affected = ''
    try:
        for pkg in sorted(issues_count[issue]):
            affected += tab*6 + '<a href="%s/%s.html" class="noted">%s</a>\n' \
                        % (RB_PKG_URI, pkg, pkg)
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
                                   affected_pkgs=affected)

def purge_old_notes(notes):
    removed_pages = []
    presents = sorted(os.listdir(NOTES_PATH))
    for page in presents:
        pkg = page.rsplit('_', 1)[0]
        log.debug('Checking if ' + page + ' (from ' + pkg + ') is still needed')
        if pkg not in notes:
            log.info('There are no notes for ' + pkg + '. Removing old page.')
            os.remove(NOTES_PATH + '/' + page)
            removed_pages.append(pkg)
    if removed_pages:
        process_packages(removed_pages)

def iterate_over_notes(notes):
    num_notes = str(len(notes))
    i = 0
    for package in sorted(notes):
        log.debug('iterating over notes... ' + str(i) + '/' + num_notes)
        note = notes[package]
        note['package'] = package
        log.debug('\t' + str(note))
        html = gen_html_note(note)

        title = 'Notes for ' + package + ' - reproducible builds result'
        destfile = NOTES_PATH + '/' + package + '_note.html'
        write_html_page(title=title, body=html, destfile=destfile,
                        noheader=True)

        desturl = REPRODUCIBLE_URL + NOTES_URI + '/' + package + '_note.html'
        log.info("you can now see your notes at " + desturl)
        i = i + 1

def iterate_over_issues(issues):
    num_issues = str(len(issues))
    i = 0
    for issue in sorted(issues):
        log.debug('iterating over issues... ' + str(i) + '/' + num_issues)
        log.debug('\t' + str(issue))
        html = gen_html_issue(issue)

        title = 'Notes about issue ' + issue
        destfile = ISSUES_PATH + '/' + issue + '_issue.html'
        write_html_page(title=title, body=html, destfile=destfile,
                        style_note=True)

        desturl = REPRODUCIBLE_URL + ISSUES_URI + '/' + issue + '_issue.html'
        log.info("you can now see the issue at " + desturl)
        i = i + 1

def sort_issues(issue):
    try:
        return (-len(issues_count[issue]), issue)
    except KeyError:    # there are no packages affected by this issue
        return (0, issue)

def index_issues(issues):
    templ = "\n<table class=\"body\">\n" + tab + "<tr>\n" + tab*2 + "<th>\n" \
          + tab*3 + "Identified issues\n" + tab*2 + "</th>\n" + tab*2 + "<th>\n" \
          + tab*3 + "Affected packages\n" + tab*2 + "</th>\n" + tab + "</tr>\n"
    html = (tab*2).join(templ.splitlines(True))
    for issue in sorted(issues, key=sort_issues):
        html += tab*3 + '<tr>\n'
        html += tab*4 + '<td><a href="' + ISSUES_URI + '/' + issue + \
                '_issue.html">' + issue + '</a></td>\n'
        html += tab*4 + '<td>\n'
        try:
            html += tab*5 + '<b>' + str(len(issues_count[issue])) + '</b>:\n'
            html += tab*5 + ', '.join(issues_count[issue]) + '\n'
        except KeyError:    # there are no packages affected by this issue
            html += tab*5 + '<b>0</b>\n'
        html += tab*4 + '</td>\n'
        html += tab*3 + '</tr>\n'
    html += tab*2 + '</table>\n'
    html += tab*2 + '<p>For a total of <b>' + \
            str(len([x for x in notes if notes[x].get('issues')])) + \
            '</b> packages categorized in <b>' + str(len(issues)) + \
            '</b> issues.</p>'
    html += tab*2 + '<p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git" target="_parent">notes.git</a>.</p>'
    title = 'Overview of known issues related to reproducible builds'
    destfile = BASE + '/index_issues.html'
    desturl = REPRODUCIBLE_URL + '/index_issues.html'
    write_html_page(title=title, body=html, destfile=destfile)
    log.info('Issues index now available at ' + desturl)

def get_trailing_icon(package, bugs):
    html = ''
    if package in bugs:
        for bug in bugs[package]:
            html += '<span class="'
            if bugs[package][bug]['done']:
                html += 'bug-done" title="#' + str(bug) + ', done">#</span>'
            elif bugs[package][bug]['patch']:
                html += 'bug-patch" title="#' + str(bug) + ', with patch">+</span>'
            else:
                html += '" title="#' + str(bug) + '">+</span>'
    return html

def index_notes(notes, bugs):
    log.debug('Building the index_notes page...')
    html = '\n<p>There are ' + str(len(notes)) + ' packages with notes.</p>\n'
    html += '<p>\n' + tab + '<code>\n'
    html = (tab*2).join(html.splitlines(True))
    for pkg in sorted(notes):
        url = RB_PKG_URI + '/' + pkg + '.html'
        html += tab*4 + '<a href="' + url + '" class="noted">' + pkg + '</a>'
        html += get_trailing_icon(pkg, bugs) + '\n'
    html += tab*3 + '</code>\n'
    html += tab*2 + '</p>\n'
    html += tab*2 + '<p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git" target="_parent">notes.git</a>.</p>'
    title = 'Overview of packages with notes'
    destfile = BASE + '/index_notes.html'
    desturl = REPRODUCIBLE_URL + '/index_notes.html'
    write_html_page(title=title, body=html, destfile=destfile,
                    style_note=True)
    log.info('Notes index now available at ' + desturl)


def index_no_notes(notes, bugs):
    log.debug('Building the index_no_notes page...')
    all_pkgs = query_db('SELECT name FROM source_packages ' +
                        'WHERE status = "unreproducible" OR status = "FTBFS"')
    without_notes = [x[0] for x in all_pkgs if x[0] not in notes]
    html = '\n<p>There are ' + str(len(without_notes)) + ' unreproducible ' \
           + 'packages without notes. So these are the packages with failures ' \
           + 'that still need to be investigated: </p>\n'
    html += '<p>\n' + tab + '<code>\n'
    html = (tab*2).join(html.splitlines(True))
    for pkg in sorted(without_notes):
        url = RB_PKG_URI + '/' + pkg + '.html'
        html += tab*4 + '<a href="' + url + '">' + pkg + '</a>'
        html += get_trailing_icon(pkg, bugs) + '\n'
    html += tab*3 + '</code>\n'
    html += tab*2 + '</p>\n'
    html += tab*2 + '<p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git" target="_parent">notes.git</a>.</p>'
    title = 'Overview of packages without notes'
    destfile = BASE + '/index_no_notes.html'
    desturl = REPRODUCIBLE_URL + '/index_no_notes.html'
    write_html_page(title=title, body=html, destfile=destfile,
                    style_note=True)
    log.info('Packages without notes index now available at ' + desturl)


if __name__ == '__main__':
    issues_count = {}
    bugs = get_bugs()
    notes = load_notes()
    issues = load_issues()
    iterate_over_notes(notes)
    iterate_over_issues(issues)
    index_issues(issues)
    index_notes(notes, bugs)
    index_no_notes(notes, bugs)
    purge_old_notes(notes)
    process_packages(notes) # regenerate all rb-pkg/ pages
