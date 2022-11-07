#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] Create /root/.ssh/authorized_keys..."
cat ../shares/.ssh/authorized-keys/*.pub > ../shares/.ssh/mha-manager/authorized_keys
docker exec ${mha_container_name} sh -c 'service sshd restart'