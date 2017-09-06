#!/usr/bin/python
# -*- coding: utf-8 -*-

import sys
import os
from string import join
from yaml import load, dump
try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper


base_distros = [
    'jessie',
    'stretch',
    'buster',
    'sid',
    ]

distro_upgrades = {
    'jessie':  'stretch',
    'stretch':  'buster',
    'buster': 'sid',
    }

# deb.debian.org runs mirror updates at 03:25, 09:25, 15:25 and 21:25 UTC and usually they run 10m...
trigger_times = {
    'jessie':  '30 16 1 * *',
    'stretch':  '30 10 * * 5',
    'buster': '30 10 */2 * *',
    'sid':     '30 4 * * *',
    }

all_targets = [
   'gnome',
   'kde',
   'kde-full',
   'cinnamon',
   'lxde',
   'xfce',
   'full_desktop',
   'qt4',
   'qt5',
   'haskell',
   'developer',
   'debconf-video',
   'education-tasks',
   'education-menus',
   'education-astronomy',
   'education-chemistry',
   'education-common',
   'education-desktop-gnome',
   'education-desktop-kde',
   'education-desktop-lxde',
   'education-desktop-lxqt',
   'education-desktop-mate',
   'education-desktop-other',
   'education-desktop-xfce',
   'education-development',
   'education-electronics',
   'education-geography',
   'education-graphics',
   'education-language',
   'education-lang-da',
   'education-lang-de',
   'education-lang-es',
   'education-lang-fr',
   'education-lang-he',
   'education-lang-it',
   'education-lang-ja',
   'education-lang-no',
   'education-lang-se',
   'education-lang-zh-tw',
   'education-laptop',
   'education-logic-games',
   'education-ltsp-server',
   'education-main-server',
   'education-mathematics',
   'education-misc',
   'education-music',
   'education-networked',
   'education-physics',
   'education-primaryschool',
   'education-services',
   'education-standalone',
   'education-thin-client',
   'education-thin-client-server',
   'education-roaming-workstation',
   'education-video',
   'education-workstation',
   'parl-desktop-eu',
   'parl-desktop-strict',
   'parl-desktop-world',
   'design-desktop-animation',
   'design-desktop-graphics',
   'design-desktop-strict',
   'design-desktop-web',
   ]

#
# not all packages are available in all distros
#
def is_target_in_distro(distro, target):
         # education-ltsp-server and education-roaming-workstation are only availble since stretch…
         if distro in ('jessie') and target in ('education-ltsp-server', 'education-roaming-workstation'):
             return False
         # education-thin-client-server is obsolete since stretch…
         elif distro in ('sid', 'buster', 'stretch') and target == 'education-thin-client-server':
             return False
         # education-lang-*, parl-desktop* and design-desktop* packages only exist since stretch
         elif distro in ('jessie') and (target[:15] == 'education-lang-' or target[:12] == 'parl-desktop' or target[:14] == 'design-desktop'):
             return False
         # education-desktop-lxqt, education-primaryschool and education-video packages only exist since buster
         elif distro in ('jessie', 'stretch') and target in ('education-desktop-lxqt', 'education-primaryschool', 'education-video'):
             return False
         return True

#
# who gets mail for which target
#
def get_recipients(target):
    if target == 'haskell':
        return 'jenkins+debian-haskell qa-jenkins-scm@lists.alioth.debian.org pkg-haskell-maintainers@lists.alioth.debian.org'
    elif target == 'gnome':
        return 'jenkins+debian-qa pkg-gnome-maintainers@lists.alioth.debian.org qa-jenkins-scm@lists.alioth.debian.org'
    elif target == 'cinnamon':
        return 'jenkins+debian-cinnamon pkg-cinnamon-team@lists.alioth.debian.org qa-jenkins-scm@lists.alioth.debian.org'
    elif target == 'debconf-video':
        return 'jenkins+debconf-video qa-jenkins-scm@lists.alioth.debian.org'
    elif target[:3] == 'kde' or target[:2] == 'qt':
        return 'jenkins+debian-qa debian-qt-kde@lists.debian.org qa-jenkins-scm@lists.alioth.debian.org'
    elif target[:10] == 'education-':
        return 'jenkins+debian-edu debian-edu-commits@lists.alioth.debian.org'
    else:
        return 'jenkins+debian-qa qa-jenkins-scm@lists.alioth.debian.org'

#
# views for different targets
#
def get_view(target, distro):
    if target == 'haskell':
        return 'haskell'
    elif target[:10] == 'education-':
        if distro in ('jessie', 'stretch'):
            return 'edu_stable'
        else:
            return 'edu_devel'
    else:
        return 'chroot-installation'

