#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] SSH private & public keys generated and check the public key in host folder (../shares/ssh-pub-keys/db-master.pub)"
docker exec ${master_container_name} sh -c 'ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa'
mkdir -p ../shares/.ssh/authorized-keys
cp -f ../shares/.ssh/master/id_rsa.pub ../shares/.ssh/authorized-keys/db-master.pub
