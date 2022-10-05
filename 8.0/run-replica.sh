#!/bin/bash
echo "[NOTICE] To prevent CRLF errors on Windows, CRLF->LF ... "
sudo sed -i -e "s/\r$//g" $(basename $0)
sudo bash ./prevent-crlf.sh
sleep 3
source ./util.sh

# pipefail
# If set, the return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status, or zero if all commands in the pipeline exit successfully. This option is disabled by default.
#set -eo pipefail
#set -eu
# Prevent 'bash' from matching null as string
#shopt -s nullglob

cache_global_vars() {
  # Read .env
  slave_emergency_recovery=$(get_value_from_env "SLAVE_EMERGENCY_RECOVERY")
  docker_layer_corruption_recovery=$(get_value_from_env "DOCKER_LAYER_CORRUPTION_RECOVERY")

  docker_mha_ip=$(get_value_from_env "DOCKER_MHA_IP")
  docker_master_ip=$(get_value_from_env "DOCKER_MASTER_IP")
  docker_slave_ip=$(get_value_from_env "DOCKER_SLAVE_IP")
  docker_mha_vip=$(get_value_from_env "DOCKER_MHA_VIP")

  separated_mode=$(get_value_from_env "SEPARATED_MODE")
  separated_mode_who_am_i=$(get_value_from_env "SEPARATED_MODE_WHO_AM_I")
  separated_mode_master_ip=$(get_value_from_env "SEPARATED_MODE_MASTER_IP")
  separated_mode_slave_ip=$(get_value_from_env "SEPARATED_MODE_SLAVE_IP")
  separated_mode_master_port=$(get_value_from_env "SEPARATED_MODE_MASTER_PORT")
  separated_mode_slave_port=$(get_value_from_env "SEPARATED_MODE_SLAVE_PORT")
  separated_mode_mha_ip=$(get_value_from_env "SEPARATED_MODE_MHA_IP")
  separated_mode_mha_vip=$(get_value_from_env "SEPARATED_MODE_MHA_VIP")

  master_container_name=$(get_value_from_env "MASTER_CONTAINER_NAME")
  slave_container_name=$(get_value_from_env "SLAVE_CONTAINER_NAME")

  mysql_data_path_master=$(get_value_from_env "MYSQL_DATA_PATH_MASTER")
  mysql_log_path_master=$(get_value_from_env "MYSQL_LOG_PATH_MASTER")
  mysql_file_path_master=$(get_value_from_env "MYSQL_FILE_PATH_MASTER")
  mysql_etc_path_master=$(get_value_from_env "MYSQL_ETC_PATH_MASTER")

  mysql_data_path_slave=$(get_value_from_env "MYSQL_DATA_PATH_SLAVE")
  mysql_log_path_slave=$(get_value_from_env "MYSQL_LOG_PATH_SLAVE")
  mysql_file_path_slave=$(get_value_from_env "MYSQL_FILE_PATH_SLAVE")
  mysql_etc_path_slave=$(get_value_from_env "MYSQL_ETC_PATH_SLAVE")

  master_root_password=$(get_value_from_env "MYSQL_ROOT_PASSWORD")
  slave_root_password=$(get_value_from_env "MYSQL_ROOT_PASSWORD")

  replication_user=$(get_value_from_env "MYSQL_REPLICATION_USER_MASTER")
  replication_password=$(get_value_from_env "MYSQL_REPLICATION_USER_PASSWORD_MASTER")

  expose_port_master=$(get_value_from_env "EXPOSE_PORT_MASTER")

  mha_sshd_password=$(get_value_from_env "MHA_SSHD_PASSWORD")

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      db_master_ip_from_the_others=${docker_master_ip}
    elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode_who_am_i} == "mha" ]]; then
      db_master_ip_from_the_others=${separated_mode_master_ip}
    fi
  elif [[ ${separated_mode} == false ]]; then
    db_master_ip_from_the_others=${docker_master_ip}
  else
    echo "[ERROR] SEPARATED_MODE on .env : empty"
    exit 1
  fi

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode_who_am_i} == "mha" ]]; then
      db_slave_ip_from_the_others=${separated_mode_slave_ip}
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      # echo $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${slave_container_name})
      db_slave_ip_from_the_others=${docker_slave_ip}
    fi
  elif [[ ${separated_mode} == false ]]; then
    db_slave_ip_from_the_others=${docker_slave_ip}
  else
    echo "[ERROR] SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

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

