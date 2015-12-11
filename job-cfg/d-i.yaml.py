#!/usr/bin/python3
#
# Copyright 2015 Philip Hands <phil@hands.com>
# written to generate something very similar to d-i.yaml so much of the
# quoted text is Copyright Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import sys
import os
from yaml import load, dump
try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper

langs = [
    {'ca': {'langname': 'Catalan'}},
    {'cs': {'langname': 'Czech'}},
    {'de': {'langname': 'German'}},
    {'en': {'langname': 'English'}},
    {'fr': {'langname': 'French'}},
    {'it': {'langname': 'Italian'}},
    {'pt_BR': {'langname': 'Brazilian Portuguese'}},
    {'da': {'langname': 'Danish'}},
    {'el': {'langname': 'Greek'}},
    {'es': {'langname': 'Spanish'}},
    {'fi': {'langname': 'Finnish'}},
    {'hu': {'langname': 'Hungarian'}},
    {'ja': {'langname': 'Japanese'}},
    {'ko': {'langname': 'Korean'}},
    {'nl': {'langname': 'Dutch'}},
    {'nn': {'langname': 'Norwegian Nynorsk'}},
    {'pt': {'langname': 'Portuguese'}},
    {'ro': {'langname': 'Romanian'}},
    {'ru': {'langname': 'Russian'}},
    {'sv': {'langname': 'Swedish'}},
    {'tl': {'langname': 'Tagalog'}},
    {'vi': {'langname': 'Vietnamese'}},
    {'zh_CN': {'langname': 'Chinese (zh_CN)'}},
    {'zh_TW': {'langname': 'Chinese (zh_TW)'}}
]

non_pdf_langs = ['el', 'vi', 'ja', 'zh_CN', 'zh_TW']
non_po_langs = ['ca', 'cs', 'de', 'en', 'fr', 'it', 'pt_BR']

pkgs = """
anna
apt-setup
arcboot-installer
base-installer
bterm-unifont
babelbox
busybox
cdebconf-entropy
cdebconf-terminal
cdebconf
cdrom-checker
cdrom-detect
cdrom-retriever
choose-mirror
clock-setup
console-setup
debian-installer-launcher
debian-installer-netboot-images
debian-installer-utils
debian-installer
debootstrap
desktop-chooser
devicetype-detect
dh-di
efi-reader
elilo-installer
finish-install
flash-kernel
grub-installer
hw-detect
installation-locale
installation-report
iso-scan
kbd-chooser
kernel-wedge
kickseed
libdebian-installer
lilo-installer
live-installer
localechooser
lowmem
lvmcfg
main-menu
mdcfg
media-retriever
mklibs
mountmedia
net-retriever
netboot-assistant
netcfg
network-console
nobootloader
oldsys-preseed
os-prober
partconf
partitioner
partman-auto-crypto
partman-auto-lvm
partman-auto-raid
partman-auto
partman-base
partman-basicfilesystems
partman-basicmethods
partman-btrfs
partman-crypto
partman-efi
partman-ext3
partman-iscsi
partman-jfs
partman-lvm
partman-md
partman-multipath
partman-nbd
partman-newworld
partman-partitioning
partman-prep
partman-target
partman-ufs
partman-xfs
partman-zfs
pkgsel
prep-installer
preseed
quik-installer
rescue
rootskel-gtk
rootskel
s390-dasd
s390-netdevice
s390-sysconfig-writer
sibyl-installer
tzsetup
udpkg
usb-discover
user-setup
win32-loader
yaboot-installer
zipl-installer
""".split()


def scm_svn(po, inc_regs=None):
    if inc_regs is None:
        inc_regs = [ os.path.join('/trunk/manual/',
                                  'po' if po else '', '{lang}', '.*') ]

    return [{'svn':
             {'excluded-commit-messages': '',
              'url': 'svn://anonscm.debian.org/svn/d-i/trunk',
              'basedir': '.',
              'workspaceupdater': 'update',
              'included-regions': inc_regs,
              'excluded-users': '',
              'exclusion-revprop-name': '',
              'excluded-regions': '',
              'viewvc-url': 'http://anonscm.debian.org/viewvc/d-i/trunk'}}]


manual_includes = [ '/trunk/manual/debian/.*', '/trunk/manual/po/.*', '/trunk/manual/doc/.*', '/trunk/manual/scripts/.*' ]

desc_str = {
    'html': (
        'Builds the {langname} html version of the installation-guide '
        'for all architectures. Triggered by SVN commits to '
        '<code>svn://anonscm.debian.org/svn/d-i/trunk/manual{popath}/{lang}/'
        '</code>. After successful build '
        '<a href="https://jenkins.debian.net/job/d-i_manual_{lang}_pdf">'
        'd-i_manual_{lang}_pdf</a> is triggered.'),
    'pdf': (
        'Builds the {langname} pdf version of the installation-guide '
        'for all architectures. '
        'Triggered by successful build of '
        '<a href="https://jenkins.debian.net/job/d-i_manual_{lang}_html">'
        'd-i_manual_{lang}_html</a>.'),
    'instguide': (
        'Builds the installation-guide package. Triggered by SVN commits to '
        '<code>svn://anonscm.debian.org/svn/d-i/</code> '
        'matching these patterns: <pre>' + str(manual_includes) + '</pre>')
    }