#
# special descriptions used for some targets
#
spoken_names = {
    'gnome': 'GNOME',
    'kde': 'KDE plasma desktop',
    'kde-full': 'complete KDE desktop',
    'cinnamon': 'Cinnamon',
    'lxde': 'LXDE',
    'xfce': 'Xfce',
    'qt4': 'Qt4 cross-platform C++ application framework',
    'qt5': 'Qt5 cross-platform C++ application framework',
    'full_desktop': 'four desktop environments and the most commonly used applications and packages',
    'haskell': 'all Haskell related packages',
    'developer': 'four desktop environments and the most commonly used applications and packages - and the build depends for all of these',
    'debconf-video': 'all packages relevant for the DebConf videoteam',
    }

def get_spoken_name(target):
    if target[:12] == 'parl-desktop':
         return 'the Debian Parl metapackage '+target
    elif target[:14] == 'design-desktop':
         return 'the Debian Parl metapackage '+target
    elif target[:10] == 'education-':
         return 'the Debian Edu metapackage '+target
    elif target in spoken_names:
         return spoken_names[target]
    else:
         return target

#
# nothing to edit below
#

#
# This structure contains the differences between the default, upgrade and upgrade_apt+dpkg_first jobs
#
jobspecs = [
    { 'j_ext': '',
      'd_ext': '',
      's_ext': '',
      'dist_func': (lambda d: d),
      'distfilter': (lambda d: tuple(set(d))),
      'skiptaryet': (lambda t: False)
    },
    { 'j_ext': '_upgrade_to_{dist2}',
      'd_ext': ', then upgrade to {dist2}',
      's_ext': ' {dist2}',
      'dist_func': (lambda d: [{dist: {'dist2': distro_upgrades[dist]}} for dist in d]),
      'distfilter': (lambda d: tuple(set(d) & set(distro_upgrades))),
      'skiptaryet': (lambda t: False)
    },
]

# some functions first…

#
# return the list of targets, filtered to be those present in 'distro'
#
def get_targets_in_distro(distro):
     return [t for t in all_targets if is_target_in_distro(distro, t)]

#
# given a target, returns a list of ([dist], key) tuples, so we can handle the
# edu packages having views that are distro dependant
#
# this groups all the distros that have matching views
#
def get_dists_per_key(target,get_distro_key):
    dists_per_key = {}
    for distro in base_distros:
        if is_target_in_distro(distro, target):
            key = get_distro_key(distro)
            if key not in dists_per_key.keys():
                dists_per_key[key] = []
            dists_per_key[key].append(distro)
    return dists_per_key


# main…

data = []
jobs = []

data.append(
   {   'defaults': {   'builders': [{   'shell': '{my_shell}'}],
                        'description': '{my_description}{do_not_edit}',
                        'logrotate': {   'artifactDaysToKeep': -1,
                                         'artifactNumToKeep': -1,
                                         'daysToKeep': 120,
                                         'numToKeep': 150},
                        'name': 'chroot-installation',
                        'properties': [   {   'sidebar': {   'icon': '/userContent/images/debian-swirl-24x24.png',
                                                             'text': 'About jenkins.debian.net',
                                                             'url': 'https://jenkins.debian.net/userContent/about.html'}},
                                          {   'sidebar': {   'icon': '/userContent/images/debian-jenkins-24x24.png',
                                                             'text': 'All {my_view} jobs',
                                                             'url': 'https://jenkins.debian.net/view/{my_view}/'}},
                                          {   'sidebar': {   'icon': '/userContent/images/profitbricks-24x24.png',
                                                             'text': 'Sponsored by Profitbricks',
                                                             'url': 'http://www.profitbricks.co.uk'}},
                                          {   'priority-sorter': {   'priority': '{my_prio}'}},
                                          {   'throttle': {   'categories': [   'chroot-installation'],
                                                              'enabled': True,
                                                              'max-per-node': 6,
                                                              'max-total': 6,
                                                              'option': 'category'}}],
                        'publishers': [   {   'trigger': {   'project': '{my_trigger}'}},
                                          {   'email-ext': {   'attach-build-log': False,
                                                               'body': 'See $BUILD_URL/console or just $BUILD_URL for more information.',
                                                               'first-failure': True,
                                                               'failure': False,
                                                               'fixed': True,
                                                               'recipients': '{my_recipients}',
                                                               'subject': '$BUILD_STATUS: $JOB_NAME/$BUILD_NUMBER'}},
                                          {   'logparser': {   'parse-rules': '/srv/jenkins/logparse/chroot-installation.rules',
                                                               'unstable-on-warning': True,}},
                                          {   'naginator': {   'progressive-delay-increment': 5,
                                                               'progressive-delay-maximum': 15,
                                                               'max-failed-builds': 3,
                                                               'regular-expression': '^E:     Couldn.t     download     .*/Packages'}}],
                        'triggers': [{   'timed': '{my_time}'}],
                        'wrappers': [{   'timeout': {   'timeout': 360}}]}})
data.append(
    {   'job-template': {   'defaults': 'chroot-installation',
                            'name': '{name}_{dist}_{action}'}})
data.append(
    {   'job-template': {   'defaults': 'chroot-installation',
                            'name': '{name}_{dist}_install_{target}'}})
