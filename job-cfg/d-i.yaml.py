#!/usr/bin/python3
#
# Copyright © 2015 Philip Hands <phil@hands.com>
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

langs = {
    'ca': 'Catalan',
    'cs': 'Czech',
    'de': 'German',
    'en': 'English',
    'fr': 'French',
    'it': 'Italian',
    'pt_BR': 'Brazilian Portuguese',
    'da': 'Danish',
    'el': 'Greek',
    'es': 'Spanish',
    'fi': 'Finnish',
    'hu': 'Hungarian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'nl': 'Dutch',
    'nn': 'Norwegian Nynorsk',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sv': 'Swedish',
    'tl': 'Tagalog',
    'vi': 'Vietnamese',
    'zh_CN': 'Chinese (zh_CN)',
    'zh_TW': 'Chinese (zh_TW)',
}

non_pdf_langs = ['el', 'vi', 'ja', 'zh_CN', 'zh_TW']
non_po_langs  = ['ca', 'cs', 'de', 'en', 'fr', 'it', 'pt_BR']

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
silo-installer
tzsetup
udpkg
usb-discover
user-setup
win32-loader
yaboot-installer
zipl-installer
""".split()


def scm_svn(po, inc_regs=None):
    if inc_regs == None:
        inc_regs = os.path.join('/trunk/manual/', 'po' if po else '', '{lang}', '.*')

    return  [{'svn': {'excludedCommitMessages': '',
                      'url': 'svn://anonscm.debian.org/svn/d-i/trunk',
                      'basedir': '.',
                      'workspaceupdater': 'update',
                      'includedRegions': inc_regs,
                      'excludedUsers': '',
                      'excludedRevprop': '',
                      'excludedRegions': '',
                      'viewvc-url': 'http://anonscm.debian.org/viewvc/d-i/trunk'}}]


def svn_desc(po, fmt):
    s =  'Builds the {languagename} ' + fmt + ' version of the installation-guide for all architectures. '
    s += 'Triggered by SVN commits to <code>svn://anonscm.debian.org/svn/d-i/trunk/manual'
    s += '/po' if po else ''
    s += '/{lang}/<code>. After successful build <a href="https://jenkins.debian.net/job/d-i_manual_{lang}_html">d-i_manual_{lang}_pdf</a> is triggered. {do_not_edit}'
    return s


def pdf_desc():
    s = 'Builds the {languagename} pdf version of the installation-guide for all architectures. Triggered by successful build of <a href="https://jenkins.debian.net/job/d-i_manual_{lang}_html">d-i_manual_{lang}_html</a>. {do_not_edit}'
    return s


def instguide_desc():
    return 'Builds the installation-guide package. Triggered by SVN commits to <code>svn://anonscm.debian.org/svn/d-i/</code> matching these patterns: <pre>{include}</pre> {do_not_edit}'


def lr(keep):
    return {'artifactDaysToKeep': -1, 'daysToKeep': keep, 'numToKeep': 30, 'artifactNumToKeep': -1}


def publ_email(irc=None):
    r = ['jenkins+' + irc] if irc != None else []
    r.append('qa-jenkins-scm@lists.alioth.debian.org')
    return [{'email': {'recipients': ' '.join(r)}}]


def publ(fmt=None,trigger=False,irc=None):
    p = []
    if trigger:
        p = [{'trigger': {'project': 'd-i_manual_{lang}_pdf', 'threshold': 'UNSTABLE'}}]
    p.extend([
        {'logparser': {'parse-rules': '/srv/jenkins/logparse/debian-installer.rules',
                       'unstable-on-warning': 'true',
                       'fail-on-error': 'true'}}])
    p.extend(publ_email(irc=irc))
    if fmt != None:
        p.append({'archive': {'artifacts': fmt + '/**/*.*', 'latest_only': True}})
    return p


def prop(type='manual', priority=None):
    p = [{'sidebar': {'url': 'https://jenkins.debian.net/userContent/about.html',
                      'text': 'About jenkins.debian.net',
                      'icon': '/userContent/images/debian-swirl-24x24.png'}},
         {'sidebar': {'url': 'https://jenkins.debian.net/view/d-i_' + type + '/',
                      'text': 'debian-installer ' + type + ' jobs',
                      'icon': '/userContent/images/debian-jenkins-24x24.png'}},
         {'sidebar': {'url': 'http://www.profitbricks.co.uk',
                      'text': 'Sponsored by Profitbricks',
                      'icon': '/userContent/images/profitbricks-24x24.png'}}]
    if priority != None:
        p.append( {'priority': {'job-prio': str(priority)}} )
    return p


def jtmpl(act, target, fmt=None, po=False):
    n = ['{name}', act, target]
    d = [ 'd-i', act ]
    if fmt:
        n.append(fmt)
        d.append(fmt)
    if po:
        d.append('po2xml')
    return {'job-template': {'name': '_'.join(n), 'defaults': '-'.join(d)}}


def jobspec_svn(key, name, desc=None, defaults=None,
                priority=120, logkeep=None, trigger=None, publisher=None,
                lang=None, fmt=None, po=False, inc_regs=None ):
    j = {'scm': scm_svn(po=po,inc_regs=inc_regs),
         'project-type': 'freestyle',
         'builders': [{'shell': '/srv/jenkins/bin/d-i_manual.sh'
                       + (' ' + lang if lang else '')
                       + (' ' + fmt if fmt else '')
                       + (' po2xml' if po else '')}],
         'properties': prop(priority=priority),
         'name': name}
    j['publishers'] = publisher() if publisher != None else publ(fmt=fmt,trigger=trigger,irc='debian-boot')

    if desc != None:
        j['description'] = desc()
    else:
        if fmt != None:
            j['description'] = svn_desc(po=po,fmt=fmt)
    if defaults != None:
        j['defaults'] = defaults
    if trigger != None:
        j['triggers'] = [{'pollscm': '*/' + str(trigger) + ' * * * *'}]
    if logkeep != None:
        j['logrotate'] = lr(logkeep)
    return { key : j }


data = []

data.append({'defaults': { 'name': 'd-i',
                           'logrotate': lr(90),
                           'project-type': 'freestyle',
                           'properties': prop(type='misc')}})

data.extend(
    [jobspec_svn(key='defaults',
                 name='d-i-manual-' + fmt + ('-po2xml' if po else ''),
                 fmt=fmt,
                 lang='{lang}',
                 trigger=None if fmt == 'pdf' else 15 if not po else 30,
                 desc=pdf_desc if fmt == 'pdf' else None,
                 po=po,
                 logkeep=90)
     for fmt in ['html', 'pdf']
     for po  in [False, True]])

data.extend(
    [{'defaults': { 'name': n,
                   'description': 'Builds debian packages in sid from git '+ bdsc +', triggered by pushes to <pre>{gitrepo}</pre> {do_not_edit}',
                   'triggers': [{'pollscm': trg}],
                   'scm': [{'git': {'url': '{gitrepo}',
                                    'branches': [br]}}],
                   'builders': [{'shell': '/srv/jenkins/bin/d-i_build.sh'}],
                   'project-type': 'freestyle',
                   'properties': prop(type='packages', priority=99),
                   'logrotate': lr(90),
                   'publishers': publ(irc=irc)}}
     for (n,bdsc,br,trg,irc)
     in [('d-i-build',    'master branch', 'master', '*/6 * * * *',  'debian-boot'),
         ('d-i-pu-build', 'pu/ branches',  'pu/**' , '*/10 * * * *', None)]])

data.append(jobspec_svn(key='job-template',
                        defaults='d-i',
                        name='{name}_manual',
                        desc=instguide_desc,
                        trigger=15,
                        priority=125,
                        publisher=publ_email,
                        inc_regs='{include}'))

data.append(
    {'job-template': { 'defaults': 'd-i',
                       'name': '{name}_check_jenkins_jobs',
                       'description': 'Checks daily for missing jenkins jobs. {do_not_edit}',
                       'triggers': [{'timed': '23 0 * * *'}],
                       'builders': [{'shell': '/srv/jenkins/bin/d-i_check_jobs.sh'}],
                       'publishers': [{'logparser': {'parse-rules': '/srv/jenkins/logparse/debian.rules',
                                                     'unstable-on-warning': 'true',
                                                     'fail-on-error': 'true'}},
                                      {'email': {'recipients': 'qa-jenkins-scm@lists.alioth.debian.org'}}]}}
)

data.append(
    {'job-template': { 'defaults': 'd-i',
                       'name': '{name}_maintenance',
                       'description': 'Cleanup and monitor so that there is a predictable environment.{do_not_edit}',
                       'triggers': [{'timed': '30 5 * * *'}],
                       'builders': [{'shell': '/srv/jenkins/bin/maintenance.sh {name}'}],
                       'properties': prop(priority=150),
                       'publishers': [{'logparser': {'parse-rules': '/srv/jenkins/logparse/debian.rules',
                                                     'unstable-on-warning': 'true',
                                                     'fail-on-error': 'true'}},
                                      {'email': {'recipients': 'jenkins+debian-boot qa-jenkins-scm@lists.alioth.debian.org'}}]}}
)

data.extend(
    [jtmpl(act='manual',target=l,fmt=f,po=(l not in non_po_langs))
     for f in ['html', 'pdf']
     for l in sorted(langs.keys())
     if not (f=='pdf' and l in non_pdf_langs)])

data.extend(
    [jtmpl(act=act,target=pkg)
     for act in ['build', 'pu-build']
     for pkg in pkgs])

jobs = [ '{name}_maintenance',
         '{name}_check_jenkins_jobs',
         {'{name}_manual': {'include': ( '/trunk/manual/debian/.*\n'
                                         '/trunk/manual/po/.*\n'
                                         '/trunk/manual/doc/.*\n'
                                         '/trunk/manual/scripts/.*' )}}]

jobs.extend(
    [{'_'.join(['{name}','manual',l,f]): {'lang': l, 'languagename': langs[l]}}
     for f in ['html', 'pdf']
     for l in sorted(langs.keys())
     if not (f=='pdf' and l in non_pdf_langs)])

jobs.extend(
    [{'_'.join(['{name}',act,pkg]): {'gitrepo': 'git://git.debian.org/git/d-i/' + pkg}}
     for act in ['build', 'pu-build']
     for pkg in pkgs])

data.append(
    {'project': { 'name': 'd-i',
                  'do_not_edit': '<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/d-i.yaml.py">d-i.yaml.py</a>.',
                  'jobs': jobs}})

sys.stdout.write( dump(data, Dumper=Dumper) )
