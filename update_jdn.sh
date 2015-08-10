#!/bin/bash

# Copyright 2012-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

BASEDIR=$HOME/jenkins.debian.net
PVNAME=/dev/vdb      # LVM physical volume for jobs
VGNAME=jenkins01     # LVM volume group
STAMP=/var/log/jenkins/update-jenkins.stamp
TMPFILE=$(mktemp)

explain() {
	echo "$HOSTNAME: $1"
}

echo "--------------------------------------------"
explain "$(date) - begin deployment update."
#
# set up users and groups
#
if ! getent passwd jenkins > /dev/null ; then
	sudo addgroup --system jenkins
	sudo adduser --system --shell /bin/bash --home /var/lib/jenkins --ingroup jenkins --disabled-login jenkins
fi
if ! getent group jenkins-adm > /dev/null ; then
	sudo addgroup --system jenkins-adm
fi
if ! getent passwd jenkins-adm > /dev/null  ; then
	sudo adduser --system --shell /bin/bash --no-create-home --ingroup jenkins-adm --disabled-login --no-create-home jenkins-adm
	sudo usermod -G jenkins jenkins-adm
fi
for user in helmut holger mattia ; do
	if ! getent passwd $user > /dev/null ; then
		sudo adduser --gecos "" --disabled-password $user
		if [ "$user" = "holger" ] ; then
			sudo usermod -G jenkins,jenkins-adm,sudo,adm $user
		else
			sudo usermod -G jenkins,jenkins-adm $user
		fi
	fi
done

sudo mkdir -p /srv/workspace
[ -d /srv/workspace/pbuilder ] || sudo mkdir -p /srv/workspace/pbuilder
[ -d /srv/schroots ] || sudo mkdir -p /srv/schroots
[ -h /chroots ] || sudo ln -s /srv/workspace/chroots /chroots
[ -h /schroots ] || sudo ln -s /srv/schroots /schroots

if [ "$HOSTNAME" = "jenkins" ] ; then
	if ! grep -q '^tmpfs\s\+/srv/workspace\s' /etc/fstab; then
		echo "tmpfs		/srv/workspace	tmpfs	defaults,size=100g	0	0" >> /etc/fstab
	fi

	if ! mountpoint -q /srv/workspace; then
		if test -z "$(ls -A /srv/workspace)"; then
			mount /srv/workspace
		else
			explain "mountpoint /srv/workspace is non-empty."
		fi
	fi
fi

# make sure needed directories exists - some directories will not be needed on all hosts...
for directory in /schroots /srv/reproducible-results /srv/d-i /srv/live-build /var/log/jenkins/ /srv/jenkins /srv/jenkins/pseudo-hosts /srv/workspace/chroots ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins.jenkins $directory
	fi
done
for directory in /srv/jenkins ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins-adm.jenkins-adm $directory
	fi
done

if ! test -h /chroots; then
	sudo rmdir /chroots || sudo rm -f /chroots # do not recurse
	if test -e /chroots; then
		explain "/chroots could not be cleared."
	else
		sudo ln -s /srv/workspace/chroots /chroots
	fi
fi

