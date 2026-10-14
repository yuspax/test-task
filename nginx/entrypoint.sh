#!/bin/sh
set -eu

DNS_RESOLVER="$(awk '/^nameserver / { print $2; exit }' /etc/resolv.conf)"
export DNS_RESOLVER
envsubst '${APP_UPSTREAM} ${DNS_RESOLVER}' < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
exec nginx -c /tmp/nginx.conf -g 'daemon off;'
