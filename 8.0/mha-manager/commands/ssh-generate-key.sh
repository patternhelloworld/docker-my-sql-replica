#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] SSH private & public keys generated and check the public key in host folder (../shares/.ssh/authorized-keys/mha-manager.pub)"
docker exec ${mha_container_name} sh -c 'ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa' || exit 1
mkdir -p ../shares/.ssh/authorized-keys
cp ../shares/.ssh/mha-manager/id_rsa.pub ../shares/.ssh/authorized-keys/mha-manager.pub

