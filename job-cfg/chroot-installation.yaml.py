#!/usr/bin/python

base_distros = """
   squeeze
   wheezy
   jessie
   sid
   """.split()

distro_upgrades = { 'squeeze':  'wheezy',
                    'wheezy':  'jessie',
                    'jessie':  'sid' }

oldstable = 'squeeze'

# ftp.de.debian.org runs mirror updates at 03:25, 09:25, 15:25 and 21:25 UTC and usually they run 10m...
trigger_times = { 'squeeze': '30 16 25 * *',
                  'wheezy':  '30 16 4,18 * *',
                  'jessie':  '30 10 */2 * *',
                  'sid':     '30 4 * * *' }

targets = """
   maintainance
   bootstrap
   gnome
   kde
   kde-full
   cinnamon
   lxde
   xfce
   full_desktop
   haskell
   developer
   education-tasks
   education-menus
   education-astronomy
   education-chemistry
   education-common
   education-desktop-gnome
   education-desktop-kde
   education-desktop-lxde
   education-desktop-mate
   education-desktop-other
   education-desktop-sugar
   education-desktop-xfce
   education-development
   education-electronics
   education-geography
   education-graphics
   education-language
   education-laptop
   education-logic-games
   education-main-server
   education-mathematics
   education-misc
   education-music
   education-networked
   education-physics
   education-services
   education-standalone
   education-thin-client
   education-thin-client-server
   education-workstation
   """.split()

#
# not all packages are available in all distros
#
def get_targets_in_distro(distro, targets):
     targets_in_distro = []
     for target in targets:
         # haskell and edu tests not in squeeze
         if distro == 'squeeze' and ( target == 'haskell' or target[:10] == 'education-'):
             continue
         # education-desktop-mate wasn't in wheezy
         if distro == 'wheezy' and target == 'education-desktop-mate':
             continue
         targets_in_distro.append(target)
     return targets_in_distro

#
# who gets mail for which target
#
def get_recipients(target):
    if target == 'maintainance':
        return 'holger@layer-acht.org'	# FIXME: this should be jenkins-maintainers@lists.somewhere
    elif target == 'haskell':
        return 'jenkins+debian-haskell holger@layer-acht.org pkg-haskell-maintainers@lists.alioth.debian.org'
    elif target[:8] == 'cinnamon':
        return 'jenkins+debian-cinnamon pkg-cinnamon-team@lists.alioth.debian.org holger@layer-acht.org'
    elif target[:3] == 'kde':
        return 'jenkins+debian-qa debian-qt-kde@lists.debian.org holger@layer-acht.org'
    elif target[:10] == 'education-':
        return 'jenkins+debian-edu debian-edu-commits@lists.alioth.debian.org'
    else:
        return 'jenkins+debian-qa holger@layer-acht.org'

#
# views for different targets
#
def get_view(target, distro):
    if target == 'maintainance':
        return 'jenkins.d.n'
    elif target == 'haskell':
        return 'haskell'
    elif target[:10] == 'education-':
        if distro in ('squeeze', 'wheezy'):
            return 'edu_stable'
        else:
            return 'edu_devel'
    else:
        return 'chroot-installation'

#
# special descriptions used for some targets
#
spoken_names = {}
spoken_names = { 'gnome': 'GNOME',
                 'kde': 'KDE plasma desktop',
                 'kde-full': 'complete KDE desktop',
                 'cinnamon': 'Cinnamon',
                 'lxde': 'LXDE',
                 'xfce': 'Xfce',
                 'full_desktop': 'four desktop environments and the most commonly used applications and packages',
                 'haskell': 'all Haskell related packages',
                 'developer': 'four desktop environments and the most commonly used applications and packages - and the build depends for all of these' }
def get_spoken_name(target):
    if target[:10] == 'education-':
         return 'the Debian Edu metapackage '+target
    elif target in spoken_names:
         return spoken_names[target]
    else:
         return target

#
# nothing to edit below
#

print("""
- defaults:
    name: chroot-installation
    description: '{my_description}{do_not_edit}'
    logrotate:
      daysToKeep: 90
      numToKeep: 30
      artifactDaysToKeep: -1
      artifactNumToKeep: -1
    triggers:
      - timed: '{my_time}'
    builders:
      - shell: '{my_shell}'
    publishers:
      - trigger:
          project: '{my_trigger}'
      - logparser:
          parse-rules: '/srv/jenkins/logparse/debian.rules'
          unstable-on-warning: 'false'
          fail-on-error: 'false'
      - email-ext:
          recipients: '{my_recipients}'
          first-failure: true
          fixed: true
          subject: '$BUILD_STATUS: $JOB_NAME/$BUILD_NUMBER'
          attach-build-log: true
          body: 'See $BUILD_URL/console or just $BUILD_URL for more information.'
    properties:
      - sidebar:
          url: https://jenkins.debian.net/userContent/about.html
          text: About jenkins.debian.net
          icon: /userContent/images/debian-swirl-24x24.png
      - sidebar:
          url: https://jenkins.debian.net/view/{my_view}/
          text: All {my_view} jobs
          icon: /userContent/images/debian-jenkins-24x24.png
      - sidebar:
          url: http://www.profitbricks.com
          text: Sponsored by Profitbricks
          icon: /userContent/images/profitbricks-24x24.png
      - priority:
          job-prio: '{my_prio}'
      - throttle:
          max-total: 6
          max-per-node: 6
          enabled: true
          option: category
          categories:
            - chroot-installation

""")
for base_distro in sorted(base_distros):
    for target in sorted(get_targets_in_distro(base_distro, targets)):
        if target in ('bootstrap', 'maintainance'):
             action = target
        else:
             action = 'install_'+target
        if target == 'maintainance' or base_distro != oldstable:
            print("""- job-template:
    defaults: chroot-installation
    name: '{name}_%(base_distro)s_%(action)s'""" %
             dict(base_distro=base_distro,
                  action=action))
        if base_distro in distro_upgrades and action != 'maintainance':
             print("""- job-template:
    defaults: chroot-installation
    name: '{name}_%(base_distro)s_%(action)s_upgrade_to_%(second_base)s'""" %
             dict(base_distro=base_distro,
                  action=action,
                  second_base=distro_upgrades[base_distro]))

