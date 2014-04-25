#!/bin/bash

# Copyright 2012,2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# convert params to variables
if [ "$1" == "" ] ; then
	echo "need at least one URL to act on"
	echo '# $1 = URL'
	exit 1
fi
URL=$1
PATTERNS=$2

#
# Don't use --continue on first run
#
if [ ! -e webcheck.dat ] ; then
	PARAMS=""
else
	PARAMS="-c -f"
fi

#
# if $URL ends with / then run webcheck with -b
#
if [ "${URL: -1}" = "/" ] ; then
	echo "URL ending in / - adding '-b' to parameters."
	PARAMS="$PARAMS -b"
fi

#
# ignore some extra patterns (=all translations) when checking www.debian.org
#
if [ "${URL:0:21}" = "http://www.debian.org" ] ; then
	echo "URL starts with http://www.debian.org - so better ignore lots of translated documents. (Checking translations is out of scope for this test.)"
	# originly was TRANSLATIONS=$(curl www.debian.org 2>/dev/null|grep index|grep lang=|cut -d "." -f2)
	# but then I had to add some and then some more... so I reached to the conclusion to hardcode them all
	TRANSLATIONS="ar bg ca cs da de el es eo fa fr ko hy hr id it he lt hu nl ja nb pl pt ro ru sk fi sv ta tr uk zh-cn zh-hk zh-tw ml vi"
	for LANG in $TRANSLATIONS pt_BR zh_CN zh_HK zh_TW ; do
		PARAMS="$PARAMS -y \.${LANG}\.html -y html\.${LANG} -y \.${LANG}\.txt -y \.txt\.${LANG} -y \.${LANG}\.pdf -y \.pdf\.${LANG}"
	done
fi

#
# ignore some extra patterns (=the installation manual for all releases and all archs) when checking www.debian.org
#
if [ "${URL:0:21}" = "http://www.debian.org" ] && [ "${URL: -1}" != "/" ] ; then
	echo "URL is http://www.debian.org - so better ignore all those manuals for all releases (and the architecture permutations). (Checking these manuals is out of scope for this test.)"
	RELEASES="slink potato woody sarge etch lenny squeeze wheezy stable"
	SLINK="i386 m68k alpha sparc source"
	POTATO="$SLINK powerpc arm"
	WOODY="$POTATO hppa ia64 mips mipsel s390"
	SARGE=$WOODY
	ETCH="$SARGE amd64"
	LENNY="$ETCH armel"
	SQUEEZE="amd64 i386 armel sparc powerpc ia64 mips mipsel s390 kfreebsd-amd64 kfreebsd-i386"  # yes there is mips
	STABLE=$SQUEEZE
	WHEEZY="$SQUEEZE armhf s390x"
	#JESSIE=$WHEEZY		# also needs to be added to RELEASES above
	for RELEASE in $RELEASES ; do
		RELEASEVAR=$(echo $RELEASE | tr  "[:lower:]" "[:upper:]")
		for ARCH in ${!RELEASEVAR} ; do
			PARAMS="$PARAMS -y www\.debian\.org/releases/$RELEASE/+$ARCH/"
		done
	done
	#
	# Remind, that this needs to be updated manually
	#
	if [ $(date +%Y) -gt 2013 ] ; then
		echo "next Warning: It's not 2013 anymore, check which architectures Jessie has for real."
	fi
fi

#
# $PATTERNS can only be used to ignore patterns atm
#
if [ "$PATTERNS" != "" ] ; then
	PARAMS="$PARAMS $(for i in $PATTERNS ; do echo -n " -y $i" ; done)"
fi

#
# actually run webcheck
#
echo "Now running: webcheck $URL $PARAMS"
echo
webcheck $URL $PARAMS
