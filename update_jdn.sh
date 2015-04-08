#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

BASEDIR=/root/jenkins.debian.net
PVNAME=/dev/vdb      # LVM physical volume for jobs
VGNAME=jenkins01     # LVM volume group

explain() {
	echo
	echo $1
	echo
}

#
# set up users and groups
#
if ! getent group jenkins-adm ; then
	sudo addgroup --system jenkins-adm
fi
if ! getent passwd jenkins-adm ; then
	sudo adduser --system --no-create-home --ingroup jenkins-adm --disable-login --no-create-home jenkins-adm
	sudo usermod -G jenkins
fi
for user in helmut holger mattia ; do
	if ! getent passwd $user ; then
		sudo adduser --gecos "" $user
		sudo usermod -G jenkins,jenkins-adm
	fi
done

mkdir -p /srv/workspace

if ! grep -q '^tmpfs\s\+/srv/workspace\s' /etc/fstab; then
	echo "tmpfs		/srv/workspace	tmpfs	defaults,size=60g	0	0" >> /etc/fstab
fi

if ! mountpoint -q /srv/workspace; then
	if test -z "$(ls -A /srv/workspace)"; then
		mount /srv/workspace
	else
		echo "mountpoint /srv/workspace is non-empty"
	fi
fi

# make sure needed directories exists
for directory in  /srv/jenkins /schroots /srv/reproducible-results /srv/d-i /srv/live-build ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins.jenkins $directory
	fi
done

if ! test -h /chroots; then
	rmdir /chroots || rm -f /chroots # do not recurse
	if test -e /chroots; then
		echo could not clear /chroots
	else
		ln -s /srv/workspace/chroots /chroots
	fi
fi

if ! test -h /var/cache/pbuilder/build; then
	rmdir /var/cache/pbuilder/build || rm -f /var/cache/pbuilder/build
	if test -e /var/cache/pbuilder/build; then
		echo could not clear /var/cache/pbuilder/build
	else
		ln -s /srv/workspace/pbuilder /var/cache/pbuilder/build
	fi
fi

#
# install packages we need
#
sudo apt-get install	apache2 \
			apt-file \
			apt-listchanges \
			bash-completion \
			bc \
			build-essential \
			calamaris \
			cron-apt \
			curl \
			debootstrap \
			devscripts \
			devscripts \
			dnsmasq-base \
			dose-extra \
			dstat \
			etckeeper \
			ffmpeg \
			figlet \
			gawk \
			ghc \
			gocr \
			graphviz \
			guestmount \
			haveged \
			imagemagick \
			ip2host \
			less \
			libapache2-mod-macro \
			libav-tools \
			libavcodec-extra-53 \
			libcap2-bin \
			libfile-touch-perl \
			libjson-rpc-perl \
			libsikuli-script-java \
			libsoap-lite-perl \
			libvirt-ruby \
			libvpx1 \
			libxslt1-dev \
			molly-guard \
			moreutils \
			mr \
			mtr-tiny \
			ntp \
			openjdk-7-jre \
			pigz \
			postgresql-client-9.1 \
			poxml \
			procmail \
			python-hachoir-metadata \
			python-imaging \
			python-lzma \
			python-pip \
			python-rpy2 \
			python-setuptools \
			python-twisted \
			python-yaml \
			python3-psycopg2 \
			python3-yaml \
			radvd \
			ruby-json \
			ruby-rspec \
			schroot \
			screen \
			shorewall \
			shorewall6 \
			sqlite3 \
			subversion \
			subversion-tools \
			sudo \
			syslinux \
			tcpdump \
			unclutter \
			unzip \
			vim \
			virt-viewer \
			vncsnapshot \
			vnstat \
			x11-apps \
			x11vnc \
			xtightvncviewer \
			xvfb \
			zutils

sudo apt-get install -t wheezy-backports \
			binfmt-support \
			cucumber \
			debootstrap \
			libvirt-bin \
			libvirt-dev \
			libvirt0 \
			linux-image-amd64 \
			munin \
			munin-plugins-extra \
			python3-debian \
			qemu \
			qemu-kvm \
			qemu-system-x86 \
			qemu-user-static \
			ruby-packetfu \
			ruby-rjb \
			seabios \
			openbios-ppc \
			openbios-sparc

explain "Packages installed."

echo "Also needs python-arpy from jessie..."
echo "Also needs ovmf from jessie..."

