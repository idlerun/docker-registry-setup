Hosting a private Docker registry is very useful. This article details how to setup a Docker registry
running inside AWS which is secured by client certificates for authentication.

## Server Setup

#### S3 Registry Bucket

Create a new S3 bucket. This will be the backing data-store for the registry.

#### Role

Create a new AWS role **Docker-Registry** for the instance.

Grant S3 access to the registry bucket with a custom role policy (replace REGISTRY\_BUCKET\_NAME with your bucket name):

```json
{
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::REGISTRY_BUCKET_NAME",
                "arn:aws:s3:::REGISTRY_BUCKET_NAME/*"
            ]
        }
    ]
}
```


#### Create

Create a new Ubuntu 14.04 instance on AWS (Micro is sufficient). Set the instance role to **Docker-Registry**.

_Amazon Linux is not recommended as it installs an out-dated version of Docker_

For the security group open port 22 (ssh) and 443 (https)

#### Pre-reqs

Install Docker as per [docs](https://docs.docker.com/installation/)

```bash
curl -sSL https://get.docker.com/ | sh
service docker start
usermod -aG docker ubuntu
```

Install AWS-cli

```bash
apt-get install -q -y python-pip
pip install awscli
```


## Certificates

Before getting started with the Docker containers, some certificates are needed.

#### Server Certificate

Generate a self-signed cert for the server _(replace **HOST=**  value with desired server name)_

```bash
HOST=my-registry

mkdir -p /opt/registry/
cd /opt/registry/
mkdir -p certs
openssl req -nodes -newkey rsa:8192 -days 365 -x509 -keyout certs/server.key -out certs/server.cert \
  -batch -subj "/commonName=$HOST"
chmod 600 certs/server.key
```

#### Client CA Certificate

A self-signed CA cert is used for signing all client certs. The nginx proxy will be configured to
use the CA cert to determine trust.

```bash
cd /opt/registry/
openssl req -nodes -newkey rsa:8192 -days 365 -x509 -keyout client-ca.key -out certs/client-ca.cert \
  -batch -subj "/commonName=docker-registry-client-ca"
chmod 600 client-ca.key
```

#### Generate CA-Signed Client Cert

Any time a new client cert is needed it can be generated with the script below.
This cert is signed with the client CA cert so the server will automatically trust it.

##### [gen-client-cert.sh](https://github.com/idlerun/docker-registry-setup/blob/master/gen-client-cert.sh)

To verify a client cert manually:

~~~ bash
openssl verify -CAfile /opt/registry/certs/client-ca.cert client.cert
~~~


## Registry

#### Config File
Customize a config.yml for the registry at /opt/registry/config.yml.

##### [config.yml](https://github.com/idlerun/docker-registry-setup/blob/master/config.yml)

Hint: you can use the following to generate a random secret:

~~~ bash
xxd -l 16 -p /dev/random
~~~


#### Container
Create a Docker container for the registry

~~~ bash
docker run -d --restart=always --name registry \
  -v /opt/registry/config.yml:/etc/docker/registry/config.yml \
  registry:2
~~~


## Nginx

#### Config File
Create `/opt/registry/nginx-registry.conf`

[nginx-registry.conf](https://github.com/idlerun/docker-registry-setup/blob/master/nginx-registry.conf)

#### Container
Create a docker container for nginx

```bash
docker run -d --restart=always --name nginx \
  --publish 443:443 \
  --link registry:registry \
  -v /opt/registry/nginx-registry.conf:/etc/nginx/conf.d/default.conf \
  -v /opt/registry/certs:/etc/nginx/ssl \
  nginx
```

## Test

Verify that both components are running and connected correctly

_Requires that gen-client-cert.sh has been run to generate a client cert_

```bash
curl -v -k --cert ./client.cert --key ./client.key https://localhost:443/v2/
```

## Docker Client Configuration

#### Client Setup Script

To configure your development machines for access to the registry

Run the following on the registry server to generate a client configuration script.
Copy the script output to the client by copy-paste or any other method and run it as root.

##### [client-config-gen.sh](https://github.com/idlerun/docker-registry-setup/blob/master/client-config-gen.sh)

## AWS - EC2 Client

This section will assist in setting up an AWS EC2 instance which is ready to use the registry at boot.

#### Client Config Bucket

Create a new S3 bucket for the client configuration files

#### Instance Role

Create an AWS role **Docker-Instance** and give it a custom policy with read access to the config bucket. _(Replace CONFIG\_BUCKET\_NAME with the bucket name)_

```json
{
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket", "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::CONFIG_BUCKET_NAME",
                "arn:aws:s3:::CONFIG_BUCKET_NAME/*"
            ]
        }
    ]
}
```

#### Create Instance

Set the role to the **Docker-Instance** created above.

Use the following script to generate the user-data (set under Advanced Details):

_(Replace CONFIG\_BUCKET\_NAME with the bucket name)_

##### [aws-config-gen.sh](https://github.com/idlerun/docker-registry-setup/blob/master/aws-config-gen.sh)

Boot the instance

## Usage

Usage is described in detail [here](https://docs.docker.com/registry/deploying/)

For example:

```bash
docker pull ubuntu
docker tag ubuntu myregistrydomain:443/ubuntu
docker push myregistrydomain:443/ubuntu
docker pull myregistrydomain:443/ubuntu
```

To force the Docker client to pull the latest versions of all container images use the following (from [here](http://blog.stefanxo.com/2014/08/update-all-docker-images-at-once/))
```bash
docker images | awk '/^REPOSITORY|\<none\>/ {next} {print $1}' | xargs -n 1 docker pull
```
