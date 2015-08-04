#!/bin/bash

set -u
set -e

case "$NODE_NAME" in
  bpi0-armhf-rb.debian.net)
    exec ssh -p 2222 jenkins@$NODE_NAME "$JOB_NAME"
    ;;
  hb0-armhf-rb.debian.net)
    exec ssh -p 2224 jenkins@$NODE_NAME "$JOB_NAME"
    ;;
  wbq0-armhf-rb.debian.net)
    exec ssh -p 2225 jenkins@$NODE_NAME "$JOB_NAME"
    ;;
  cbxi4pro0-armhf-rb.debian.net)
    exec ssh -p 2226 jenkins@$NODE_NAME "$JOB_NAME"
    ;;
  *)
    echo >&2 "Unknown node $NODE_NAME."
    exit 1
esac
