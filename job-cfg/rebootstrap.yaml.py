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
    armel armhf kfreebsd-armhf musl-linux-armhf arm64 hurd-amd64 musl-linux-arm64
    alpha
    hppa
    hurd-i386 musl-linux-i386
    m68k
    musl-linux-mips musl-linux-mipsel
    powerpcel powerpcspe ppc64el
    or1k
    sh4
    """.split()

release_architectures = """
    armel armhf arm64
    i386
    mips mipsel
    powerpc ppc64el
    s390x
    """.split()

architectures += mono_architectures

gcc_versions = ("5",)
debbindiff_gcc_versions = ("5",)

def get_node(arch):
    if arch == "or1k":
        return "profitbricks4"
    return ""

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
      - priority:
          job-prio: '150'
      - throttle:
          max-total: 4
          max-per-node: 4
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
      - shell: '{my_wrapper} LC_ALL=C /srv/jenkins/bin/chroot-run.sh sid minimal ./bootstrap.sh HOST_ARCH={my_arch} {my_params}'
    publishers:
      - logparser:
          parse-rules: '/srv/jenkins/logparse/rebootstrap.rules'
          unstable-on-warning: 'false'
          fail-on-error: 'false'
      - email:
          recipients: 'jenkins+debian-bootstrap helmutg@debian.org'
    triggers:
      - pollscm: '*/6 * * * *'
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
                for debbindiff in ["", "_debbindiff"]:
                    if debbindiff and (arch not in release_architectures or gccver not in debbindiff_gcc_versions):
                        continue
                    print("""
- job-template:
    defaults: rebootstrap
    name: '{name}_%(arch)s_gcc%(gccshortver)s%(nobiarch)s%(supported)s%(debbindiff)s'""" %
    dict(arch=arch, gccshortver=gccver.replace(".", ""), nobiarch=nobiarch, supported=supported, debbindiff=debbindiff))

print("""
- project:
    name: rebootstrap
    do_not_edit: '<br><br>Job configuration source is <a href="http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/job-cfg/rebootstrap.yaml.py">rebootstrap.yaml.py</a>.'
    jobs:""")
for arch in sorted(architectures):
    for gccver in sorted(gcc_versions):
        for nobiarch in (False, True):
            if nobiarch and arch in mono_architectures:
                continue
            for supported in (False, True):
                if (nobiarch or arch.startswith("musl-linux-") or arch.startswith("hurd-") or arch.startswith("kfreebsd-")) and supported:
                    continue
                for debbindiff in (False, True):
                    if debbindiff and (arch not in release_architectures or gccver not in debbindiff_gcc_versions):
                        continue
                    print(
"""        - '{name}_%(suffix)s':
            my_arch: '%(arch)s'
            my_params: 'GCC_VER=%(gccver)s ENABLE_MULTILIB=%(multilib_value)s ENABLE_MULTIARCH_GCC=%(multiarch_gcc_value)s ENABLE_DEBBINDIFF=%(debbindiff_value)s'
            my_description: 'Verify bootstrappability of Debian using gcc-%(gccver)s%(nobiarch_comment)s for %(arch)s%(supported_comment)s%(debbindiff_comment)s'
            my_branchname: 'jenkins_%(suffix)s'
            my_node: '%(node)s'""" %
                dict(arch=arch,
                     suffix=arch + "_gcc" + gccver.replace(".", "") + ("_nobiarch" if nobiarch else "") + ("_supported" if supported else "") + ("_debbindiff" if debbindiff else ""),
                     gccver=gccver,
                     multilib_value="no" if nobiarch else "yes",
                     nobiarch_comment=" without multilib" if nobiarch else "",
                     multiarch_gcc_value="no" if supported else "yes",
                     supported_comment=" using the supported method" if supported else "",
                     debbindiff_value="yes" if debbindiff else "no",
                     debbindiff_comment=" showing debbindiffs" if debbindiff else "",
                     node=get_node(arch)))
                    if get_node(arch):
                        print("            my_wrapper: '/srv/jenkins/bin/reproducible_master_wrapper.sh'")
