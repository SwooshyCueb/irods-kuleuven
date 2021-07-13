#!/bin/bash

: ${VERSION:=4.2.9}

POSTGRESQL_NAME=kuleuven-postgres
POSTGRESQL_ROOT_PASSWORD=rootpw
IRODS_NAME=kuleuven-irods
IRODS_HOST=irods.container
IRODS_ZONE=test
IRODS_IMAGE=kuleuven-irods:postgres

set -e
docker build -t $IRODS_IMAGE --build-arg VERSION=$VERSION -f Dockerfile.postgres .
set +e

docker rm -f $POSTGRESQL_NAME $IRODS_NAME

docker run -d --name $POSTGRESQL_NAME -e POSTGRES_PASSWORD=$POSTGRESQL_ROOT_PASSWORD -e PGPASSWORD=$POSTGRESQL_ROOT_PASSWORD postgres:11
sleep 15
docker exec -i $POSTGRESQL_NAME psql -h localhost -U postgres <<'EOF'
CREATE DATABASE irods;                            
CREATE USER irods WITH ENCRYPTED PASSWORD 'irods';
GRANT ALL PRIVILEGES ON DATABASE irods TO irods;  
EOF

SRV_NEGOTIATION_KEY="$(<irods/keys/srv_negotiation.key)"
SRV_ZONE_KEY="$(<irods/keys/srv_zone.key)"
CTRL_PLANE_KEY="$(<irods/keys/ctrl_plane.key)"

mkdir -p logs.new

docker run -d --name $IRODS_NAME --link $POSTGRESQL_NAME \
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
  -e DB_SRV_HOST=$POSTGRESQL_NAME \
  -e SSL_CERTIFICATE_CHAIN_FILE=/ssl/cert.pem \
  -e SSL_CERTIFICATE_KEY_FILE=/ssl/key.pem \
  -e SSL_CA_BUNDLE=/ssl/ca-bundle.pem \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  --privileged \
  $IRODS_IMAGE

#exit 0

set -e

sleep 5
docker exec -i $IRODS_NAME supervisorctl start irods
docker exec -i $IRODS_NAME supervisorctl start irods-initialize
sleep 5

until docker exec -i $IRODS_NAME /usr/local/bin/healthcheck; do
  sleep 0.5
done

echo Starting stress test
for i in $(seq 1 100); do 
  docker exec -ti $IRODS_NAME runuser -u irods -- iadmin lu
done
