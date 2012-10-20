#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# make sure needed directories exists
for directory in  /srv/jenkins /chroots ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins.jenkins $directory
	fi
done

#
# install the heart of jenkins.debian.net
#
cp -r bin logparse /srv/jenkins/
cp -r userContent/* /var/lib/jenkins/userContent/
asciidoc -a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -a imagesdir=./  -b html5 -a toc -a toclevels=4 -a icons -o about.html TODO && cp about.html /var/lib/jenkins/userContent/

#
# install packages we need
# (more or less grouped into more-then-nice-to-have, needed-while-things-are-new, needed)
#
sudo apt-get install vim screen less etckeeper mtr-tiny dstat devscripts bash-completion \
	build-essential python-setuptools \
	debootstrap sudo figlet graphviz apache2 python-yaml 

#
# deploy package configuration in /etc
#
sudo cp -r etc/* /

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

