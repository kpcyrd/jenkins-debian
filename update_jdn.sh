#!/bin/bash
# Copyright 2012-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set -e

BASEDIR="$(dirname "$(readlink -e $0)")"
PVNAME=/dev/vdb      # LVM physical volume for jobs
VGNAME=jenkins01     # LVM volume group
STAMP=/var/log/jenkins/update-jenkins.stamp
TMPFILE=$(mktemp)
# The $@ below means that command line args get passed on to j-j-b
# which allows one to specify --flush-cache or --ignore-cache
JJB="jenkins-job-builder $@"

# so we can later run some commands only if $0 has been updated…
if [ -f $STAMP ] && [ $STAMP -nt $BASEDIR/$0 ] ; then
	UP2DATE=true
else
	UP2DATE=false
fi


explain() {
	echo "$HOSTNAME: $1"
}



echo "--------------------------------------------"
explain "$(date) - begin deployment update."

# some nodes need special treatment…
case $HOSTNAME in
	profitbricks-build4-amd64|profitbricks-build5-amd64|profitbricks-build6-i386)
		# set correct date
		sudo service ntp stop
		sudo ntpdate -b de.pool.ntp.org
		;;
	opi2a)
		# this host is acting strange…
		# restarting services cause hangs, so we don't do that
		echo -e "#!/bin/sh\nexit 0" | sudo tee /usr/sbin/policy-rc.d
		;;
	*)	;;
esac

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
	sudo adduser --system --shell /bin/bash --hone /home/jenkins-adm --ingroup jenkins-adm --disabled-login jenkins-adm
	sudo usermod -G jenkins jenkins-adm
fi
if [ ! -d /home/jenkins-adm ]; then
    sudo mkdir /home/jenkins-adm
    sudo chown jenkins-adm.jenkins-adm /home/jenkins-adm
fi


declare -A user_host_groups u_shell

sudo_groups='jenkins,jenkins-adm,sudo,adm'

# if there's a need for host groups, a case statement on $HOSTNAME here that sets $GROUPNAME, say, should do the trick
# then you can define user_host_groups['phil','lvm_group']=... below
# and add checks for the GROUP version whereever the HOSTNAME is checked in the following code

user_host_groups['helmut','*']="$sudo_groups"
user_host_groups['holger','*']="$sudo_groups"
user_host_groups['holger','jenkins']="reproducible,${user_host_groups['holger','*']}"
user_host_groups['mattia','*']="$sudo_groups"
user_host_groups['mattia','jenkins']="reproducible,${user_host_groups['mattia','*']}"
user_host_groups['phil','jenkins-test-vm']="$sudo_groups,libvirt,libvirt-qemu"
user_host_groups['phil','profitbricks-build10-amd64']="$sudo_groups"
user_host_groups['phil','jenkins']=''
user_host_groups['lunar','jenkins']='reproducible'


u_shell['mattia']='/bin/zsh'
u_shell['jenkins-adm']='/bin/bash'

# get the users out of the user_host_groups array's index
users=$(for i in ${!user_host_groups[@]}; do echo ${i%,*} ; done | sort -u)

$UP2DATE || for user in ${users}; do
	# -v is a bashism to check for set variables, used here to see if this user is active on this host
	[ -v user_host_groups["$user","$HOSTNAME"] -o -v user_host_groups["$user",'*'] ] || continue

	# create the user
	if ! getent passwd $user > /dev/null ; then
		# adduser, defaulting to /bin/bash as shell
		sudo adduser --gecos "" --shell "${u_shell[$user]:-/bin/bash}" --disabled-password $user
	fi
	# add groups: first try the specific host, or if unset fall-back to default '*' setting
	for h in "$HOSTNAME" '*' ; do
		if [ -v user_host_groups["$user","$h"] ] ; then
			sudo usermod -G "${user_host_groups["$user","$h"]}" $user
			break
		fi
	done
	# add the user's keys (if any)
	if ls authorized_keys/${user}@*.pub >/dev/null 2>&1 ; then
		[ -d /var/lib/misc/userkeys ] || sudo mkdir -p /var/lib/misc/userkeys
		cat authorized_keys/${user}@*.pub | sudo tee /var/lib/misc/userkeys/${user} > /dev/null
	fi
done

