#!/bin/bash

set -x

: ${VERSION:=4.2.9}

MYSQL_NAME=kuleuven-mysql
MYSQL_ROOT_PASSWORD=rootpw
IRODS_NAME=kuleuven-irods
IRODS_HOST=irods.container
IRODS_ZONE=test
IRODS_IMAGE=kuleuven-irods:mysql

mkdir -p packages
cp /home/swooshy/devstuff/renci/builds/centos7-stable/packages/*.rpm packages/

set -e
docker build -t $IRODS_IMAGE \
  --build-arg VERSION=$VERSION \
  --build-arg UID=$(id -u) \
  --build-arg GID=$(id -g) \
  .
set +e

docker rm -f $MYSQL_NAME $IRODS_NAME

mkdir -p ssl
test -f ssl/cert.pem || docker run -i --rm -v $(pwd)/ssl:/ssl securefab/openssl req -x509 -nodes -newkey rsa:4096 -keyout /ssl/key.pem -out /ssl/cert.pem -days 365 \
     -subj '/CN=$(IRODS_HOST)' \
     -addext "subjectAltName = DNS:$IRODS_HOST"
cat ssl/cert.pem > ssl/ca-bundle.pem

docker run -d --name $MYSQL_NAME -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD mysql:5
sleep 15
docker exec -i $MYSQL_NAME mysql -h localhost -uroot -p$MYSQL_ROOT_PASSWORD <<'EOF'
CREATE DATABASE irods;
ALTER DATABASE irods CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
CREATE USER 'irods'@'%' IDENTIFIED WITH mysql_native_password BY 'irods';
GRANT ALL ON irods.* TO 'irods'@'%';
EOF

mkdir -p irods/keys
if [ ! -e irods/keys/srv_negotiation.key ]; then
  openssl rand -hex 16 > irods/keys/srv_negotiation.key
fi
if [ ! -e irods/keys/srv_zone.key ]; then
  openssl rand -hex 16 > irods/keys/srv_zone.key
fi
if [ ! -e irods/keys/ctrl_plane.key ]; then
  openssl rand -hex 16 > irods/keys/ctrl_plane.key
fi

SRV_NEGOTIATION_KEY="$(<irods/keys/srv_negotiation.key)"
SRV_ZONE_KEY="$(<irods/keys/srv_zone.key)"
CTRL_PLANE_KEY="$(<irods/keys/ctrl_plane.key)"

mkdir -p logs.new

echo docker run --name $IRODS_NAME --link $MYSQL_NAME \
  --hostname $IRODS_HOST \
  --shm-size="1G" \
  -v $(pwd)/ssl:/ssl \
  -v $(pwd)/logs.new:/var/lib/irods/log \
  -v $(pwd)/packages:/irods_packages:ro \
  -v /home/swooshy/devstuff/renci/irods:/irods_source:ro \
  -v /home/swooshy/devstuff/renci/irods_client_icommands:/icommands_source:ro \
  -v /home/swooshy/devstuff/renci/irods_rule_engine_plugin_python:/re_python_source:ro \
  -v /home/swooshy/devstuff/renci/irods_rule_engine_plugin_audit_amqp:/re_audit_amqp_source:ro \
  -v /home/swooshy/devstuff/renci/builds/centos7-stable/irods:/irods_build:ro \
  -v /home/swooshy/devstuff/renci/builds/centos7-stable/icommands:/icommands_build:ro \
  -v /home/swooshy/devstuff/renci/builds/centos7-stable/re_python:/re_python_build:ro \
  -v /home/swooshy/devstuff/renci/builds/centos7-stable/re_hard_links:/re_audit_amqp_build:ro \
  -e SERVER=$IRODS_HOST \
  -e ZONE=$IRODS_ZONE \
  -e SRV_NEGOTIATION_KEY="${SRV_NEGOTIATION_KEY}" \
  -e SRV_ZONE_KEY="${SRV_ZONE_KEY}" \
  -e CTRL_PLANE_KEY="${CTRL_PLANE_KEY}" \
  -e DB_NAME=irods \
  -e DB_USER=irods \
  -e DB_PASSWORD=irods \
  -e DB_SRV_HOST=$MYSQL_NAME \
  -e SSL_CERTIFICATE_CHAIN_FILE=/ssl/cert.pem \
  -e SSL_CERTIFICATE_KEY_FILE=/ssl/key.pem \
  -e SSL_CA_BUNDLE=/ssl/ca-bundle.pem \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --privileged \
  $IRODS_IMAGE

exit 0

set -e

until docker exec -i $IRODS_NAME /usr/local/bin/healthcheck; do
  sleep 0.5
done

echo Starting stress test
for i in $(seq 1 100); do 
  docker exec -ti $IRODS_NAME runuser -u irods -- iadmin lu
done