def lr(keep):
    return {'artifactDaysToKeep': -1, 'daysToKeep': keep,
            'numToKeep': 30, 'artifactNumToKeep': -1}


def publ_email(irc=None):
    r = ['jenkins+' + irc] if irc is not None else []
    r.append('qa-jenkins-scm@lists.alioth.debian.org')
    return {'email': {'recipients': ' '.join(r)}}


def publ(fmt=None, trigger=None, irc=None):
    p = []
    if trigger is not None:
        p = [{'trigger': {'project': 'd-i_manual_{lang}_pdf',
                          'threshold': 'UNSTABLE'}}]
    p.extend([
        {'logparser': {
            'parse-rules': '/srv/jenkins/logparse/debian-installer.rules',
            'unstable-on-warning': 'true',
            'fail-on-error': 'true'}}])
    p.append(publ_email(irc=irc))
    if fmt is not None:
        p.append({'archive': {'artifacts': fmt + '/**/*.*',
                              'latest-only': True}})
    return p

# make the yaml a bit shorter, with aliases
# if that's unhelpful move the variables inside prop()
sb_about = {
    'sidebar': {'url': 'https://jenkins.debian.net/userContent/about.html',
                'text': 'About jenkins.debian.net',
                'icon': '/userContent/images/debian-swirl-24x24.png'}}

sb_profitbricks = {
    'sidebar': {'url': 'http://www.profitbricks.co.uk',
                'text': 'Sponsored by Profitbricks',
                'icon': '/userContent/images/profitbricks-24x24.png'}}


def prop(type='manual', priority=None):
    p = [sb_about,
         {'sidebar': {'url': 'https://jenkins.debian.net/view/d-i_'+type+'/',
                      'text': 'debian-installer ' + type + ' jobs',
                      'icon': '/userContent/images/debian-jenkins-24x24.png'}},
         sb_profitbricks]
    if priority is not None:
        p.append({'priority-sorter': {'priority': str(priority)}})
    return p


def jtmpl(act, target, fmt=None, po=''):
    n = ['{name}', act, target]
    d = ['{name}', act]
    if fmt:
        n.append(fmt)
        d.append(fmt)
    if po != '':
        n.append(po)
        d.append(po)
    return {'job-template': {'name': '_'.join(n), 'defaults': '-'.join(d)}}


def jobspec_svn(key, name, desc, defaults=None,
                priority=120, logkeep=None, trigger=None, publishers=None,
                lang='', fmt='', po='', inc_regs=None):
    shell_cmd = [p for p in ['/srv/jenkins/bin/d-i_manual.sh',
                             lang, fmt, po] if p != '']
    j = {'scm': scm_svn(po=po, inc_regs=inc_regs),
         'project-type': 'freestyle',
         'builders': [{'shell': ' '.join(shell_cmd)}],
         'properties': prop(priority=priority),
         'name': name}
    j['publishers'] = (publishers if publishers is not None
                       else publ(fmt=fmt, trigger=trigger, irc='debian-boot'))

    j['description'] = desc
    j['description'] += ' {do_not_edit}'

    if defaults is not None:
        j['defaults'] = defaults
    if trigger is not None:
        j['triggers'] = [{'pollscm': trigger}]
    if logkeep is not None:
        j['logrotate'] = lr(logkeep)
    return {key: j}



# -- here we build the data to be dumped as yaml
data = []

data.append(
    {'defaults': {'name': 'd-i',
                  'logrotate': lr(90),
                  'project-type': 'freestyle',
                  'properties': prop(type='misc')}})

templs = []

for f in ['html', 'pdf']:
    for po in ['', 'po2xml']:
        n = ['{name}', 'manual', f]
        if po != '':
            n.append(po)
        data.append(
            jobspec_svn(key='defaults',
                        name='-'.join(n),
                        lang='{lang}',
                        fmt=f,
                        po=po,
                        trigger=('{trg}' if not (f == 'pdf' and po == '')
                                 else None),
                        desc=desc_str[f],
                        logkeep=90))
        templs.append(jtmpl(act='manual', target='{lang}', fmt=f, po=po))

data.extend(
    [{'defaults': {
        'name': '{name}-{act}',
        'description': ('Builds debian packages in sid from git {branchdesc}, '
                        'triggered by pushes to <pre>{gitrepo}</pre> '
                        '{do_not_edit}'),
        'triggers': [{'pollscm': '{trg}'}],
        'scm': [{'git': {'url': '{gitrepo}',
                         'branches': ['{branch}']}}],
        'builders': [{'shell': '/srv/jenkins/bin/d-i_build.sh'}],
        'project-type': 'freestyle',
        'properties': prop(type='packages', priority=99),
        'logrotate': lr(90),
        'publishers': publ(irc='debian-boot')}}])