# change defaults
$UP2DATE || grep -q '^AuthorizedKeysFile' /etc/ssh/sshd_config || {
	sudo sh -c "echo 'AuthorizedKeysFile /var/lib/misc/userkeys/%u %h/.ssh/authorized_keys' >> /etc/ssh/sshd_config"
	sudo service ssh reload
}
# change vagrants manual configuration on some armhf hosts
$UP2DATE || grep -q '/var/lib/misc/userkeys' /etc/ssh/sshd_config || {
	sudo sed -i "s#/var/lib/monkeysphere/authorized_keys/#/var/lib/misc/userkeys/#g" /etc/ssh/sshd_config
	sudo service ssh reload
}

sudo mkdir -p /srv/workspace
[ -d /srv/schroots ] || sudo mkdir -p /srv/schroots
[ -h /chroots ] || sudo ln -s /srv/workspace/chroots /chroots
[ -h /schroots ] || sudo ln -s /srv/schroots /schroots

if [ "$HOSTNAME" = "jenkins-test-vm" ] || [ "$HOSTNAME" = "profitbricks-build10-amd64" ] ; then
	# jenkins needs access to libvirt
	sudo adduser jenkins libvirt
	sudo adduser jenkins libvirt-qemu

	# we need a directory for the VM's storage pools
	VM_POOL_DIR=/srv/lvc/vm-pools
	if [ ! -d $VM_POOL_DIR ] ; then
		sudo mkdir -p $VM_POOL_DIR
		sudo chown jenkins:libvirt-qemu $VM_POOL_DIR
		sudo chmod 775 $VM_POOL_DIR
	fi

	# tidy up after ourselves, for a while at least
	OLD_VM_POOL_DIR=/srv/workspace/vm-pools
	if [ -d "$OLD_VM_POOL_DIR" ] ; then
		sudo rm -r "$OLD_VM_POOL_DIR"
	fi
fi

# prepare tmpfs on some hosts
case $HOSTNAME in
	jenkins)
		TMPFSSIZE=100
		TMPSIZE=15
		;;
	profitbricks-build9-amd64)
		TMPFSSIZE=40
		TMPSIZE=8
		;;
	profitbricks-build*)
		TMPFSSIZE=200
		TMPSIZE=15
		;;
	*) ;;
esac
case $HOSTNAME in
	profitbricks-build*i386)
		if ! grep -q '/srv/workspace' /etc/fstab; then
			echo "Warning: you need to manually create a /srv/workspace partition on i386 nodes, exiting."
			exit 1
		fi
		;;
	jenkins|profitbricks-build*amd64)
		if ! grep -q '^tmpfs\s\+/srv/workspace\s' /etc/fstab; then
			echo "tmpfs		/srv/workspace	tmpfs	defaults,size=${TMPFSSIZE}g	0	0" | sudo tee -a /etc/fstab >/dev/null  
		fi
		if ! grep -q '^tmpfs\s\+/tmp\s' /etc/fstab; then
			echo "tmpfs		/tmp	tmpfs	defaults,size=${TMPSIZE}g	0	0" | sudo tee -a /etc/fstab >/dev/null
		fi
		if ! mountpoint -q /srv/workspace; then
			if test -z "$(ls -A /srv/workspace)"; then
				sudo mount /srv/workspace
			else
				explain "WARNING: mountpoint /srv/workspace is non-empty."
			fi
		fi
		;;
	*) ;;
esac