# only on Debian systems
if [ -f /etc/debian_version ] ; then
	if [ ! -h /var/cache/pbuilder/build ] ; then
		sudo rmdir /var/cache/pbuilder/build || sudo rm -f /var/cache/pbuilder/build
		if [ -e /var/cache/pbuilder/build ] ; then
			explain "/var/cache/pbuilder/build could not be cleared."
		else
			sudo ln -s /srv/workspace/pbuilder /var/cache/pbuilder/build
		fi
	fi

	#
	# install packages we need
	#
	if [ ./$0 -nt $STAMP ] || [ ! -f $STAMP ] ; then
		DEBS=" 
			bash-completion 
			bc 
			curl 
			debootstrap 
			devscripts 
			etckeeper
			git
			haveged
			less
			munin-node
			munin-plugins-extra 
			pigz 
			python3-psycopg2 
			schroot 
			screen 
			subversion 
			subversion-tools 
			sudo 
			unzip 
			vim 
			"
		case $HOSTNAME in
			jenkins|profitbricks-build?-amd64) DEBS="$DEBS squid3" ;;
			*) ;;
		esac
		if [ "$HOSTNAME" = "jenkins" ] ; then
			MASTERDEBS=" 
				apache2 
				apt-file 
				apt-listchanges 
				binfmt-support 
				bison 
				build-essential 
				calamaris 
				cmake 
				cron-apt 
				csvtool 
				cucumber 
				dnsmasq-base 
				dose-extra 
				dstat 
				figlet 
				flex 
				gawk 
				ghc 
				gocr 
				graphviz 
				iasl 
				imagemagick 
				ip2host 
				libapache2-mod-macro 
				libav-tools 
				libcap2-bin 
				libfile-touch-perl 
				libguestfs-tools 
				libjson-rpc-perl 
				libsikuli-script-java 
				libsoap-lite-perl 
				libvirt0 
				libvirt-bin 
				libvirt-dev 
				libvpx1 
				libxslt1-dev 
				linux-image-amd64 
				mock 
				molly-guard 
				moreutils 
				mr 
				mtr-tiny 
				munin 
				ntp 
				openbios-ppc 
				openbios-sparc 
				openjdk-7-jre 
				ovmf
				pandoc
				postgresql-client-9.4 
				poxml 
				procmail 
				python3-debian 
				python3-yaml 
				python-arpy 
				python-hachoir-metadata 
				python-imaging 
				python-lzma 
				python-pip 
				python-rpy2 
				python-setuptools 
				python-twisted 
				python-yaml 
				qemu 
				qemu-kvm 
				qemu-system-x86 
				qemu-user-static 
				radvd 
				ruby-json 
				ruby-libvirt 
				ruby-packetfu 
				ruby-rjb 
				ruby-rspec 
				seabios 
				shorewall 
				shorewall6 
				sqlite3 
				syslinux 
				tcpdump 
				unclutter 
				virt-viewer 
				vncsnapshot 
				vnstat 
				x11-apps 
				x11vnc 
				xtightvncviewer 
				xvfb 
				zutils 
				sysvinit-core"
		else
			MASTERDEBS=""
		fi
		sudo apt-get update
		sudo apt-get install $DEBS $MASTERDEBS
		sudo apt-get install -t jessie-backports \
				pbuilder
		#		botch
		explain "packages installed."
	else
		explain "no new packages to be installed."
	fi
fi