templs.append(jtmpl(act='{act}', target='{pkg}'))
data.extend(templs)

data.append(
    jobspec_svn(key='job-template',
                defaults='d-i',
                name='{name}_manual',
                desc=desc_str['instguide'],
                trigger='{trg}',
                priority=125,
                publishers=[publ_email(irc='debian-boot')],
                inc_regs=manual_includes))

data.append(
    {'job-template': {
        'defaults': 'd-i',
        'name': '{name}_check_jenkins_jobs',
        'description': 'Checks daily for missing jenkins jobs. {do_not_edit}',
        'triggers': [{'timed': '23 0 * * *'}],
        'builders': [{'shell': '/srv/jenkins/bin/d-i_check_jobs.sh'}],
        'publishers': [
            {'logparser': {'parse-rules': '/srv/jenkins/logparse/debian.rules',
                           'unstable-on-warning': 'true',
                           'fail-on-error': 'true'}},
            publ_email()]}})

data.append(
    {'job-template': {
        'defaults': 'd-i',
        'name': '{name}_maintenance',
        'description': ('Cleanup and monitor so that there is '
                        'a predictable environment.{do_not_edit}'),
        'triggers': [{'timed': '30 5 * * *'}],
        'builders': [{'shell': '/srv/jenkins/bin/maintenance.sh {name}'}],
        'properties': prop(priority=150),
        'publishers': [
            {'logparser': {'parse-rules': '/srv/jenkins/logparse/debian.rules',
                           'unstable-on-warning': 'true',
                           'fail-on-error': 'true'}},
            publ_email(irc='debian-boot')]}})

data.append(
    {'job-group': {
        'name': '{name}_manual_html_group',
        'jobs': ['{name}_manual_{lang}_html'],
        'lang': [l for l in langs if list(l.keys())[0] in non_po_langs],
        'trg': 'H/15 * * * *',
        'fmt': 'html',
        'popath': ''}})

data.append(
    {'job-group': {
        'name': '{name}_manual_pdf_group',
        'jobs': ['{name}_manual_{lang}_pdf'],
        'lang': [l for l in langs
                 if (list(l.keys())[0] not in non_pdf_langs)
                 and (list(l.keys())[0] in non_po_langs)],
        'trg': '',
        'fmt': 'pdf'}})

data.append(
    {'job-group': {
        'name': '{name}_manual_html_po2xml_group',
        'jobs': ['{name}_manual_{lang}_html_po2xml'],
        'lang': [l for l in langs if list(l.keys())[0] not in non_po_langs],
        'trg': 'H/30 * * * *',
        'fmt': 'html',
        'popath': '/po'}})

data.append(
    {'job-group': {
        'name': '{name}_manual_pdf_po2xml_group',
        'jobs': ['{name}_manual_{lang}_pdf_po2xml'],
        'lang': [l for l in langs
                 if (list(l.keys())[0] not in non_pdf_langs)
                 and (list(l.keys())[0] not in non_po_langs)],
        'trg': '',
        'fmt': 'pdf'}})

data.append(
    {'job-group': {
        'name': '{name}_build-group',
        'jobs': ['{name}_{act}_{pkg}'],
        'gitrepo': 'git://git.debian.org/git/d-i/{pkg}',
        'act': 'build',
        'branchdesc': 'master branch',
        'branch': 'origin/master',
        'trg': 'H/6 * * * *',
        'pkg': pkgs}})

data.append(
    {'job-group': {
        'name': '{name}_pu-build-group',
        'jobs': ['{name}_{act}_{pkg}'],
        'gitrepo': 'git://git.debian.org/git/d-i/{pkg}',
        'act': 'pu-build',
        'branchdesc': 'pu/ branches',
        'branch': 'origin/pu/**',
        'trg': 'H/10 * * * *',
        'pkg': pkgs}})

data.append(
    {'project': {
        'name': 'd-i',
        'do_not_edit': (
            '<br><br>Job configuration source is '
            '<a href="http://anonscm.debian.org/cgit/qa/'
            'jenkins.debian.net.git/tree/job-cfg/d-i.yaml.py">'
            'd-i.yaml.py</a>.'),
        'jobs': [
            '{name}_maintenance',
            '{name}_check_jenkins_jobs',
            {'{name}_manual': {
                'trg': 'H/15 * * * *'}},
            '{name}_manual_html_group',
            '{name}_manual_pdf_group',
            '{name}_manual_html_po2xml_group',
            '{name}_manual_pdf_po2xml_group',
            '{name}_build-group',
            '{name}_pu-build-group']}})

sys.stdout.write(dump(data, Dumper=Dumper))
