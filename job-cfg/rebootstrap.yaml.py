#!/usr/bin/python

architectures = """
   kfreebsd-amd64
   i386 kfreebsd-i386
   mips mips64el mipsel
   powerpc ppc64
   s390x
   sparc sparc64
   x32
   """.split()

mono_architectures = """
    armel armhf kfreebsd-armhf arm64 arm64ilp32 hurd-amd64
    musl-linux-armhf musl-linux-arm64
    alpha
    hppa
    hurd-i386 musl-linux-i386
    m68k
    mips64r6el mips32r6el
    musl-linux-mips musl-linux-mipsel
    nios2
    powerpcel powerpcspe ppc64el
    sh4
    tilegx
    """.split()

release_architectures = """
    armel armhf arm64
    i386
    mips mipsel
    powerpc ppc64el
    s390x
    """.split()

architectures += mono_architectures

gcc_versions = ("5", "6")
diffoscope_gcc_versions = ("5",)

print("""
- defaults:
    name: rebootstrap
    project-type: freestyle
    properties:
      - sidebar:
          url: https://jenkins.debian.net/userContent/about.html
          text: About jenkins.debian.net
          icon: /userContent/images/debian-swirl-24x24.png
      - sidebar:
          url: https://jenkins.debian.net/view/rebootstrap/
          text: All rebootstrap jobs
          icon: /userContent/images/debian-jenkins-24x24.png
      - sidebar:
          url: http://www.profitbricks.co.uk
          text: Sponsored by Profitbricks
          icon: /userContent/images/profitbricks-24x24.png
      - priority-sorter:
          priority: '150'
      - throttle:
          max-total: 5
          max-per-node: 5
          enabled: true
          option: category
          categories:
            - rebootstrap
    description: '{my_description}{do_not_edit}'
    logrotate:
      daysToKeep: 90
      numToKeep: 10
      artifactDaysToKeep: -1
      artifactNumToKeep: -1
    scm:
      - git:
          url: 'git://anonscm.debian.org/users/helmutg/rebootstrap.git'
          branches:
            - '{my_branchname}'
    builders:
      - shell: '{my_wrapper} {my_branchname} HOST_ARCH={my_arch} {my_params}'
    publishers:
      - logparser:
          parse-rules: '/srv/jenkins/logparse/rebootstrap.rules'
          unstable-on-warning: 'false'
          fail-on-error: 'false'
      - email:
          recipients: 'jenkins+debian-bootstrap helmutg@debian.org'
    triggers:
      - pollscm:
          cron: '*/6 * * * *'
    node: '{my_node}'
""")

for arch in sorted(architectures):
    for gccver in sorted(gcc_versions):
        for nobiarch in ["", "_nobiarch"]:
            if nobiarch and arch in mono_architectures:
                continue
            for supported in ["", "_supported"]:
                if (nobiarch or arch.startswith("musl-linux-") or arch.startswith("hurd-") or arch.startswith("kfreebsd-")) and supported:
                    continue
                for diffoscope in ["", "_diffoscope"]:
                    if diffoscope and (arch not in release_architectures or gccver not in diffoscope_gcc_versions):
                        continue
                    print("""
- job-template:
    defaults: rebootstrap
    name: '{name}_%(arch)s_gcc%(gccshortver)s%(nobiarch)s%(supported)s%(diffoscope)s'""" %
    dict(arch=arch, gccshortver=gccver.replace(".", ""), nobiarch=nobiarch, supported=supported, diffoscope=diffoscope))

print("""
- project:
    name: rebootstrap
    do_not_edit: '<br><br>Job configuration source is <a href="https://anonscm.debian.org/git/qa/jenkins.debian.net.git/tree/job-cfg/rebootstrap.yaml.py">rebootstrap.yaml.py</a>.'
    jobs:""")
for arch in sorted(architectures):
    for gccver in sorted(gcc_versions):
        for nobiarch in (False, True):
            if nobiarch and arch in mono_architectures:
                continue
            for supported in (False, True):
                if (nobiarch or arch.startswith("musl-linux-") or arch.startswith("hurd-") or arch.startswith("kfreebsd-")) and supported:
                    continue
                for diffoscope in (False, True):
                    if diffoscope and (arch not in release_architectures or gccver not in diffoscope_gcc_versions):
                        continue
                    print(
"""        - '{name}_%(suffix)s':
            my_arch: '%(arch)s'
            my_params: 'GCC_VER=%(gccver)s ENABLE_MULTILIB=%(multilib_value)s ENABLE_MULTIARCH_GCC=%(multiarch_gcc_value)s ENABLE_DIFFOSCOPE=%(diffoscope_value)s'
            my_description: 'Verify bootstrappability of Debian using gcc-%(gccver)s%(nobiarch_comment)s for %(arch)s%(supported_comment)s%(diffoscope_comment)s'
            my_branchname: 'jenkins_%(suffix)s'
            my_node: '%(node)s'
            my_wrapper: '/srv/jenkins/bin/jenkins_master_wrapper.sh'""" %
                dict(arch=arch,
                     suffix=arch + "_gcc" + gccver.replace(".", "") + ("_nobiarch" if nobiarch else "") + ("_supported" if supported else "") + ("_diffoscope" if diffoscope else ""),
                     gccver=gccver,
                     multilib_value="no" if nobiarch else "yes",
                     nobiarch_comment=" without multilib" if nobiarch else "",
                     multiarch_gcc_value="no" if supported else "yes",
                     supported_comment=" using the supported method" if supported else "",
                     diffoscope_value="yes" if diffoscope else "no",
                     diffoscope_comment=" showing diffoscopes" if diffoscope else "",
                     node="profitbricks9"))

