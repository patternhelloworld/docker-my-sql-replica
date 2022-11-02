#!/bin/bash
source ./cache-global-vars.sh

check_ssh_validity(){
    echo "[NOTICE] Test SSH connections from MHA to ${1}"
    status=$(docker exec ${mha_container_name} sh -c 'exec ssh -o BatchMode=yes -o ConnectTimeout=5 root@'${1}' echo ok 2>&1')

    if [[ $status == ok ]] ; then
      echo "${1} Valid"
    elif [[ $status == "Warning: Permanently added"* ]] ; then
      echo "${1} Valid ($status)"
      exit 1
    elif [[ $status == "Permission denied"* ]] ; then
      echo "[ERROR] ${1} invalid. Stopping... ($status)"
      exit 1
    else
      echo "[ERROR] ${1} invalid. Stopping... ($status)"
    fi
}

check_ssh_validity ${machine_master_ip}
check_ssh_validity ${machine_slave_ip}

