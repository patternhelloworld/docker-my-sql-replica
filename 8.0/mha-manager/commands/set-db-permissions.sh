#!/bin/bash
source ./cache-global-vars.sh

echo "[SECURITY] Set my.cnf 999:1000 at all times (999 is 'mysql' user and 1000 is for the host user)"
docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "chown -R 999:1000 ./master/log"'

#sudo chown -R 999:1000 ./slave/log
#sudo chown 999:1000 ./master/my.cnf
#sudo chown 999:1000 ./slave/my.cnf

