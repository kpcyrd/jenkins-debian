#!/usr/bin/env bash

# Copyright (c) 2009, 2010, 2012, 2015 Peter Palfrader
#               2015 Holger Levsen
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set -e
set -u

MYLOGNAME="`basename "$0"`[$$]"

usage() {
	echo "local Usage: $0"
	echo "via ssh orig command:"
	echo "                      <allowed command>"
}

info() {
	echo >&2 "$MYLOGNAME $1"
	echo > ~/jenkins-ssh-wrap.log "$MYLOGNAME $1"
}

croak() {
	echo >&2 "$MYLOGNAME $1"
	echo > ~/jenkins-ssh-wrap.log "$MYLOGNAME $1"
	exit 1
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

# check/parse remote command line
if [ -z "${SSH_ORIGINAL_COMMAND:-}" ] ; then
	croak "Did not find SSH_ORIGINAL_COMMAND"
fi
set "dummy" ${SSH_ORIGINAL_COMMAND}
shift

allowed_cmds=()

if [[ "$*" =~ /bin/true ]] ; then
	exec /bin/true ; croak "Exec failed";
elif [[ "$*" =~ /bin/nc\ localhost\ 4949 ]] ; then
	exec /bin/nc localhost 4949 ; croak "Exec failed";
elif [[ "$*" =~ rebootstrap_.* ]] ; then
	shift
	REBOOTSTRAPSH="/srv/jenkins/bin/rebootstrap.sh $@"
	export LC_ALL=C
	exec $REBOOTSTRAPSH; croak "Exec failed";
elif [ "$*" = "reproducible_nodes_info" ] ; then
	exec /srv/jenkins/bin/reproducible_info.sh ; croak "Exec failed";
elif [ "$1" = "/srv/jenkins/bin/reproducible_build.sh" ] && ( [ "$2" = "1" ] || [ "$2" = "2" ] ) ; then
	exec /srv/jenkins/bin/reproducible_build.sh "$2" "$3" "$4" "$5" ; croak "Exec failed";
elif [[ "$*" =~ rsync\ --server\ --sender\ .*\ .\ /srv/reproducible-results/tmp.* ]] ; then
	exec rsync --server --sender "$4" . "$6" ; croak "Exec failed";
elif [[ "$*" =~ rm\ -r\ /srv/reproducible-results/tmp.* ]] ; then
	exec rm -r "$3" ; croak "Exec failed";
elif [[ "$*" =~ reproducible_setup_pbuilder_unstable_.*_.* ]] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif [[ "$*" =~ reproducible_setup_pbuilder_testing_.*_.* ]] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh testing ; croak "Exec failed";
elif [[ "$*" =~ reproducible_setup_pbuilder_experimental_.*_.* ]] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh experimental ; croak "Exec failed";
elif [[ "$*" =~ reproducible_maintenance_.*_.* ]] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [[ "$*" =~ reproducible_setup_schroot_unstable_.*_.* ]] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif [[ "$*" =~ reproducible_setup_schroot_testing_.*_.* ]] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-testing testing ; croak "Exec failed";
elif [[ "$*" =~ reproducible_setup_schroot_experimental_.*_.* ]] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-experimental experimental ; croak "Exec failed";
elif [ "$*" = "some_jenkins_job_name" ] ; then
	exec echo run any commands here ; croak "Exec failed";
fi

croak "Command '$*' not found in allowed commands."
