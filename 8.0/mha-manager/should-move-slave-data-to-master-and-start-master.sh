#!/bin/bash

source ./util.sh

echo "[NOTICE] Load Global Variables"
cache_global_vars

create_host_folders_if_not_exists() {

  arr_variable=("$mysql_data_path_master" "$mysql_log_path_master" "$mysql_file_path_master" "$mysql_etc_path_master" "$mysql_data_path_slave" "$mysql_log_path_slave" "$mysql_file_path_slave" "$mysql_etc_path_slave")

  ## now loop through the above array
  for val in "${arr_variable[@]}"; do
    if [[ -d $val ]]; then
      echo "[NOTICE] The directory of '$val' already exists."
    else
      if [ -z $val ]; then
        echo "[NOTICE] The variable '$val' is empty"
        exit 0
      fi

      sudo mkdir -p $val

      echo "[NOTICE] The directory of '$val' has been created."
    fi

    sudo chown -R 999:999 $val

  done
}

create_host_folders_if_not_exists

echo "[NOTICE] Export SQL from Slave & Save it on MHA (/var/tmp/all-databases.sql)"
docker exec ${mha_container_name} sh -c 'exec mysqldump -h'${machine_slave_ip}' -uroot -p'${slave_root_password}' --master-data=2 --flush-logs --all-databases --single-transaction --ignore-table=mysql.innodb_index_stats --ignore-table=mysql.innodb_table_stats > /var/tmp/all-databases.sql'

# [[ docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' ]] means that

echo "[NOTICE] Restart SSH for Master"
if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "service ssh restart"'
elif [[ ${separated_mode} == false ]]; then
  docker exec ${master_container_name} service ssh restart
fi

sleep 3

echo "[NOTICE] Stop Master Container to normalize DB"
if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "docker-compose rm -s -v db-master"'
elif [[ ${separated_mode} == false ]]; then
  docker-compose rm -s -v db-master
fi

timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
echo "[NOTICE] Remove all DB data to normalize DB (${timestamp})"
if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "mkdir -p /var/backups/mysql/'${timestamp}' && mv /var/lib/mysql/* /var/backups/mysql/'${timestamp}'"'
elif [[ ${separated_mode} == false ]]; then
  sudo mkdir -p ./backups/master/data/${timestamp} && sudo mv ./master/data/* ./backups/master/data/${timestamp}
fi

sleep 3

echo "[NOTICE] Start Master to normalize DB"
if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "docker-compose up -d db-master"'
elif [[ ${separated_mode} == false ]]; then
  docker-compose up -d db-master
fi

sleep 3

echo "[NOTICE] Wait until Master is up"
if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} mysql -uroot -p${master_root_password} -h${machine_master_ip} -P${separated_mode_master_port} -e "FLUSH TABLES WITH READ LOCK;"
  wait_until_db_up_remote "${machine_master_ip}" "${master_root_password}" ${mha_container_name}
elif [[ ${separated_mode} == false ]]; then
  docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH TABLES WITH READ LOCK;"
  wait_until_db_up "${master_container_name}" "${master_root_password}"
fi

echo "[NOTICE] Import '/var/tmp/all-databases.sql' into Master DB"
docker exec ${mha_container_name} sh -c 'exec mysql -h'${machine_master_ip}' -uroot -p'${master_root_password}' -f < /var/tmp/all-databases.sql'


if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} mysql -uroot -p${master_root_password} -h${machine_master_ip} -P${separated_mode_master_port} -e "UNLOCK TABLES;"
elif [[ ${separated_mode} == false ]]; then
  docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "UNLOCK TABLES;"
fi

echo "[NOTICE] Restart SSH for Master"
if [[ ${separated_mode} == true ]]; then
  docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "service ssh restart"'
elif [[ ${separated_mode} == false ]]; then
  docker exec ${master_container_name} service ssh restart
fi