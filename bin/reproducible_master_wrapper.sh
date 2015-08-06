#!/bin/bash

set -u
set -e

case "$NODE_NAME" in
  bpi0-armhf-rb.debian.net)
    exec ssh -p 2222 $NODE_NAME "$JOB_NAME"
    ;;
  hb0-armhf-rb.debian.net)
    exec ssh -p 2224 $NODE_NAME "$JOB_NAME"
    ;;
  wbq0-armhf-rb.debian.net)
    exec ssh -p 2225 $NODE_NAME "$JOB_NAME"
    ;;
  cbxi4pro0-armhf-rb.debian.net)
    exec ssh -p 2226 $NODE_NAME "$JOB_NAME"
    ;;
  profitbricks-build?-amd64)
    exec ssh $NODE_NAME "$JOB_NAME"
    ;;
  *)
    echo >&2 "Unknown node $NODE_NAME."
    exit 1
esac
