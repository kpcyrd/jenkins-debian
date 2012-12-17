#
# Regular cron jobs for the jenkins.debian.net package
#
0 4	* * *	root	[ -x /usr/bin/jenkins.debian.net_maintenance ] && /usr/bin/jenkins.debian.net_maintenance
