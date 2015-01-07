#!/usr/bin/python3
# -*- coding: utf-8 -*-

# clean-notes: sort and clean the notes stored in notes.git
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2+
#
# Depends: python3 python3-yaml

import yaml
from reproducible_common import *

NOTES = 'packages.yml'
ISSUES = 'issues.yml'

note_html = Template("""<table class="body">
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
        <p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git">notes.git</a>.</p>
    </td>
</tr>
</table>""")
note_issues_html = Template("<tr><td>Identified issues:</td><td>$issues</td></tr>")
note_bugs_html = Template("<tr><td>Bugs noted:</td><td>$bugs</td></tr>")
note_comments_html = Template("<tr><td>Comments:</td><td>$comments</td></tr>")

note_issue_html_url = Template("""<tr><td>URL</td>
    <td><a href="$url" target="_blank">$url</a></td></tr>""")
note_issue_html_desc = Template("""<tr><td>Description</td>
    <td>$description</td></tr>""")
note_issue_html = Template("""<table class="body">
<tr>
    <td>Identifier:</td>
    <td><a href="%s/${issue}_issue.html" target="_parent">$issue</a>
</tr>
$issue_info
</table>
""" % ISSUES_URI)

issue_html_url = Template("""<tr><td>URL:</td><td><a href="$url">$url</a>
    </td></tr>""")
issue_html = Template("""<table class="body">
<tr>
    <td>Identifier:</td>
    <th>$issue</th>
</tr>
$urls
<tr>
    <td>Description:</td>
    <td>$description</td>
</tr>
<tr>
    <td>Packages known to be affected by this issue:</td>
    <td>$affected_pkgs</td>
</tr>
<tr><td colspan="2">&nbsp;</td></tr>
<tr><td colspan="2" style="text-align:right; font-size:0.9em;">
<p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git">notes.git</a>.</p>
</td></tr></table>""")


def load_notes():
    """
    format:
    { 'package_name': {'version': '0.0', 'comments'<etc>}, 'package_name':{} }
    """
    with open(NOTES) as fd:
        notes = yaml.load(fd)
    log.debug("notes loaded. There are " + str(len(notes)) +
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
                       '">' + str(bug) + '</a><br />'
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
    for pkg in sorted(issues_count[issue]):
        affected += '<a href="%s/%s.html" class="noted">%s</a>\n' % (
                     RB_PKG_URI, pkg, pkg)
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
                        noheader=True, nofooter=True)

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
        write_html_page(title=title, body=html, destfile=destfile)

        desturl = REPRODUCIBLE_URL + ISSUES_URI + '/' + issue + '_issue.html'
        log.info("you can now see the issue at " +desturl)
        i = i + 1

def index_issues(issues):
    html  = '<table class="body">'
    html += '<tr><th>Identified issues</th></tr>'
    for issue in sorted(issues):
        html += '<tr><td><a href="' + ISSUES_URI + '/' + issue + \
                '_issue.html">' + issue + '</a></td></tr>'
    html += '</table>'
    html += '<p>Notes are stored in <a href="https://anonscm.debian.org/cgit/reproducible/notes.git">notes.git</a>.</p>'
    title = 'Overview of known issues related to reproducible builds'
    destfile = BASE + '/userContent/index_issues.html'
    desturl = REPRODUCIBLE_URL + '/userContent/index_issues.html'
    write_html_page(title=title, body=html, destfile=destfile, nofooter=True)
    log.info('Issues index now available at ' + desturl)

if __name__ == '__main__':
    issues_count = {}
    notes = load_notes()
    issues = load_issues()
    iterate_over_notes(notes)
    iterate_over_issues(issues)
    index_issues(issues)
        
