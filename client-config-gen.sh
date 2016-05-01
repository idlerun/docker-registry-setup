#!/bin/bash

if [ ! -f client.key ]; then
	echo "Expected a client certificate to exist in the current directory.."
	exit 1
fi

HOST=$(openssl x509 -in /opt/registry/certs/server.cert -text -noout | grep "Subject: CN=" | cut -d"=" -f2)
SERVER_IP="$(wget -q -O- curlmyip.org)"
cat << __EOF__
set -xe
SERVER_CERT="$(cat /opt/registry/certs/server.cert)"
CLIENT_KEY="$(cat client.key)"
CLIENT_CERT="$(cat client.cert)"
mkdir -p /etc/docker/certs.d/$HOST:443
echo "\$SERVER_CERT" > /etc/docker/certs.d/$HOST:443/ca.crt
echo "\$CLIENT_CERT" > /etc/docker/certs.d/$HOST:443/client.cert
echo "\$CLIENT_KEY" > /etc/docker/certs.d/$HOST:443/client.key
# workaround for https://github.com/docker/distribution/issues/426
cat /etc/ssl/certs/*.pem >> /etc/docker/certs.d/$HOST:443/ca.crt
echo "\$(cat /etc/hosts | grep -v '$HOST')" > /etc/hosts
echo "$SERVER_IP $HOST" >> /etc/hosts
__EOF__
