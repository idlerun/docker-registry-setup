#!/bin/bash

openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr -batch -subj "/commonName=docker-registry-client"
sudo openssl x509 -req -days 365 -in client.csr \
  -CA /opt/registry/certs/client-ca.cert -CAkey /opt/registry/client-ca.key \
  -set_serial 01 -out client.cert
rm -f client.csr