#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] Create /root/.ssh/authorized_keys..."
cat ../shares/.ssh/authorized-keys/*.pub > ../shares/.ssh/slave/authorized_keys
docker exec ${slave_container_name} sh -c 'service ssh restart'