#
# deploy package configuration in /etc
#
cd $BASEDIR
sudo cp --preserve=mode,timestamps -r hosts/$HOSTNAME/etc/* /etc

#
# more configuration than a simple cp can do
#
sudo chown root.root /etc/sudoers.d/jenkins ; sudo chmod 700 /etc/sudoers.d/jenkins
sudo chown root.root /etc/sudoers.d/jenkins-adm ; sudo chmod 700 /etc/sudoers.d/jenkins-adm

if [ "$HOSTNAME" = "jenkins" ] ; then
	if [ $BASEDIR/hosts/$HOSTNAME/etc/apache2 -nt $STAMP ] || [ ! -f $STAMP ] ; then
		if [ ! -e /etc/apache2/mods-enabled/proxy.load ] ; then
			sudo a2enmod proxy
			sudo a2enmod proxy_http
			sudo a2enmod rewrite
			sudo a2enmod ssl
			sudo a2enmod headers
			sudo a2enmod macro
			sudo a2enmod filter
		fi
		sudo a2ensite -q jenkins.debian.net
		sudo a2enconf -q munin
		sudo chown jenkins-adm.jenkins-adm /etc/apache2/sites-enabled/jenkins.conf
		# for reproducible.d.n url rewriting:
		[ -L /var/www/userContent ] || sudo ln -sf /var/lib/jenkins/userContent /var/www/userContent
		sudo service apache2 reload
	fi
fi

if [ $BASEDIR/hosts/$HOSTNAME/etc/munin -nt $STAMP ] || [ ! -f $STAMP ] ; then
	cd /etc/munin/plugins ; sudo rm -f postfix_* open_inodes df_inode interrupts irqstats threads proc_pri vmstat if_err_eth0 fw_forwarded_local fw_packets forks open_files users 2>/dev/null
	if [ "$HOSTNAME" = "jenkins" ] && [ ! -L /etc/munin/plugins/apache_accesses ] ; then
		for i in apache_accesses apache_volume ; do sudo ln -s /usr/share/munin/plugins/$i $i ; done
	fi
	sudo service munin-node force-reload
fi
explain "packages configured."

#
# install the heart of jenkins.debian.net
#
cd $BASEDIR
for dir in bin logparse job-cfg features live ; do
	sudo cp --preserve=mode,timestamps -r $dir /srv/jenkins/
	sudo chown -R jenkins-adm.jenkins-adm /srv/jenkins/$dir
done
sudo mkdir -p /var/lib/jenkins/.ssh
if [ "$HOSTNAME" = "jenkins" ] ; then
	sudo cp jenkins-home/procmailrc /var/lib/jenkins/.procmailrc
	sudo cp jenkins-home/authorized_keys /var/lib/jenkins/.ssh/authorized_keys
else
	sudo cp jenkins-nodes-home/authorized_keys /var/lib/jenkins/.ssh/authorized_keys
fi
sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh
sudo chmod 600 /var/lib/jenkins/.ssh/authorized_keys
explain "scripts and configurations for jenkins updated."

if [ "$HOSTNAME" = "jenkins" ] ; then
	sudo cp -pr README INSTALL TODO CONTRIBUTING d-i-preseed-cfgs /var/lib/jenkins/userContent/
	git log | grep ^Author| cut -d " " -f2-|sort -u > $TMPFILE
	echo "----" >> $TMPFILE
	sudo cat THANKS.head > /var/lib/jenkins/userContent/THANKS
	# samuel, lunar and josch committed with several commiters, only display one
	grep -v "samuel.thibault@ens-lyon.org" $TMPFILE | grep -v Lunar | sudo grep -v "j.schauer@email.de" >> /var/lib/jenkins/userContent/THANKS
	rm $TMPFILE
	sudo cp -pr userContent /var/lib/jenkins/
	cd /var/lib/jenkins/userContent/
	ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
	[ about.html -nt README ] || asciidoc $ASCIIDOC_PARAMS -o about.html README
	[ todo.html -nt TODO ] || asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
	[ setup.html -nt INSTALL ] || asciidoc $ASCIIDOC_PARAMS -o setup.html INSTALL
	[ contributing.html -nt CONTRIBUTING ] || asciidoc $ASCIIDOC_PARAMS -o contributing.html CONTRIBUTING
	diff THANKS .THANKS >/dev/null || asciidoc $ASCIIDOC_PARAMS -o thanks.html THANKS
	mv THANKS .THANKS
	rm TODO README INSTALL CONTRIBUTING
	sudo chown -R jenkins.jenkins /var/lib/jenkins/userContent
	explain "user content for jenkins updated."

	#
	# run jenkins-job-builder to update jobs if needed
	#     (using sudo because /etc/jenkins_jobs is root:root 700)
	#
	cd /srv/jenkins/job-cfg
	for metaconfig in *.yaml.py ; do
	# there are both python2 and python3 scripts here
		./$metaconfig > $TMPFILE
		if ! $(diff ${metaconfig%.py} $TMPFILE > /dev/null) ; then
			cp $TMPFILE ${metaconfig%.py}
		fi
	done
	rm -f $TMPFILE
	for config in *.yaml ; do
		if [ $config -nt $STAMP ] || [ ! -f $STAMP ] ; then
			sudo jenkins-jobs update $config
		else
			echo "$config has not changed, nothing to do."
		fi
	done
	explain "jenkins jobs updated."
fi

#
# configure git for jenkins
#
if [ "$(sudo su - jenkins -c 'git config --get user.email')" != "jenkins@jenkins.debian.net" ] ; then
	sudo su - jenkins -c "git config --global user.email jenkins@jenkins.debian.net"
	sudo su - jenkins -c "git config --global user.name Jenkins"
fi

if [ -f /etc/debian_version ] ; then
	#
	# configure pbuilder for jenkins user
	#
	sudo chown jenkins /var/cache/pbuilder/result
fi

if [ "$HOSTNAME" = "jenkins" ] ; then
	#
	# creating LVM volume group for jobs
	#
	if [ "$PVNAME" = "" ]; then
	    figlet -f banner Error
	    explain "you must set \$PVNAME to physical volume pathname, exiting."
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
	# generate the kgb-client configurations
	#
	cd $BASEDIR
	KGB_SECRETS="/srv/jenkins/kgb/secrets.yml"
	if [ -f "$KGB_SECRETS" ] && [ $(stat -c "%a:%U:%G" "$KGB_SECRETS") = "640:jenkins-adm:jenkins-adm" ] ; then
	    # the last condition is to assure the files are owned by the right user/team
	    if [ "$KGB_SECRETS" -nt $STAMP ] || [ ! -f $STAMP ] ; then
	        sudo -u jenkins-adm "./deploy_kgb.py"
	    else
	        explain "kgb-client configuration unchanged, nothing to do."
	    fi
	else
	    figlet -f banner Warning
	    echo "Warning: $KGB_SECRETS either does not exist or has bad permissions. Please fix. KGB configs not generated"
	    echo "We expect the secrets file to be mode 640 and owned by jenkins-adm:jenkins-adm."
	fi
fi

#
# There's always some work left...
#	echo FIXME is ignored so check-jobs scripts can output templates requiring manual work
#
rgrep FIXME $BASEDIR/* | grep -v "rgrep FIXME" | grep -v echo > $TMPFILE
if [ -s $TMPFILE ] ; then
	echo
	cat $TMPFILE
	echo
fi
rm -f $TMPFILE

#
# finally
#
sudo touch $STAMP	# so on the next run, only configs newer than this file will be updated
explain "$(date) - finished deployment."

