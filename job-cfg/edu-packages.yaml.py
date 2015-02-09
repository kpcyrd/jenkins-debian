#!/usr/bin/python

packages = """
   debian-edu
   debian-edu-config
   debian-edu-install
   debian-edu-doc
   debian-edu-artwork
   debian-edu-archive-keyring
   """.split()

distro="sid"

print("""
- defaults:
    name: edu-packages
    project-type: freestyle
    properties:
      - sidebar:
          url: https://jenkins.debian.net/userContent/about.html
          text: About jenkins.debian.net
          icon: /userContent/images/debian-swirl-24x24.png
      - sidebar:
          url: https://jenkins.debian.net/view/edu_devel
          text: Debian Edu development
          icon: /userContent/images/debian-jenkins-24x24.png
      - sidebar:
          url: http://www.profitbricks.com
          text: Sponsored by Profitbricks
          icon: /userContent/images/profitbricks-24x24.png
    description: 'Build the master branch of git://anonscm.debian.org/debian-edu/{my_package}.git in sid on every commit.<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/edu-packages.yaml">edu-packages.yaml</a>.'
    logrotate:
      daysToKeep: 90
      numToKeep: 30
      artifactDaysToKeep: -1
      artifactNumToKeep: -1
    scm:
      - git:
          url: 'git://anonscm.debian.org/debian-edu/{my_package}.git'
          branches:
            - master
    builders:
      - shell: '/srv/jenkins/bin/chroot-run.sh {my_distro} debuild -b -uc -us'
    triggers:
      - pollscm: '*/6 * * * *'
    publishers:
      - email:
          recipients: 'jenkins+debian-edu debian-edu-commits@lists.alioth.debian.org'

""")

for package in sorted(packages):
    print("""- job-template:
    defaults: edu-packages
    name: '{name}_%(distro)s_%(package)s'""" %
        dict(package=package,
             distro=distro))

print("""
- project:
    name: edu-packages
    jobs:""")
for package in sorted(packages):
    print("""        - '{name}_%(distro)s_%(package)s':
            my_distro: '%(distro)s'
            my_package: '%(package)s'""" %
              dict(package=package,
                  distro=distro))