re_up_master_slave() {

  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker image prune -f
    docker rmi 80_db-master
    docker rmi 80_db-slave
  fi

  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker-compose build --no-cache || exit 1
  else
    docker-compose build || exit 1
  fi

  docker-compose down

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      docker-compose up -d db-master
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      docker-compose up -d db-slave
    fi
  elif [[ ${separated_mode} == false ]]; then
    docker-compose up -d db-master
    docker-compose up -d db-slave
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi

}

wait_until_db_up() {

  echo -e "[NOTICE] Checking DB ("${1}") is up."

  for retry_count in {1..10}; do
    db_up=$(docker exec "${1}" mysql -uroot -p${2} -e "SELECT 1" -s | tail -n 1 | awk {'print $1'}) || db_up=0
    db_up_found=$(echo ${db_up} | egrep '^[^0-9]*1[^0-9]*$' | wc -l)

    if [[ ${db_up_found} -ge 1 ]]; then
      echo -e "[SUCCESS] DB ("${1}") is up."
      break
    else
      echo "Retrying..."
    fi

    if [[ ${retry_count} -eq 10 ]]; then
      echo "10 retries have failed."
      break
    fi

    echo "> 10 retries every 5 seconds"
    sleep 5
  done
}

get_db_master_bin_log_file() {
  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      echo $(docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $1'})
    elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode_who_am_i} == "mha" ]]; then
      echo $(docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -h${separated_mode_master_ip} -P${separated_mode_master_port} -e "show master status" -s | tail -n 1 | awk {'print $1'})
    fi
  elif [[ ${separated_mode} == false ]]; then
    echo $(docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $1'})
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

get_db_master_bin_log_pos() {
  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      echo $(docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $2'})
    elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode_who_am_i} == "mha" ]]; then
      echo $(docker exec ${slave_container_name} mysql -uroot -p${master_root_password} -h${separated_mode_master_ip} -P${separated_mode_master_port} -e "show master status" -s | tail -n 1 | awk {'print $2'})
    fi
  elif [[ ${separated_mode} == false ]]; then
    echo $(docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $2'})
  else
    echo "[ERROR] SEPARATED_MODE on .env : empty (get_db_master_bin_log_pos)"
    exit 1
  fi
}

cache_global_vars_after_d_up() {

  db_master_bin_log_file=$(get_db_master_bin_log_file)
  db_master_bin_log_pos=$(get_db_master_bin_log_pos)

}

cache_set_vip() {

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      master_network_interface_name=$(ip addr show | awk '/inet.*brd/{print $NF; exit}' || exit 1)
      mha_vip=${separated_mode_mha_vip}

      echo "Set Master VIP"
      ifconfig ${master_network_interface_name}:1 ${mha_vip}
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      slave_network_interface_name=$(ip addr show | awk '/inet.*brd/{print $NF; exit}'|| exit 1)
      mha_vip=${separated_mode_mha_vip}
    elif [[ ${separated_mode_who_am_i} == "mha" ]]; then
      mha_vip=${separated_mode_mha_vip}
    fi
  elif [[ ${separated_mode} == false ]]; then
    master_network_interface_name=$(docker exec ${master_container_name} ip addr show | awk '/inet.*brd/{print $NF; exit}' || exit 1)
    slave_network_interface_name=$(docker exec ${slave_container_name} ip addr show | awk '/inet.*brd/{print $NF; exit}' || exit 1)
    mha_vip=10.3.0.12

    echo "Set Master VIP"
    docker exec ${master_container_name} ifconfig ${master_network_interface_name}:1 ${mha_vip}
  else
    echo "[ERROR] SEPARATED_MODE on .env : empty (cache_set_vip)"
    exit 1
  fi

}

create_replication_user() {
  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "CREATE USER IF NOT EXISTS '${replication_user}'@'${db_slave_ip_from_the_others}' IDENTIFIED BY '${replication_password}';"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "GRANT ALL PRIVILEGES ON *.* TO '${replication_user}'@'${db_slave_ip_from_the_others}' WITH GRANT OPTION;"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH PRIVILEGES;"
  fi
}

