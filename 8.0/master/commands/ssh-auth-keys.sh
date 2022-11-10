#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] Create /root/.ssh/authorized_keys..."
cat ../shares/.ssh/authorized-keys/*.pub > ../shares/.ssh/master/authorized_keys
docker exec ${master_container_name} sh -c 'service ssh restart'