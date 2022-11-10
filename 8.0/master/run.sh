#!/bin/bash
echo "[NOTICE] To prevent CRLF errors on Windows, CRLF->LF ... "
sudo sed -i -e "s/\r$//g" $(basename $0)
sleep 3
source ./util.sh


initialize_files(){
  sudo rm -f ./master/etc/all-databases.sql
}

create_host_folders_if_not_exists() {

  arr_variable=("$mysql_data_path_master" "$mysql_log_path_master" "$mysql_file_path_master" "$mysql_etc_path_master")

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

re_up_master() {

  docker-compose down

  docker-compose up -d db-master

}

prepare_ssh_keys_none_separated_mode() {

  echo "MASTER - GENERATE SSH PUBLIC,PRIVATE KEYS"
  docker exec -it ${master_container_name} /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh

  echo "MASTER - RESTART SSH"
  docker exec -it ${master_container_name} service ssh restart

}


cache_set_vip() {

    if [[ ${separated_mode} == true ]]; then

      master_network_interface_name=$(ip addr show | awk '/inet.*brd/{print $NF; exit}' || exit 1)
      mha_vip=${machine_mha_vip}

      echo "[NOTICE] Set MHA VIP on Master (on a different machine = ${separated_mode})"
      ifconfig ${master_network_interface_name}:1 ${mha_vip}

    elif [[ ${separated_mode} == false ]]; then

      master_network_interface_name=eth0
      mha_vip=${machine_mha_vip}

      echo "[NOTICE] Set MHA VIP on Master (on a different machine = ${separated_mode})"
      docker exec ${master_container_name} sh -c "ifconfig ${master_network_interface_name}:1 ${mha_vip}"

    fi

}

create_replication_user() {

    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "CREATE USER IF NOT EXISTS '${replication_user}'@'${machine_slave_ip}' IDENTIFIED BY '${replication_password}';"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "GRANT ALL PRIVILEGES ON *.* TO '${replication_user}'@'${machine_slave_ip}' WITH GRANT OPTION;"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH PRIVILEGES;"

}

show_current_db_status() {
    echo -e "Master DB List"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "show databases;"

    echo -e "Current Master DB settings"
    docker exec ${master_container_name} cat /etc/mysql/my.cnf
}


_main() {

  echo "[SECURITY] Set .env 600 at all times."
  sudo chmod 600 .env

  echo "[SECURITY] Set my.cnf 999:1000 at all times (999 is 'mysql' user and 1000 is for the host user)"
  sudo chown -R 999:1000 ./master/log
  sudo chown 999:1000 ./master/my.cnf

  sudo chown -R root:1000 ../shares/.ssh

  # Set global variables BEFORE DOCKER IS UP
  cache_global_vars

  initialize_files

  create_host_folders_if_not_exists

  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    # To remove the image, down the container.
    docker-compose down
    docker image prune -f
    docker rmi master_db-master
  fi
  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker-compose build --no-cache || exit 1
  else
    docker-compose build || exit 1
  fi


  re_up_master

  cache_set_vip

  # If the following error comes up, that means the DB is not yet up, so we need to give it a proper time to be up.
  # ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' (2)
  echo -e "[NOTICE] Waiting for DB to be up..."

  wait_until_db_up "${master_container_name}" "${master_root_password}"

  # Create Master-Slave Replication User
  create_replication_user

  show_current_db_status

  #docker exec ${mha_container_name} sh -c 'rm -f /root/.ssh/known_hosts'
  docker exec ${master_container_name} sh -c 'service ssh restart'

}
_main
