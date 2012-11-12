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
sudo apt-get install vim screen less etckeeper moreutils curl mtr-tiny dstat devscripts bash-completion shorewall shorewall6 cron-apt apt-listchanges munin \
	build-essential python-setuptools \
	debootstrap sudo figlet graphviz apache2 python-yaml python-pip mr subversion subversion-tools vnstat webcheck
explain "Packages installed."

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
explain "Jenkins updated."
cp -r TODO README userContent/* /var/lib/jenkins/userContent/
cd /var/lib/jenkins/userContent/
ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
asciidoc $ASCIIDOC_PARAMS -o about.html README
asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
rm TODO README
explain "Updated about.html and todo.html"

#
# run jenkins-job-builder to update jobs if needed
#     (using sudo because /etc/jenkins_jobs is root:root 700)
#
cd /srv/jenkins/job-cfg 
sudo jenkins-jobs update .
explain "Jenkins jobs updated."

#
# crappy tests for checking that jenkins-job-builder works correctly
#
DEFINED_TRIGGERS=$(grep _trigger: *.yaml|wc -l)
CONFIGURED_TRIGGERS=$(grep -C 1 \<hudson.tasks.BuildTrigger /var/lib/jenkins/jobs/*/config.xml|grep child|wc -l)
if [ "$DEFINED_TRIGGERS" != "$CONFIGURED_TRIGGERS" ] ; then
	figlet Warning
	explain "Number of defined triggers ($DEFINED_TRIGGERS) differs from configured triggers ($CONFIGURED_TRIGGERS), please investigate."
fi

