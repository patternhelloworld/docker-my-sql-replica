#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] SSH private & public keys generated and check the public key in host folder (../shares/.ssh/authorized-keys/db-slave.pub)"
docker exec ${slave_container_name} sh -c 'ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa' || exit 1
cp ../shares/.ssh/slave/id_rsa.pub ../shares/.ssh/authorized-keys/db-slave.pub
