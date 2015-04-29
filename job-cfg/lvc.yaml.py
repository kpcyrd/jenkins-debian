#!/usr/bin/python

images = """
    wheezy_standard
    wheezy_gnome-desktop
    debian-edu_jessie_standalone
    debian-edu_jessie_workstation
    debian_jessie_gnome
    debian_jessie_xfce
    debian_sid_xfce
   """.split()

features = """
    apt
   """.split()

files = { 'wheezy_standard': '/var/lib/jenkins/debian-live-7.7.0-amd64-standard.iso',
          'wheezy_gnome-desktop': '/var/lib/jenkins/debian-live-7.7.0-amd64-gnome-desktop.iso',
          'debian-edu_jessie_standalone': '/srv/live-build/results/debian-edu_jessie_standalone_live_amd64.iso',
          'debian-edu_jessie_workstation': '/srv/live-build/results/debian-edu_jessie_workstation_live_amd64.iso',
          'debian_jessie_gnome': '/srv/live-build/results/debian_jessie_gnome_live_amd64.iso',
          'debian_jessie_xfce': '/srv/live-build/results/debian_jessie_xfce_live_amd64.iso',
          'debian_sid_xfce': '/srv/live-build/results/debian_sid_xfce_live_amd64.iso'
        }

titles = { 'wheezy_standard': 'Debian Live 7 standard',
           'wheezy_gnome-desktop': 'Debian Live 7 GNOME desktop',
           'debian-edu_jessie_standalone': 'Debian Edu Live 8 Standalone',
           'debian-edu_jessie_workstation': 'Debian Edu Live 8 Workstation',
           'debian_jessie_gnome': 'Debian Live 8 GNOME Desktop',
           'debian_jessie_xfce': 'Debian Live 8 Xfce Desktop',
           'debian_sid_xfce': 'Debian Live Sid Xfce Desktop',
         }

print("""
- defaults:
    name: lvc
    project-type: freestyle
    description: '{my_description}<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/lvc.yaml.py">lvc.yaml.py</a>.'
    properties:
      - sidebar:
          url: https://jenkins.debian.net/userContent/about.html
          text: About jenkins.debian.net
          icon: /userContent/images/debian-swirl-24x24.png
      - sidebar:
          url: https://jenkins.debian.net/view/lvc
          text: Jobs for libvirt and cucumber based tests
          icon: /userContent/images/debian-jenkins-24x24.png
      - sidebar:
          url: http://www.profitbricks.co.uk
          text: Sponsored by Profitbricks
          icon: /userContent/images/profitbricks-24x24.png
      - throttle:
          max-total: 1
          max-per-node: 1
          enabled: true
          option: category
          categories:
            - lvc
    logrotate:
      daysToKeep: 90
      numToKeep: 20
      artifactDaysToKeep: -1
      artifactNumToKeep: -1
    publishers:
      - email:
          recipients: 'qa-jenkins-scm@lists.alioth.debian.org'
      - archive:
          artifacts: '*.webm, {my_pngs}'
          latest_only: false
      - imagegallery:
          title: '{my_title}'
          includes: '{my_pngs}'
          image-width: 300
    wrappers:
      - live-screenshot
    builders:
      - shell: 'rm $WORKSPACE/*.png -f >/dev/null; /srv/jenkins/bin/lvc/run_test_suite {my_params}'
    triggers:
      - timed: '{my_time}'
""")

for image in sorted(images):
    for feature in sorted(features):
        print("""- job-template:
    defaults: lvc
    name: '{name}_debian-live_%(image)s_%(feature)s'
""" % dict(image=image,
           feature=feature))

print("""
- project:
    name: lvc
    jobs:""")
for image in sorted(images):
    for feature in sorted(features):
        print("""        - '{name}_debian-live_%(image)s_%(feature)s':
           my_title: '%(title)s'
           my_time: '23 45 31 12 *'
           my_params: '--debug --capture lvc_debian-live_%(image)s_%(feature)s.webm --temp-dir $WORKSPACE --iso %(iso)s DebianLive/%(feature)s.feature'
           my_pngs: '%(feature)s-*.png'
           my_description: 'Work in progress...'
""" % dict(image=image,
           feature=feature,
           iso=files[image],
           title=titles[image]))