show_current_db_status() {
  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
    echo -e "Master DB List"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "show databases;"
  elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
    echo -e "Slave DB List"
    docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "show databases;"
  fi

  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
    echo -e "Current Master DB settings"
    docker exec ${master_container_name} cat /etc/mysql/my.cnf
  elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
    echo -e "Current Slave DB settings"
    docker exec ${slave_container_name} cat /etc/mysql/my.cnf
  fi
}

connect_slave_to_master() {
  if [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then

    echo -e "Stopping Slave..."
    docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "STOP SLAVE;"
    docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "RESET SLAVE ALL;"

    echo -e "Point Slave to Master (IP : ${db_master_ip_from_the_others}, Bin Log File : ${db_master_bin_log_file}, Bin Log File Pos : ${db_master_bin_log_pos})"

    if [[ ${separated_mode} == true ]]; then
      docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "CHANGE MASTER TO MASTER_HOST='${db_master_ip_from_the_others}', MASTER_USER='${replication_user}', MASTER_PASSWORD='${replication_password}', MASTER_LOG_FILE='${db_master_bin_log_file}', MASTER_LOG_POS=${db_master_bin_log_pos}, GET_MASTER_PUBLIC_KEY=1, MASTER_PORT=${separated_mode_master_port};"
    else
      docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "CHANGE MASTER TO MASTER_HOST='${db_master_ip_from_the_others}', MASTER_USER='${replication_user}', MASTER_PASSWORD='${replication_password}', MASTER_LOG_FILE='${db_master_bin_log_file}', MASTER_LOG_POS=${db_master_bin_log_pos}, GET_MASTER_PUBLIC_KEY=1;"
    fi

    echo -e "Starting Slave..."
    docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "START SLAVE;"
    echo -e "Current Replication Status"
    docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "SHOW SLAVE STATUS\G;"
  fi
}

slave_health() {
  echo -e "Checking replication health..."
  status=$(docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "SHOW SLAVE STATUS\G")
  echo "$status" | egrep 'Slave_(IO|SQL)_Running:|Seconds_Behind_Master:|Last_.*_Error:' | grep -v "Error: $"
  if ! echo "$status" | grep -qs "Slave_IO_Running: Yes" ||
    ! echo "$status" | grep -qs "Slave_SQL_Running: Yes" ||
    ! echo "$status" | grep -qs "Seconds_Behind_Master: 0"; then
    echo ERROR: Replication is not healthy.
    return 1
  fi
  return 0
}

check_slave_health() {
  counter=0
  while ! slave_health; do
    if ((counter >= 5)); then
      echo ERROR: Replication is NOT healthy.
      exit 1
    fi
    let counter=counter+1
    sleep 2
  done

  echo SUCCESS: Replication is healthy.
}

lock_all() {
  echo -e "Lock all the tables in Master"
  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH TABLES WITH READ LOCK;"
  elif [[ ${separated_mode_who_am_i} == "slave" && ${separated_mode} == true ]]; then
    docker exec ${slave_container_name} mysql -uroot -p${master_root_password} -h${separated_mode_master_ip} -P${separated_mode_master_port} -e "FLUSH TABLES WITH READ LOCK;"
  fi
}

unlock_all() {
  echo -e "Unlock all the tables in Master"
  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "UNLOCK TABLES;"
  elif [[ ${separated_mode_who_am_i} == "slave" && ${separated_mode} == true ]]; then
    docker exec ${slave_container_name} mysql -uroot -p${master_root_password} -h${separated_mode_master_ip} -P${separated_mode_master_port} -e "UNLOCK TABLES;"
  fi
}

up_mha_manager() {

  export db_master_ip_from_the_others=${db_master_ip_from_the_others}
  export db_slave_ip_from_the_others=${db_slave_ip_from_the_others}
  export master_network_interface_name=${master_network_interface_name}
  export slave_network_interface_name=${slave_network_interface_name}
  export mha_vip=${mha_vip}

  printf 'db_master_ip_from_the_others='${db_master_ip_from_the_others}'\ndb_slave_ip_from_the_others='${db_slave_ip_from_the_others}'\nmaster_network_interface_name='${master_network_interface_name}'\nslave_network_interface_name='${slave_network_interface_name}'\nmha_vip='${mha_vip} > ./.dynamic_env

  docker-compose up -d mha-manager
}

set_mha_conf_after_cache_global_vars_after_d_up() {
  # Set MHA configuration
  # sed -i -E "s/(post_max_size\s*=\s*)[^\n\r]+/\1100M/" /usr/local/etc/php/php.ini
  sed -i -E 's/^(password=).*$/\1'${master_root_password}'/' ./mha-manager/conf/app1.conf
  sed -i -E 's/^(repl_user=).*$/\1'${replication_user}'/' ./mha-manager/conf/app1.conf
  sed -i -E 's/^(repl_password=).*$/\1'${replication_password}'/' ./mha-manager/conf/app1.conf
  sed -i -E -z 's/(\[server1\][\n\r\t\s]*hostname[\t\s]*=)[^\n\r]*/\1'${db_master_ip_from_the_others}'/' ./mha-manager/conf/app1.conf
  sed -i -E -z 's/(\[server2\][\n\r\t\s]*hostname[\t\s]*=)[^\n\r]*/\1'${db_slave_ip_from_the_others}'/' ./mha-manager/conf/app1.conf
}

prepare_mha_ssh_keys() {

  echo "MHA - GENERATE SSH PUBLIC,PRIVATE KEYS"
  docker exec -it mha-manager /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh
  echo "MASTER - GENERATE SSH PUBLIC,PRIVATE KEYS"
  docker exec -it ${master_container_name} /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh
  echo "SLAVE - GENERATE SSH PUBLIC,PRIVATE KEYS"
  docker exec -it ${slave_container_name} /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh

  echo "MHA - PLACE PUBLIC KEYS FOR ALL CONTAINERS"
  docker exec -it mha-manager /bin/bash /root/mha-ssh/scripts/ssh_auth_keys.sh
  echo "MASTER - PLACE PUBLIC KEYS FOR ALL CONTAINERS"
  docker exec -it ${master_container_name} /bin/bash /root/mha-ssh/scripts/ssh_auth_keys.sh
  echo "SLAVE - PLACE PUBLIC KEYS FOR ALL CONTAINERS"
  docker exec -it ${slave_container_name} /bin/bash /root/mha-ssh/scripts/ssh_auth_keys.sh

  sleep 3

  ## SSH 키 적용
  echo "MHA - RESTART SSH"
  docker exec -it mha-manager service ssh restart
  echo "MASTER - RESTART SSH"
  docker exec -it ${master_container_name} service ssh restart
  echo "SLAVE - RESTART SSH"
  docker exec -it ${slave_container_name} service ssh restart
}

set_mha_ssh_root_passwd() {
  # MHA SSH ROOT PASSWORD 설정
  echo "MHA : SSH ROOT PASSWORD 적용"
  docker exec -it mha-manager sh -c 'echo "root:'${mha_sshd_password}'" | chpasswd'
}

make_changes_to_mha_library() {
  docker exec -it mha-manager chmod 664 /usr/local/share/perl/5.26.1/MHA/NodeUtil.pm
  docker exec -it mha-manager sed -i -E -z "s/(\use warnings FATAL => 'all';[\n\r\t\s]*)/\1no warnings qw( redundant );/" /usr/local/share/perl/5.26.1/MHA/NodeUtil.pm
}

start_mha() {
  echo "START MHA MANAGER"
  docker exec -it mha-manager bash -c "nohup masterha_manager --conf=/etc/mha/app1.conf --last_failover_minute=1 &> /usr/local/mha/log/masterha_manager.log & sleep 5"
  docker exec -it mha-manager masterha_check_status --conf=/etc/mha/app1.conf
}

set_additional_envs() {
    if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then

      docker exec ${master_container_name} export db_master_ip_from_the_others=${db_master_ip_from_the_others}
      docker exec ${master_container_name} export db_slave_ip_from_the_others=${db_slave_ip_from_the_others}
      docker exec ${master_container_name} export master_network_interface_name=${master_network_interface_name}
      docker exec ${master_container_name} export mha_vip=${mha_vip}

    elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
      docker exec ${slave_container_name} export db_master_ip_from_the_others=${db_master_ip_from_the_others}
      docker exec ${slave_container_name} export db_slave_ip_from_the_others=${db_slave_ip_from_the_others}
      docker exec ${slave_container_name} export master_network_interface_name=${master_network_interface_name}
      docker exec ${slave_container_name} export slave_network_interface_name=${slave_network_interface_name}
      docker exec ${slave_container_name} export mha_vip=${mha_vip}

    elif [[ ${separated_mode_who_am_i} == "mha" || ${separated_mode} == false ]]; then
      docker exec mha-manager export db_master_ip_from_the_others=${db_master_ip_from_the_others}
      docker exec mha-manager export db_slave_ip_from_the_others=${db_slave_ip_from_the_others}
      docker exec mha-manager export master_network_interface_name=${master_network_interface_name}
      docker exec mha-manager export slave_network_interface_name=${slave_network_interface_name}
      docker exec mha-manager export mha_vip=${mha_vip}
    fi
}

_main() {

  echo "[SECURITY] Set .env 600 at all times."
  sudo chmod 600 .env

  echo "[SECURITY] Set my.cnf 999:1000 at all times (1000 is for the Host User)"
  sudo chown 999:1000 ./master/my.cnf
  sudo chown 999:1000 ./slave/my.cnf

  # Set global variables BEFORE DOCKER IS UP
  cache_global_vars

  if [[ ${slave_emergency_recovery} == true && ${separated_mode} == false ]]; then

    docker-compose down

    sudo rm -rf ${mysql_data_path_slave}

    echo -e "[IMPORTANT] Removed all slave data as 'slave_emergency_recovery' is on."
  fi
  create_host_folders_if_not_exists

  re_up_master_slave

  # If the following error comes up, that means the DB is not yet up, so we need to give it a proper time to be up.
  # ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' (2)
  echo -e "Waiting for DB to be up..."

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      wait_until_db_up "${master_container_name}" "${master_root_password}"
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      wait_until_db_up "${slave_container_name}" "${slave_root_password}"
    fi
  elif [[ ${separated_mode} == false ]]; then
    wait_until_db_up "${master_container_name}" "${master_root_password}"
    wait_until_db_up "${slave_container_name}" "${slave_root_password}"
  fi

  # Now DB is up from this point on....

  # MASTER ONLY
  create_replication_user

  show_current_db_status

  lock_all

  if [[ ${slave_emergency_recovery} == true && ${separated_mode} == false ]]; then

    echo "Create Master Back Up SQL"
    docker exec ${master_container_name} sh -c 'exec mysqldump -uroot -p'${master_root_password}' --all-databases --single-transaction > /var/tmp/all-databases.sql'

    echo "Move SQL"
    sudo cp -a ${mysql_etc_path_master}/all-databases.sql ${mysql_etc_path_slave}

    echo "Copy Master Data to Slave"
    docker exec ${slave_container_name} sh -c 'exec mysql -uroot -p'${slave_root_password}' < /var/tmp/all-databases.sql'

    #echo "Change ROOT password"
    #docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "ALTER USER 'root'@'%' IDENTIFIED BY '${slave_root_password}';"
    # docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
    # docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "FLUSH PRIVILEGES;"
    #docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e  "FLUSH TABLES WITH READ LOCK;"
    #docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e  "UNLOCK TABLES;"

  fi

  # Set global variables AFTER DB IS UP
  # Master and Slave IPs are now set
  cache_global_vars_after_d_up
  # SLAVE ONLY
  connect_slave_to_master

  cache_set_vip

  # set_additional_envs

  if [[ ${separated_mode} == false || ${separated_mode_who_am_i} == "mha" ]]; then

    up_mha_manager

    set_mha_conf_after_cache_global_vars_after_d_up

    set_mha_ssh_root_passwd

    prepare_mha_ssh_keys

    make_changes_to_mha_library

  fi

  check_slave_health

  unlock_all

  if [[ ${separated_mode} == false || ${separated_mode_who_am_i} == "mha" ]]; then

    start_mha

  fi

  # https://jhdatabase.tistory.com/19
}
_main
