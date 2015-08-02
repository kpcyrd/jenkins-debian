#!/usr/bin/python

packages = """
   lintian
   debsums
   """.split()

shell = { 'lintian':  'timeout 6h debian/rules runtests',
           'debsums':  'timeout 5m prove -v' }

distros = { 'lintian':  ( 'sid', 'jessie', 'wheezy backports' ),
            'debsums':  ( 'sid', 'jessie', 'wheezy' ) }
#FIXME: add stretch too
recipients = { 'lintian':  'jenkins+debian-qa qa-jenkins-scm@lists.alioth.debian.org lintian-maint@debian.org',
               'debsums':  'jenkins+debian-qa qa-jenkins-scm@lists.alioth.debian.org pkg-perl-maintainers@lists.alioth.debian.org'
             }

git-repo = { 'lintian':  'git://anonscm.debian.org/lintian/lintian.git',
             'debsums':  'git://anonscm.debian.org/pkg-perl/packages/debsums.git' }

#
# nothing to edit below
#

print("""
- defaults:
    name: qa.debian.org-tests
    project-type: freestyle
    properties:
      - sidebar:
          url: https://jenkins.debian.net/userContent/about.html
          text: About jenkins.debian.net
          icon: /userContent/images/debian-swirl-24x24.png
      - sidebar:
          url: https://jenkins.debian.net/view/qa.debian.org/
          text: Jobs for Debian QA related packages
          icon: /userContent/images/debian-jenkins-24x24.png
      - sidebar:
          url: http://www.profitbricks.co.uk
          text: Sponsored by Profitbricks
          icon: /userContent/images/profitbricks-24x24.png
    description: '{my_description}<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/qa.debian.org-tests.yaml.py">qa.debian.org-tests.yaml.py</a>.'
    logrotate:
      daysToKeep: 90
      numToKeep: 30
      artifactDaysToKeep: -1
      artifactNumToKeep: -1
    scm:
      - git:
          url: '{my_repo}'
          branches:
            - master
    builders:
      - shell: '/srv/jenkins/bin/chroot-run.sh {my_distro} {my_shell}'

""")
for package in sorted(packages):
    print("""
- job-template:
    defaults: qa.debian.org-tests
    name: '%(package)s_wheezy'
    publishers:
      - email:
          recipients: '%(recipients)s'

- job-template:
    defaults: qa.debian.org-tests
    name: '%(package)s_jessie'
    publishers:
      - email:
          recipients: '%(recipients)s'
      - trigger:
          project: '{my_trigger}'

- job-template:
    defaults: qa.debian.org-tests
    name: '%(package)s_sid'
    triggers:
      - pollscm: '*/6 * * * *'
    publishers:
      - email:
          recipients: '%(recipients)s'
      - trigger:
          project: '{my_trigger}'
""" %
             dict(package=package,
                  recipients=recipients[package]))

print("""
- project:
    name: qa.debian.org-tests
    jobs:""")
for package in sorted(packages):
    print("""
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

        - '{name}_sid':
            my_distro: 'sid'
            my_shell: 'timeout 6h debian/rules runtests'
            my_description: 'Debian/Lintian testsuite running on sid.'
            my_trigger: 'qa.debian.org-tests_jessie'
        - '{name}_jessie':
            my_distro: 'jessie'
            my_shell: 'timeout 6h debian/rules runtests'
            my_description: 'Debian/Lintian testsuite running on jessie.'
            my_trigger: 'qa.debian.org-tests_wheezy'
        - '{name}_wheezy':
            my_distro: 'wheezy backports'
            my_shell: 'timeout 6h debian/rules runtests'
            my_description: 'Debian/Lintian testsuite running on wheezy (+backports).'

