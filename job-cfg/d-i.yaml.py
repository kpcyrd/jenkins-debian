#!/usr/bin/python

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


def sb_about():
    return {'sidebar': {'url': 'https://jenkins.debian.net/userContent/about.html',
                        'text': 'About jenkins.debian.net',
                        'icon': '/userContent/images/debian-swirl-24x24.png'}}

def sb_misc():
    return {'sidebar': {'url': 'https://jenkins.debian.net/view/d-i_misc/',
                        'text': 'Misc debian-installer jobs',
                        'icon': '/userContent/images/debian-jenkins-24x24.png'}}

def sb_manual():
    return {'sidebar': {'url': 'https://jenkins.debian.net/view/d-i_manual/',
                        'text': 'debian-installer manual jobs',
                        'icon': '/userContent/images/debian-jenkins-24x24.png'}}

def sb_pkgs():
    return {'sidebar': {'url': 'https://jenkins.debian.net/view/d-i_packages/',
                        'text': 'debian-installer packages jobs',
                        'icon': '/userContent/images/debian-jenkins-24x24.png'}}

def sb_pbricks():
    return {'sidebar': {'url': 'http://www.profitbricks.co.uk',
                        'text': 'Sponsored by Profitbricks',
                        'icon': '/userContent/images/profitbricks-24x24.png'}}

def lr(keep):
    return {'artifactDaysToKeep': -1, 'daysToKeep': keep, 'numToKeep': 30, 'artifactNumToKeep': -1}


def publ(fmt=None,trigger=False):
    p = []
    if trigger:
        p = [{'trigger': {'project': 'd-i_manual_{lang}_pdf', 'threshold': 'UNSTABLE'}}]
    p.extend([
        {'logparser': {'parse-rules': '/srv/jenkins/logparse/debian-installer.rules',
                       'unstable-on-warning': 'true',
                       'fail-on-error': 'true'}},
        {'email': {'recipients': 'jenkins+debian-bot qa-jenkins-scm@lists.alioth.debian.org'}}])
    if fmt != None:
        p.append({'archive': {'artifacts': fmt + '/**/*.*', 'latest_only': True}})
    return p


def publ_email():
        return [{'email': {'recipients': 'jenkins+debian-boot qa-jenkins-scm@lists.alioth.debian.org'}}]


def prop(middle=sb_manual, priority=None):
    arr = [sb_about(), middle(), sb_pbricks()]
    if priority != None:
        arr.append( {'priority': {'job-prio': str(priority)}} )
    return arr


def jtmpl(act, lang, fmt=None, po=False):
    n = ['{name}', act, lang]
    d = [ 'd-i', act ]
    if fmt:
        n.append(fmt)
        d.append(fmt)
    if po:
        d.append('po2xml')
    return {'job-template': {'name': '_'.join(n), 'defaults': '-'.join(d)}}


def jobspec_svn(name, desc=None, defaults=None,
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
    j['publishers'] = publisher() if publisher != None else publ(fmt=fmt,trigger=trigger)

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
    return j


data = []

data.append( {'defaults': { 'name': 'd-i',
                            'logrotate': lr(90),
                            'project-type': 'freestyle',
                            'properties': prop(middle=sb_misc)}})

data.append( {'defaults': jobspec_svn( name='d-i-manual-html',
                                       fmt='html',
                                       lang='{lang}',
                                       trigger=15,
                                       logkeep=90 )})

data.append( {'defaults': jobspec_svn( name='d-i-manual-html-po2xml',
                                       fmt='html',
                                       lang='{lang}',
                                       po=True,
                                       trigger=30,
                                       logkeep=90 )})

data.append( {'defaults': jobspec_svn( name='d-i-manual-pdf',
                                       fmt='pdf',
                                       lang='{lang}',
                                       desc=pdf_desc,
                                       logkeep=90 )})

data.append( {'defaults': jobspec_svn( name='d-i-manual-pdf-po2xml',
                                       fmt='pdf',
                                       lang='{lang}',
                                       desc=pdf_desc,
                                       po=True,
                                       logkeep=90 )})

data.append( {'defaults': { 'name': 'd-i-build',
                   'description': 'Builds debian packages in sid from git master branch, triggered by pushes to <pre>{gitrepo}</pre> {do_not_edit}',
                   'triggers': [{'pollscm': '*/6 * * * *'}],
                   'scm': [{'git': {'url': '{gitrepo}',
                                    'branches': ['master']}}],
                   'builders': [{'shell': '/srv/jenkins/bin/d-i_build.sh'}],
                   'project-type': 'freestyle',
                   'properties': prop(middle=sb_pkgs, priority=99),
                   'logrotate': lr(90),
                   'publishers': publ()}}
)

data.append( {'defaults': { 'name': 'd-i-pu-build',
                   'description': 'Builds debian packages in sid from git pu/ branches, triggered by pushes to <pre>{gitrepo}</pre> {do_not_edit}',
                   'triggers': [{'pollscm': '*/30 * * * *'}],
                   'scm': [{'git': {'url': '{gitrepo}',
                                    'branches': ['pu/**']}}],
                   'builders': [{'shell': '/srv/jenkins/bin/d-i_build.sh'}],
                   'project-type': 'freestyle',
                   'properties': prop(middle=sb_pkgs, priority=99),
                   'logrotate': lr(90),
                   'publishers': publ()}}
)

data.append({'job-template': jobspec_svn( defaults='d-i',
                                          name='{name}_manual',
                                          desc=instguide_desc,
                                          trigger=15, priority=125,
                                          publisher=publ_email,
                                          inc_regs='{include}')})

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


data.extend(map(lambda (l, f): jtmpl(act='manual',lang=l,fmt=f,po=(l not in non_po_langs)),
                filter(lambda (l, f): not (f=='pdf' and l in non_pdf_langs),
                       [(l, f)
                        for f in ['html', 'pdf']
                        for l in langs.keys()])))

data.extend(map(lambda l: jtmpl(act='build',lang=l), pkgs))

data.extend(map(lambda l: jtmpl(act='pu-build',lang=l), pkgs))


jobs = [ '{name}_maintenance',
         '{name}_check_jenkins_jobs',
         {'{name}_manual': {'include': ( '/trunk/manual/debian/.*\n'
                                         '/trunk/manual/po/.*\n'
                                         '/trunk/manual/doc/.*\n'
                                         '/trunk/manual/scripts/.*' )}}]

jobs.extend(map(lambda (l, fmt): {'_'.join(['{name}','manual',l,fmt]): {'lang': l, 'languagename': langs[l]}},
                filter(lambda (l, f): not (f=='pdf' and l in non_pdf_langs),
                       [(l, f)
                        for f in ['html', 'pdf']
                        for l in langs.keys()])))

jobs.extend(map(lambda (p): {'_'.join(['{name}','build',p]):    {'gitrepo': 'git://git.debian.org/git/d-i/' + p}},
                pkgs))

jobs.extend(map(lambda (p): {'_'.join(['{name}','pu-build',p]): {'gitrepo': 'git://git.debian.org/git/d-i/' + p}},
                pkgs))

data.append(
    {'project': { 'name': 'd-i',
                  'do_not_edit': '<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/d-i.yaml.py">d-i.yaml.py</a>.',
                  'jobs': jobs}}
)

sys.stdout.write( dump(data, Dumper=Dumper) )
