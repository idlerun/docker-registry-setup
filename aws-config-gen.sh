#!/bin/bash -e

CLIENT_BUCKET="CONFIG_BUCKET_NAME"

HOST=$(openssl x509 -in /opt/registry/certs/server.cert -text -noout | grep "Subject: CN=" | cut -d"=" -f2)
SERVER_IP="$(wget -q -O- curlmyip.org)"

aws s3 --sse cp /opt/registry/certs/server.cert s3://$CLIENT_BUCKET/server.cert
aws s3 --sse cp client.cert s3://$CLIENT_BUCKET/client.cert
aws s3 --sse cp client.key s3://$CLIENT_BUCKET/client.key

echo
echo "AWS Instance 'User-Data' Script"
echo "========================================================================"

cat << __EOF__
#!/bin/bash
apt-get update
if [ ! -d /etc/docker/certs.d/$HOST:443 ]; then
  export PATH="\$PATH:/usr/local/bin"
  curl -sSL https://get.docker.com/ | sh
  usermod -aG docker ubuntu
  service docker start
  wget -q -O- https://bootstrap.pypa.io/get-pip.py | python
  pip install awscli
  mkdir -p /etc/docker/certs.d/$HOST:443
  aws s3 cp s3://$CLIENT_BUCKET/server.cert /etc/docker/certs.d/$HOST:443/ca.crt
  aws s3 cp s3://$CLIENT_BUCKET/client.cert /etc/docker/certs.d/$HOST:443/client.cert
  aws s3 cp s3://$CLIENT_BUCKET/client.key /etc/docker/certs.d/$HOST:443/client.key
  cat /etc/ssl/certs/ca-certificates.crt >> /etc/docker/certs.d/$HOST:443/ca.crt
  echo "\$(cat /etc/hosts | grep -v '$HOST')" > /etc/hosts
  echo "$SERVER_IP $HOST" >> /etc/hosts

  # AWS default 'ulimit -n' is 1024 which can cause issues for some containers (like apache2)
  # may need to reboot for this to come into effect
  cat > /etc/security/limits.conf << _FILE_
root soft nofile 16384
root hard nofile 16384
* soft nofile 16384
* hard nofile 16384
_FILE_
fi
__EOF__

echo "========================================================================"