print("""
- project:
    name: chroot-installation
    do_not_edit: '<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/chroot-installation.yaml.py">chroot-installation.yaml.py</a>.'
    jobs:""")
for base_distro in sorted(base_distros):
    for target in sorted(get_targets_in_distro(base_distro, targets)):
        if target == 'maintainance':
            description = 'Maintainance job for chroot-installation_'+base_distro+'_* jobs, do some cleanups and monitoring so that there is a predictable environment.'
            shell = '/srv/jenkins/bin/maintainance.sh chroot-installation_'+base_distro
            prio = 135
            time = trigger_times[base_distro]
            if base_distro in distro_upgrades.values():
                trigger = 'chroot-installation_'+base_distro+'_bootstrap'
                for item in distro_upgrades.items():
                    if item[1]==base_distro and base_distro in distro_upgrades:
                         trigger = trigger+', chroot-installation_'+base_distro+'_bootstrap_upgrade_to_'+distro_upgrades[base_distro]
            else:
                trigger = 'chroot-installation_'+base_distro+'_bootstrap_upgrade_to_'+distro_upgrades[base_distro]
        elif target == 'bootstrap':
            description = 'Debootstrap '+base_distro+'.'
            shell = '/srv/jenkins/bin/chroot-installation.sh '+base_distro
            prio = 131
            time = ''
            trigger = ''
            for trigger_target in get_targets_in_distro(base_distro, targets):
                if trigger_target not in ('maintainance', 'bootstrap'):
                    if trigger != '':
                        trigger = trigger+', '
                    trigger = trigger+'chroot-installation_'+base_distro+'_install_'+trigger_target
        else:
            description = 'Debootstrap '+base_distro+', then install '+get_spoken_name(target)+'.'
            shell = '/srv/jenkins/bin/chroot-installation.sh '+base_distro+' '+target
            prio = 130
            time = ''
            trigger = ''
        if target in ('bootstrap', 'maintainance'):
            action = target
        else:
            action = 'install_'+target
        if target == 'maintainance' or base_distro != oldstable:
            print("""      - '{name}_%(base_distro)s_%(action)s':
            my_shell: '%(shell)s'
            my_prio: '%(prio)s'
            my_time: '%(time)s'
            my_trigger: '%(trigger)s'
            my_recipients: '%(recipients)s'
            my_view: '%(view)s'
            my_description: '%(description)s'""" %
             dict(base_distro=base_distro,
                  action=action,
                  shell=shell,
                  prio=prio,
                  time=time,
                  trigger=trigger,
                  recipients=get_recipients(target),
                  view=get_view(target, base_distro),
                  description=description))
        if base_distro in distro_upgrades and action != 'maintainance':
            if target == 'bootstrap':
                shell = '/srv/jenkins/bin/chroot-installation.sh '+base_distro+' none '+distro_upgrades[base_distro]
                description = 'Debootstrap '+base_distro+', then upgrade to '+distro_upgrades[base_distro]+'.'
                trigger = ''
                for trigger_target in get_targets_in_distro(base_distro, targets):
                    if trigger_target not in ('maintainance', 'bootstrap'):
                        if trigger != '':
                            trigger = trigger+', '
                        trigger = trigger+'chroot-installation_'+base_distro+'_install_'+trigger_target+'_upgrade_to_'+distro_upgrades[base_distro]
            else:
                shell = '/srv/jenkins/bin/chroot-installation.sh '+base_distro+' '+target+' '+distro_upgrades[base_distro]
                description = 'Debootstrap '+base_distro+', then install '+get_spoken_name(target)+', then upgrade to '+distro_upgrades[base_distro]+'.'
                trigger = ''
            print("""      - '{name}_%(base_distro)s_%(action)s_upgrade_to_%(second_base)s':
            my_shell: '%(shell)s'
            my_prio: '%(prio)s'
            my_time: ''
            my_trigger: '%(trigger)s'
            my_recipients: '%(recipients)s'
            my_view: '%(view)s'
            my_description: '%(description)s'""" %
             dict(base_distro=base_distro,
                  action=action,
                  shell=shell,
                  prio=prio,
                  trigger=trigger,
                  recipients=get_recipients(target),
                  view=get_view(target, base_distro),
                  second_base=distro_upgrades[base_distro],
                  description=description))