#
# deploy package configuration in /etc
#
cd $BASEDIR
sudo cp --preserve=mode,timestamps -r etc/* /etc

#
# more configuration than a simple cp can do
#
if [ ! -e /etc/apache2/mods-enabled/proxy.load ] ; then
	sudo a2enmod proxy
	sudo a2enmod proxy_http
	sudo a2enmod rewrite
	sudo a2enmod ssl
	sudo a2enmod headers
	sudo a2enmod macro
fi
sudo chown root.root /etc/sudoers.d/jenkins ; sudo chmod 700 /etc/sudoers.d/jenkins
sudo chown root.root /etc/sudoers.d/jenkins-adm ; sudo chmod 700 /etc/sudoers.d/jenkins-adm
sudo ln -sf /etc/apache2/sites-available/jenkins.debian.net /etc/apache2/sites-enabled/000-default
sudo chown jenkins-adm.jenkins-adm /etc/apache2/sites-enabled/000-default
# for reproducible.d.n url rewriting:
sudo ln -sf /var/lib/jenkins/userContent /var/www/userContent
sudo service apache2 reload
cd /etc/munin/plugins ; sudo rm -f postfix_* open_inodes df_inode interrupts irqstats threads proc_pri vmstat if_err_eth0 fw_forwarded_local fw_packets forks open_files users 2>/dev/null
[ -L apache_accesses ] || for i in apache_accesses apache_volume ; do ln -s /usr/share/munin/plugins/$i $i ; done
explain "Packages configured."
sudo service munin-node force-reload

#
# install the heart of jenkins.debian.net
#
cd $BASEDIR
for dir in bin logparse job-cfg features live ; do
	cp --preserve=mode,timestamps -r $dir /srv/jenkins/
	chmod -R jenkins-adm.jenkins-adm /srv/jenkins/$dir
done
cp procmailrc /var/lib/jenkins/.procmailrc
explain "Jenkins updated."
cp -pr README INSTALL TODO CONTRIBUTING d-i-preseed-cfgs /var/lib/jenkins/userContent/
TMPFILE=$(mktemp)
git log | grep ^Author| cut -d " " -f2-|sort -u > $TMPFILE
echo "----" >> $TMPFILE
cat THANKS.head $TMPFILE > /var/lib/jenkins/userContent/THANKS
rm $TMPFILE
cp -pr userContent /var/lib/jenkins/
cd /var/lib/jenkins/userContent/
ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
[ about.html -nt README ] || asciidoc $ASCIIDOC_PARAMS -o about.html README
[ todo.html -nt TODO ] || asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
[ setup.html -nt INSTALL ] || asciidoc $ASCIIDOC_PARAMS -o setup.html INSTALL
[ contributing.html -nt CONTRIBUTING ] || asciidoc $ASCIIDOC_PARAMS -o contributing.html CONTRIBUTING
diff THANKS .THANKS >/dev/null || asciidoc $ASCIIDOC_PARAMS -o thanks.html THANKS
mv THANKS .THANKS
rm TODO README INSTALL CONTRIBUTING
chown -R jenkins.jenkins /var/lib/jenkins/userContent
explain "Updated user content for Jenkins."

#
# run jenkins-job-builder to update jobs if needed
#     (using sudo because /etc/jenkins_jobs is root:root 700)
#
cd /srv/jenkins/job-cfg
for metaconfig in *.yaml.py ; do
	python $metaconfig > ${metaconfig%.py}
done
for config in *.yaml ; do
	sudo jenkins-jobs update $config
done
explain "Jenkins jobs updated."

#
# crappy tests for checking that jenkins-job-builder works correctly
#
#wc -m counts one byte too many, so we substract one
let DEFINED_MY_TRIGGERS=$(grep -v \# *.yaml | grep my_trigger: | grep -v "my_trigger: ''"|wc -l)+$(grep my_trigger: *.yaml|grep , |xargs -r echo | sed 's/[^,]//g'| wc -m)-1
let DEFINED_DI_TRIGGERS=$(grep "defaults: d-i-manual-html" d-i.yaml|wc -l)
#DEFINED_REPRODUCIBLE_TRIGGERS=$(grep "^    defaults: reproducible$" reproducible.yaml|wc -l)
let DEFINED_TRIGGERS=DEFINED_MY_TRIGGERS+DEFINED_DI_TRIGGERS
#let DEFINED_TRIGGERS=DEFINED_TRIGGERS+DEFINED_REPRODUCIBLE_TRIGGERS
let CONFIGURED_TRIGGERS=$(grep \</childProjects /var/lib/jenkins/jobs/*/config.xml|wc -l)+$(grep  \<childProjects /var/lib/jenkins/jobs/*/config.xml |grep , |xargs -r echo | sed 's/[^,]//g'| wc -m)-1
if [ "$DEFINED_TRIGGERS" != "$CONFIGURED_TRIGGERS" ] ; then
	figlet -f banner Warning
	explain "Number of defined triggers ($DEFINED_TRIGGERS) differs from currently configured triggers ($CONFIGURED_TRIGGERS), please investigate."
fi

#
# configure git for jenkins
#
if [ "$(sudo su - jenkins -c 'git config --get user.email')" != "jenkins@jenkins.debian.net" ] ; then
	sudo su - jenkins -c "git config --global user.email jenkins@jenkins.debian.net"
	sudo su - jenkins -c "git config --global user.name Jenkins"
fi

#
# configure pbuilder for jenkins user
#
sudo chown jenkins /var/cache/pbuilder/result

#
# creating LVM volume group for jobs
#
if [ "$PVNAME" = "" ]; then
    figlet -f banner Error
    explain "Set \$PVNAME to physical volume pathname."
    exit 1
else
    if ! sudo pvs $PVNAME >/dev/null 2>&1; then
        sudo pvcreate $PVNAME
    fi
    if ! sudo vgs $VGNAME >/dev/null 2>&1; then
        sudo vgcreate $VGNAME $PVNAME
    fi
fi

#
# There's always some work left...
#	echo FIXME is ignored so check-jobs scripts can output templates requiring manual work
#
echo
rgrep FIXME $BASEDIR/* | grep -v "rgrep FIXME" | grep -v echo

