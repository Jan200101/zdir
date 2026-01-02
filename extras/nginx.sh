#!/bin/env bash

TOPDIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

nginx -e /tmp/nginx/error.log -c $TOPDIR/nginx.conf