# make sure needed directories exists - some directories will not be needed on all hosts...
for directory in /schroots /srv/reproducible-results /srv/d-i /srv/udebs /srv/live-build /var/log/jenkins/ /srv/jenkins /srv/jenkins/pseudo-hosts /srv/workspace/chroots ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
	fi
	sudo chown jenkins.jenkins $directory
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
	#
	# install packages we need
	#
	if [ $BASEDIR/$0 -nt $STAMP ] || [ ! -f $STAMP ] ; then
		DEBS=" 
			bash-completion 
			bc
			bsd-mailx
			curl 
			debootstrap 
			devscripts
			eatmydata
			etckeeper
			figlet
			git
			haveged
			htop
			less
			locales-all
			lsof
			molly-guard
			moreutils
			munin-node
			munin-plugins-extra
			netcat-traditional
			ntp
			ntpdate
			pigz 
			postfix
			procmail
			psmisc
			python3-psycopg2 
			schroot 
			screen
			slay
			subversion 
			subversion-tools 
			sudo 
			unzip 
			vim 
			zsh
			"
		# install squid everywhere except on the armhf nodes
		case $HOSTNAME in
			jenkins|jenkins-test-vm|profitbricks-build*) DEBS="$DEBS
				squid3"
			   ;;
			*) ;;
		esac
		# needed to run the 2nd reproducible builds nodes in the future...
		case $HOSTNAME in
			profitbricks-build4-amd64|profitbricks-build5-amd64|profitbricks-build6-i386) DEBS="$DEBS ntpdate" ;;
			*) ;;
		esac
		# needed to run coreboot/openwrt/lede/netbsd/fedora/fdroid jobs
		case $HOSTNAME in
			profitbricks-build3-amd64|profitbricks-build4-amd64) DEBS="$DEBS
				bison
				ca-certificates
				cmake
				diffutils
				findutils
				flex
				g++
				gawk
				gcc
				git
				grep
				iasl
				libc6-dev
				libncurses5-dev
				libssl-dev
				locales-all
				kgb-client
				m4
				make
				python3-clint
				python3-git
				python3-requests
				python3-yaml
				subversion
				sysvinit-core
				tree
				unzip
				util-linux
				vagrant
				virtualbox
				zlib1g-dev"
			   ;;
			*) ;;
		esac
		# cucumber dependencies
		case $HOSTNAME in
			profitbricks-build10-amd64|jenkins-test-vm) DEBS="$DEBS
				cucumber
				tesseract-ocr
				i18nspector
				imagemagick
				libav-tools
				libsikuli-script-java
				libvirt-bin
				libvirt-dev
				ovmf
				python-jabberbot
				python-potr
				python3-yaml
				ruby-guestfs
				ruby-libvirt
				ruby-net-irc
				ruby-packetfu
				ruby-rb-inotify
				ruby-rjb
				ruby-test-unit
				tcpdump
				unclutter
				virt-viewer
				x264
				xvfb
				x11vnc"
			   ;;
			*) ;;
		esac
		if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
			# for phil only
			DEBS="$DEBS postfix-pcre"
		fi
		if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
			MASTERDEBS=" 
				apache2 
				apt-file 
				apt-listchanges 
				asciidoc
				binfmt-support 
				bison 
				build-essential 
				calamaris 
				cmake 
				cron-apt 
				csvtool 
				dnsmasq-base 
				dose-extra 
				dstat 
				figlet 
				flex
				gawk 
				ghc
				git-notifier 
				gocr 
				graphviz 
				iasl 
				imagemagick 
				ip2host
				jekyll
				kgb-client
				libapache2-mod-macro 
				libcap2-bin 
				libfile-touch-perl 
				libguestfs-tools 
				libjson-rpc-perl 
				libsoap-lite-perl 
				libvirt0 
				libvirt-bin 
				libvpx1 
				libxslt1-dev 
				linux-image-amd64
				moreutils 
				mr 
				mtr-tiny 
				munin 
				ntp 
				openbios-ppc 
				openbios-sparc 
				openjdk-7-jre 
				pandoc
				postgresql-client-9.4 
				poxml 
				procmail 
				python3-debian 
				python3-pystache
				python3-sqlalchemy
				python3-xdg
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
				ruby-rspec 
				seabios 
				shorewall 
				shorewall6 
				sqlite3 
				syslinux 
				tor
				vncsnapshot 
				vnstat
				whohas
				x11-apps 
				xtightvncviewer
				xvfb
				xvkbd
				zutils"
		else
			MASTERDEBS=""
		fi
		$UP2DATE || sudo apt-get update
		$UP2DATE || sudo apt-get install $DEBS $MASTERDEBS
		$UP2DATE || sudo apt-get install -t jessie-backports \
				pbuilder lintian || echo "this should only fail on the first install"
		#		botch
		# we need mock from bpo to build current fedora
		# we need vagrant from bpo to build fdroid
		if [ "$HOSTNAME" = "profitbricks-build3-amd64" ] || [ "$HOSTNAME" = "profitbricks-build4-amd64" ] || [ "$HOSTNAME" = "jenkins" ] ; then
			$UP2DATE || sudo apt-get install -t jessie-backports mock python3-vagrant \
				|| echo "this should only fail on the first install"
		fi
		# for varying kernels
		# we use bpo kernels on pb-build5+6 (and i386 kernel on pb-build2-i386)
		if [ "$HOSTNAME" = "profitbricks-build5-amd64" ] || [ "$HOSTNAME" = "profitbricks-build6-i386" ]; then
			$UP2DATE || sudo apt-get install -t jessie-backports linux-image-amd64 || echo "this should only fail on the first install"
		fi
		# only needed on the main node
		if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
			$UP2DATE || sudo apt-get install -t jessie-backports jenkins-job-builder || echo "this should only fail on the first install"
		elif [ "$HOSTNAME" = "jenkins" ] ; then
			$UP2DATE || sudo apt-get install -t jessie-backports ffmpeg libav-tools python3-popcon jenkins-job-builder
		fi
		explain "packages installed."
	else
		explain "no new packages to be installed."
	fi
