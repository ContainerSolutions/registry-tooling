#!/bin/bash
set -e
set -o pipefail

if [[ ! -d /certs ]]; then
  mkdir /certs
fi

openssl req -config /in.req -newkey rsa:4096 -nodes -sha256 \
  -keyout /certs/domain.key -x509 -days 265 -out /certs/ca.crt

#should now have /certs/domain.key and /certs/ca.crt