data.append(
    {   'job-template': {   'defaults': 'chroot-installation',
                            'name': '{name}_{dist}_{action}_upgrade_to_{dist2}'}})
data.append(
    {   'job-template': {   'defaults': 'chroot-installation',
                            'name': '{name}_{dist}_install_{target}_upgrade_to_{dist2}'}})
# maintenance jobs
maint_distros = []
for base_distro in sorted(base_distros):
    dist2 = ''
    if base_distro in distro_upgrades.values():
        trigger = 'chroot-installation_{dist}_bootstrap'
        for item in distro_upgrades.items():
            if item[1]==base_distro and base_distro in distro_upgrades:
                trigger = trigger+', chroot-installation_{dist}_bootstrap_upgrade_to_{dist2}'
                dist2 = distro_upgrades[base_distro]
    else:
        trigger = 'chroot-installation_{dist}_bootstrap_upgrade_to_{dist2}'
        dist2 = distro_upgrades[base_distro]
    maint_distros.append({ base_distro: {
                              'my_time': trigger_times[base_distro],
                              'dist2': dist2,
                              'my_trigger': trigger}})
jobs.append({ '{name}_{dist}_{action}': {
                  'action': 'maintenance',
                  'dist': maint_distros,
                  'my_description': 'Maintainance job for chroot-installation_{dist}_* jobs, do some cleanups and monitoring so that there is a predictable environment.',
                  'my_prio': '135',
                  'my_recipients': 'qa-jenkins-scm@lists.alioth.debian.org',
                  'my_shell': '/srv/jenkins/bin/maintenance.sh chroot-installation_{dist}',
                  'my_view': 'jenkins.d.n'}})


# bootstrap jobs
js_dists_trigs = [{},{},{}]
for trigs, dists in get_dists_per_key('bootstrap',(lambda d: tuple(sorted(get_targets_in_distro(d))))).items():
    for jobindex, jobspec in enumerate(jobspecs):
        js_dists = jobspec['distfilter'](dists)
        if (js_dists):
            js_disttrig = tuple((tuple(js_dists), trigs))
            js_dists_trigs[jobindex][js_disttrig] = True


for jobindex, jobspec in enumerate(jobspecs):
    jobs.extend([{ '{name}_{dist}_{action}'+jobspec['j_ext']: {
                      'action': 'bootstrap',
                      'dist': list(dists) if jobspec['j_ext'] == '' else
                              [{dist: {'dist2': distro_upgrades[dist]}} for dist in dists],
                      'my_trigger': join(['chroot-installation_{dist}_install_'+t+jobspec['j_ext']
                                          for t in list(trigs)], ', '),
                      'my_description': 'Debootstrap {dist}'+jobspec['d_ext']+'.',
                      'my_prio': 131,
                      'my_time': '',
                      'my_recipients': get_recipients('bootstrap'),
                      'my_shell': '/srv/jenkins/bin/chroot-installation.sh {dist} none'+jobspec['s_ext'],
                      'my_view': get_view('bootstrap', None),
                  }}
                  for (dists, trigs) in js_dists_trigs[jobindex].keys()])

# now all the other jobs
targets_per_distview = [{},{},{}]
for target in sorted(all_targets):
    for view, dists in get_dists_per_key(target,(lambda d: get_view(target, d))).items():
        for jobindex, jobspec in enumerate(jobspecs):
            if jobspec['skiptaryet'](target):
                continue

            js_dists = jobspec['distfilter'](dists)
            if (js_dists):
                distview = tuple((tuple(js_dists), view))
                if distview not in targets_per_distview[jobindex].keys():
                    targets_per_distview[jobindex][distview] = []
                targets_per_distview[jobindex][distview].append(target)

for jobindex, jobspec in enumerate(jobspecs):
    jobs.extend([{ '{name}_{dist}_install_{target}'+jobspec['j_ext']: {
                  'dist': jobspec['dist_func'](list(dists)),
                  'target': [{t: {
                                 'my_spokenname': get_spoken_name(t),
                                 'my_recipients': get_recipients(t)}}
                             for t in dv_targs],
                  'my_description': 'Debootstrap {dist}, then install {my_spokenname}'+jobspec['d_ext']+'.',
                  'my_shell': '/srv/jenkins/bin/chroot-installation.sh {dist} {target}'+jobspec['s_ext'],
                  'my_view': view,
                  }}
                  for (dists, view), dv_targs in targets_per_distview[jobindex].items()])

data.append({'project': {
                 'name': 'chroot-installation',
                 'do_not_edit': '<br><br>Job  configuration source is <a href="https://anonscm.debian.org/git/qa/jenkins.debian.net.git/tree/job-cfg/chroot-installation.yaml.py">chroot-installation.yaml.py</a>.',
                 'my_prio': '130',
                 'my_trigger': '',
                 'my_time': '',
                 'jobs': jobs}})

sys.stdout.write(dump(data, Dumper=Dumper))
