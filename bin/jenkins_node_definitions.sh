#!/bin/bash

# Copyright 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# define Debian build nodes in use
BUILD_NODES="profitbricks-build1-amd64.debian.net profitbricks-build2-amd64.debian.net profitbricks-build5-amd64.debian.net profitbricks-build6-amd64.debian.net wbq0-armhf-rb.debian.net cbxi4a-armhf-rb.debian.net cbxi4b-armhf-rb.debian.net cbxi4pro0-armhf-rb.debian.net bbx15-armhf-rb.debian.net bpi0-armhf-rb.debian.net hb0-armhf-rb.debian.net odxu4-armhf-rb.debian.net wbd0-armhf-rb.debian.net rpi2b-armhf-rb.debian.net rpi2c-armhf-rb.debian.net odxu4b-armhf-rb.debian.net odxu4c-armhf-rb.debian.net ff2a-armhf-rb.debian.net ff2b-armhf-rb.debian.net ff4a-armhf-rb.debian.net opi2a-armhf-rb.debian.net opi2b-armhf-rb.debian.net"

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
	  opi2a-armhf-rb.debian.net)
	    PORT=2236
	    ;;
	  opi2b-armhf-rb.debian.net)
	    PORT=2238
	    ;;
	  profitbricks-build?-amd64.debian.net)
	    PORT=22
	    ;;
	  *)
	    echo >&2 "Unknown node $NODE_NAME."
	    exit 1
	esac
}