fi

#
# deploy package configuration in /etc and /usr/local/
#
cd $BASEDIR
sudo cp --preserve=mode,timestamps -r hosts/$HOSTNAME/etc/* /etc
sudo cp --preserve=mode,timestamps -r hosts/$HOSTNAME/usr/* /usr/

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
		sudo chown jenkins-adm.jenkins-adm /etc/apache2/sites-enabled/jenkins.debian.net.conf
		# for reproducible.d.n url rewriting:
		[ -L /var/www/userContent ] || sudo ln -sf /var/lib/jenkins/userContent /var/www/userContent
		sudo service apache2 reload
	fi
fi

if [ $BASEDIR/hosts/$HOSTNAME/etc/munin -nt $STAMP ] || [ ! -f $STAMP ] ; then
	cd /etc/munin/plugins
	sudo rm -f postfix_* open_inodes interrupts irqstats threads proc_pri vmstat if_err_* exim_* netstat fw_forwarded_local fw_packets forks open_files users nfs* iostat_ios 2>/dev/null
	case $HOSTNAME in
			jenkins|profitbricks-build*) [ -L /etc/munin/plugins/squid_cache ] || for i in squid_cache squid_objectsize squid_requests squid_traffic ; do sudo ln -s /usr/share/munin/plugins/$i $i ; done ;;
			*)	;;
	esac
	if [ "$HOSTNAME" != "jenkins" ] && [ -L /etc/munin/plugins/iostat ] ; then
		sudo rm /etc/munin/plugins/iostat
	fi
	if [ "$HOSTNAME" = "jenkins" ] && [ ! -L /etc/munin/plugins/apache_accesses ] ; then
		for i in apache_accesses apache_volume ; do sudo ln -s /usr/share/munin/plugins/$i $i ; done
		sudo ln -s /usr/share/munin/plugins/loggrep jenkins_oom
	fi
	sudo service munin-node force-reload
fi
explain "packages configured."

#
# install the heart of jenkins.debian.net
#
cd $BASEDIR
[ -d /srv/jenkins/features ] && sudo rm -rf /srv/jenkins/features
for dir in bin logparse cucumber live mustache-templates ; do
	sudo mkdir -p /srv/jenkins/$dir
	sudo rsync -rpt --delete $dir/ /srv/jenkins/$dir/
	sudo chown -R jenkins-adm.jenkins-adm /srv/jenkins/$dir
done
HOST_JOBS="hosts/$HOSTNAME/job-cfg"
if [ -e "$HOST_JOBS" ] ; then
	sudo rsync -rpt --copy-links --delete "$HOST_JOBS/" /srv/jenkins/job-cfg/
	sudo chown -R jenkins-adm.jenkins-adm /srv/jenkins/$dir
else
	# tidying up ... assuming that we don't want clutter on peripheral servers
	[ -d /srv/jenkins/job-cfg ] && sudo rm -rf /srv/jenkins/job-cfg
fi


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
	git log | grep ^Author| cut -d " " -f2-|sort -u -f > $TMPFILE
	echo "----" >> $TMPFILE
	sudo tee /var/lib/jenkins/userContent/THANKS > /dev/null < THANKS.head
	# samuel, lunar, josch and phil committed with several commiters, only display one
	grep -v -e "samuel.thibault@ens-lyon.org" -e Lunar -e "j.schauer@email.de" -e "mattia@mapreri.org" -e "phil@jenkins-test-vm" $TMPFILE | sudo tee -a /var/lib/jenkins/userContent/THANKS > /dev/null
	rm $TMPFILE
	TMPDIR=$(mktemp -d -t update-jdn-XXXXXXXX)
	sudo cp -pr userContent $TMPDIR/
	sudo chown -R jenkins.jenkins $TMPDIR
	sudo cp -pr $TMPDIR/userContent  /var/lib/jenkins/
	sudo rm -r $TMPDIR > /dev/null
	cd /var/lib/jenkins/userContent/
	ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
	[ about.html -nt README ] || asciidoc $ASCIIDOC_PARAMS -o about.html README
	[ todo.html -nt TODO ] || asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
	[ setup.html -nt INSTALL ] || asciidoc $ASCIIDOC_PARAMS -o setup.html INSTALL
	[ contributing.html -nt CONTRIBUTING ] || asciidoc $ASCIIDOC_PARAMS -o contributing.html CONTRIBUTING
	diff THANKS .THANKS >/dev/null || asciidoc $ASCIIDOC_PARAMS -o thanks.html THANKS
	mv THANKS .THANKS
	rm TODO README INSTALL CONTRIBUTING
	sudo chown jenkins.jenkins /var/lib/jenkins/userContent/*html
	explain "user content for jenkins updated."
fi

if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	#
	# run jenkins-job-builder to update jobs if needed
	#     (using sudo because /etc/jenkins_jobs is root:root 700)
	#
	cd /srv/jenkins/job-cfg
	for metaconfig in *.yaml.py ; do
	# there are both python2 and python3 scripts here
		[ -e ./$metaconfig ] || continue
		./$metaconfig > $TMPFILE
		if ! sudo -u jenkins-adm cmp -s ${metaconfig%.py} - < $TMPFILE ; then
			sudo -u jenkins-adm tee ${metaconfig%.py} > /dev/null < $TMPFILE
		fi
	done
	rm -f $TMPFILE
	for config in *.yaml ; do
		# do update, if
		# no stamp file exist or
		# no .py file exists and config is newer than stamp or
		# a .py file exists and .py file is newer than stamp
		if [ ! -f $STAMP ] || \
		 ( [ ! -f $config.py ] && [ $config -nt $STAMP ] ) || \
		 ( [ -f $config.py ] && [ $config.py -nt $STAMP ] ) ; then
			$JJB update $config
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

if [ "$HOSTNAME" = "jenkins" ] ; then
	#
	# creating LVM volume group for jobs
	#
	if [ "$PVNAME" = "" ]; then
		figlet -f banner Error
		explain "you must set \$PVNAME to physical volume pathname, exiting."
		exit 1
	elif ! $UP2DATE ; then
		if ! sudo pvs $PVNAME >/dev/null 2>&1; then
			sudo pvcreate $PVNAME
		fi
		if ! sudo vgs $VGNAME >/dev/null 2>&1; then
			sudo vgcreate $VGNAME $PVNAME
		fi
	fi
fi

#
# generate the kgb-client configurations
#
if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "profitbricks-build3-amd64" ] || [ "$HOSTNAME" = "profitbricks-build4-amd64" ] ; then
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
		echo "/srv/jenkins/kbg should be mode 755 and owned by jenkins-adm:root."
		echo "/srv/jenkins/kbg/client-status should be mode 755 and owned by jenkins:jenkins."
	fi
fi

#
# There's always some work left...
#	echo FIXME is ignored so check-jobs scripts can output templates requiring manual work
#
if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	rgrep FI[X]ME $BASEDIR/* | grep -v echo > $TMPFILE || true
	if [ -s $TMPFILE ] ; then
		echo
		# only show cucumber FIXMEs when deploying on jenkins-test-vm
		if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
			cat $TMPFILE
		else
			cat $TMPFILE | grep -v cucumber
		fi
		echo
	fi
	rm -f $TMPFILE
fi

#
# almost finally…
#
sudo touch $STAMP	# so on the next run, only configs newer than this file will be updated
explain "$(date) - finished deployment."

# finally!
case $HOSTNAME in
	# set time back to the future
	profitbricks-build4-amd64|profitbricks-build5-amd64|profitbricks-build6-i386)
		sudo date --set="+398 days +6 hours + 23 minutes"
		;;
	opi2a)
		# this host is acting strange…
		# cleaning up our workaround…
		sudo rm /usr/sbin/policy-rc.d
		;;
	jenkins)
		# notify irc
		MESSAGE="jenkins.d.n updated to $(cd $BASEDIR ; git describe --always)."
		kgb-client --conf /srv/jenkins/kgb/debian-qa.conf --relay-msg "$MESSAGE"
		;;
	*)	;;
esac

echo
figlet ok
echo
echo "__$HOSTNAME=ok__"

