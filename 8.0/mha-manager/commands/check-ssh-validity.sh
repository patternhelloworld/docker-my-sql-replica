#!/bin/bash
source ./cache-global-vars.sh

check_ssh_validity(){
    echo "[NOTICE] Test SSH connections from MHA to ${1}"
    status=$(docker exec ${mha_container_name} sh -c 'exec ssh -o BatchMode=yes -o ConnectTimeout=5 -p '${2}' root@'${1}' echo ok 2>&1')
    #status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p ${2} root@${1} echo ok 2>&1) r

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
      exit 1
    fi
}

check_ssh_validity ${machine_master_ip} ${machine_master_ssh_port}
#check_ssh_validity ${machine_slave_ip} ${machine_slave_ssh_port}

