#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

BASEDIR=/root/jenkins.debian.net

explain() {
	echo
	echo $1
	echo
}

# make sure needed directories exists
for directory in  /srv/jenkins /chroots ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins.jenkins $directory
	fi
done

#
# install packages we need
# (more or less grouped into more-then-nice-to-have, needed-while-things-are-new, needed)
#
sudo apt-get install vim screen less etckeeper moreutils curl mtr-tiny dstat devscripts bash-completion shorewall shorewall6 cron-apt apt-listchanges munin calamaris visitors procmail libjson-rpc-perl libfile-touch-perl zutils \
	build-essential python-setuptools \
	debootstrap sudo figlet graphviz apache2 python-yaml python-pip mr subversion subversion-tools vnstat webcheck poxml qemu vncsnapshot imagemagick ffmpeg2theora python-twisted python-imaging
explain "Packages installed."

#
# as long as d-i_manual_*_(html|pdf) is build on the host system...
#
sudo apt-get build-dep installation-guide

#
# deploy package configuration in /etc
#
cd $BASEDIR
sudo cp -r etc/* /etc

#
# more configuration than a simple cp can do
#
if [ ! -e /etc/apache2/mods-enabled/proxy.load ] ; then
	sudo a2enmod proxy
	sudo a2enmod proxy_http
	sudo a2enmod rewrite
fi
sudo chown root.root /etc/sudoers.d/jenkins ; sudo chmod 700 /etc/sudoers.d/jenkins
sudo ln -sf /etc/apache2/sites-available/jenkins.debian.net /etc/apache2/sites-enabled/000-default
sudo service apache2 reload
cd /etc/munin/plugins ; sudo rm -f postfix_* open_inodes df_inode interrupts diskstats irqstats threads proc_pri vmstat if_err_eth0 fw_forwarded_local fw_packets forks open_files users 2>/dev/null
[ -L apache_accesses ] || for i in apache_accesses apache_volume ; do ln -s /usr/share/munin/plugins/$i $i ; done
explain "Packages configured."

#
# install the heart of jenkins.debian.net
#
cd $BASEDIR
cp -r bin logparse job-cfg /srv/jenkins/
cp procmailrc /var/lib/jenkins/.procmailrc
explain "Jenkins updated."
cp -r README INSTALL TODO d-i-preseed-cfgs userContent/* /var/lib/jenkins/userContent/
cd /var/lib/jenkins/userContent/
ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
asciidoc $ASCIIDOC_PARAMS -o about.html README
asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
asciidoc $ASCIIDOC_PARAMS -o setup.html INSTALL
rm TODO README INSTALL
explain "Updated about.html, setup.html and todo.html."

#
# run jenkins-job-builder to update jobs if needed
#     (using sudo because /etc/jenkins_jobs is root:root 700)
#
cd /srv/jenkins/job-cfg
for config in *.yaml ; do
	sudo jenkins-jobs update $config
done
explain "Jenkins jobs updated."

#
# crappy tests for checking that jenkins-job-builder works correctly
#
#wc -m counts one byte too many, so we substract one
let DEFINED_MY_TRIGGERS=$(grep my_trigger: *.yaml|wc -l)+$(grep my_trigger: *.yaml|grep , |xargs -r echo | sed 's/[^,]//g'| wc -m)-1
DEFINED_DI_TRIGGERS=$(grep "defaults: d-i-manual-html" d-i.yaml|wc -l)
let DEFINED_TRIGGERS=DEFINED_MY_TRIGGERS+DEFINED_DI_TRIGGERS
let CONFIGURED_TRIGGERS=$(grep \<childProjects /var/lib/jenkins/jobs/*/config.xml|wc -l)+$(grep  \<childProjects /var/lib/jenkins/jobs/*/config.xml |grep , |xargs -r echo | sed 's/[^,]//g'| wc -m)-1
if [ "$DEFINED_TRIGGERS" != "$CONFIGURED_TRIGGERS" ] ; then
	figlet Warning
	explain "Number of defined triggers ($DEFINED_TRIGGERS) differs from currently configured triggers ($CONFIGURED_TRIGGERS), please investigate."
fi

#
# FIXME: this should also only be run once
#
sudo su - jenkins -c "git config --global user.email jenkins@jenkins.debian.net"
sudo su - jenkins -c "git config --global user.name Jenkins"

#
# FIXME: file a bug against pbuilder
#	else you have http://jenkins.debian.net/view/debian-installer/job/d-i_build_partman-ext3/4/console
#	with this you have: http://jenkins.debian.net/view/debian-installer/job/d-i_build_partman-ext3/5/console
#	and this asks for a password: pdebuild --use-pdebuild-internal --pbuilder '/sbin/sudo /usr/sbin/pbuilder'
#	despites the jenkins user cam run "sudo pbuilder" without it just fine...??!
#
sudo chown jenkins /var/cache/pbuilder/result

#
# There's always some work left...
#	echo FIXME is ignored so check-jobs scripts can output templates requiring manual work
#
echo
rgrep FIXME $BASEDIR/* | grep -v "rgrep FIXME" | grep -v echo

