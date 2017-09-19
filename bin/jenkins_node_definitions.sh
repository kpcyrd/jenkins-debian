#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# define Debian build nodes in use for tests.reproducible-builds.org/debian/
# 	FIXME: this is used differently in two places,
#		- bin/reproducible_html_nodes_info.sh
#		  where it *must* only contain the Debian nodes as it's used
#		  to generate the variations… and
#		- bin/reproducible_cleanup_nodes.sh where it would be
#		  nice to also include pb-build3+4+7+9+10, to also cleanup
#		  jobs there…
BUILD_NODES="bbx15-armhf-rb.debian.net
bpi0-armhf-rb.debian.net
cb3a-armhf-rb.debian.net
cbxi4a-armhf-rb.debian.net
cbxi4b-armhf-rb.debian.net
cbxi4pro0-armhf-rb.debian.net
codethink-sled9-arm64.debian.net
codethink-sled10-arm64.debian.net
codethink-sled11-arm64.debian.net
codethink-sled12-arm64.debian.net
codethink-sled13-arm64.debian.net
codethink-sled14-arm64.debian.net
codethink-sled15-arm64.debian.net
codethink-sled16-arm64.debian.net
ff2a-armhf-rb.debian.net
ff2b-armhf-rb.debian.net
ff4a-armhf-rb.debian.net
ff64a-armhf-rb.debian.net
hb0-armhf-rb.debian.net
jtk1a-armhf-rb.debian.net
jtk1b-armhf-rb.debian.net
jtx1a-armhf-rb.debian.net
jtx1b-armhf-rb.debian.net
jtx1c-armhf-rb.debian.net
odu3a-armhf-rb.debian.net
odxu4-armhf-rb.debian.net
odxu4b-armhf-rb.debian.net
odxu4c-armhf-rb.debian.net
opi2a-armhf-rb.debian.net
opi2b-armhf-rb.debian.net
opi2c-armhf-rb.debian.net
p64b-armhf-rb.debian.net
p64c-armhf-rb.debian.net
profitbricks-build1-amd64.debian.net
profitbricks-build2-i386.debian.net
profitbricks-build5-amd64.debian.net
profitbricks-build6-i386.debian.net
profitbricks-build11-amd64.debian.net
profitbricks-build12-i386.debian.net
profitbricks-build15-amd64.debian.net
profitbricks-build16-i386.debian.net
rpi2b-armhf-rb.debian.net
rpi2c-armhf-rb.debian.net
wbd0-armhf-rb.debian.net
wbq0-armhf-rb.debian.net"

# return the ports sshd is listening on
get_node_ssh_port() {
	local NODE_NAME=$1
	case "$NODE_NAME" in
	  bbx15-armhf-rb.debian.net)
	    PORT=2242
	    ;;
	  bpi0-armhf-rb.debian.net)
	    PORT=2222
	    ;;
	  hb0-armhf-rb.debian.net)
	    PORT=2224
	    ;;
	  wbq0-armhf-rb.debian.net)
	    PORT=2225
	    ;;
	  cbxi4a-armhf-rb.debian.net)
	    PORT=2239
	    ;;
	  cbxi4b-armhf-rb.debian.net)
	    PORT=2240
	    ;;
	  cbxi4pro0-armhf-rb.debian.net)
	    PORT=2226
	    ;;
	  odxu4-armhf-rb.debian.net)
	    PORT=2229
	    ;;
	  wbd0-armhf-rb.debian.net)
	    PORT=2223
	    ;;
	  rpi2b-armhf-rb.debian.net)
	    PORT=2230
	    ;;
	  rpi2c-armhf-rb.debian.net)
	    PORT=2235
	    ;;
	  odxu4b-armhf-rb.debian.net)
	    PORT=2232
	    ;;
	  odxu4c-armhf-rb.debian.net)
	    PORT=2233
	    ;;
	  ff2a-armhf-rb.debian.net)
	    PORT=2234
	    ;;
	  ff2b-armhf-rb.debian.net)
	    PORT=2237
	    ;;
	  ff4a-armhf-rb.debian.net)
	    PORT=2241
	    ;;
	  ff64a-armhf-rb.debian.net)
	    PORT=2250
	    ;;
	  opi2a-armhf-rb.debian.net)
	    PORT=2236
	    ;;
	  opi2b-armhf-rb.debian.net)
	    PORT=2238
	    ;;
	  odu3a-armhf-rb.debian.net)
	    PORT=2243
	    ;;
	  cb3a-armhf-rb.debian.net)
	    PORT=2244
	    ;;
	  opi2c-armhf-rb.debian.net)
	    PORT=2245
	    ;;
	  jtk1a-armhf-rb.debian.net)
	    PORT=2246
	    ;;
	  jtk1b-armhf-rb.debian.net)
	     PORT=2252
	     ;;
	  jtx1a-armhf-rb.debian.net)
	    PORT=2249
	    ;;
	  jtx1b-armhf-rb.debian.net)
	    PORT=2253
	    ;;
	  jtx1c-armhf-rb.debian.net)
	    PORT=2254
	    ;;
	  p64b-armhf-rb.debian.net)
	    PORT=2247
	    ;;
	  p64c-armhf-rb.debian.net)
	    PORT=2248
	    ;;
	  profitbricks-build*)
	    PORT=22
	    ;;
	  codethink-sled9*)
	    PORT=10109
	    ;;
	  codethink-sled10*)
	    PORT=10110
	    ;;
	  codethink-sled11*)
	    PORT=10111
	    ;;
	  codethink-sled12*)
	    PORT=10112
	    ;;
	  codethink-sled13*)
	    PORT=10113
	    ;;
	  codethink-sled14*)
	    PORT=10114
	    ;;
	  codethink-sled15*)
	    PORT=10115
	    ;;
	  codethink-sled16*)
	    PORT=10116
	    ;;
	  *)
	    echo >&2 "Unknown node $NODE_NAME."
	    exit 1
	    ;;
	esac
}

