#!/bin/bash
echo "[NOTICE] To prevent CRLF errors on Windows, CRLF->LF ... "
sudo sed -i -e "s/\r$//g" $(basename $0)
sleep 3
source ./util.sh

# pipefail
# If set, the return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status, or zero if all commands in the pipeline exit successfully. This option is disabled by default.
#set -eo pipefail
#set -eu
# Prevent 'bash' from matching null as string
#shopt -s nullglob

initialize_files() {
  # sudo rm -f ./master/etc/all-databases.sql
  # sudo rm -f ./slave/etc/all-databases.sql
  sudo rm -f ./mha-manager/work/app1.failover.complete
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

prepare_ssh_keys_none_separated_mode() {

  if [[ ${separated_mode} == false ]]; then

    echo "MHA - GENERATE SSH PUBLIC,PRIVATE KEYS"
    docker exec -it ${mha_container_name} /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh
    echo "MASTER - GENERATE SSH PUBLIC,PRIVATE KEYS"
    docker exec -it ${master_container_name} /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh
    echo "SLAVE - GENERATE SSH PUBLIC,PRIVATE KEYS"
    docker exec -it ${slave_container_name} /bin/bash /root/mha-ssh/scripts/ssh_generate_key.sh

    echo "MHA - PLACE PUBLIC KEYS FOR ALL CONTAINERS"
    docker exec -it ${mha_container_name} /bin/bash /root/mha-ssh/scripts/ssh_auth_keys.sh
    echo "MASTER - PLACE PUBLIC KEYS FOR ALL CONTAINERS"
    docker exec -it ${master_container_name} /bin/bash /root/mha-ssh/scripts/ssh_auth_keys.sh
    echo "SLAVE - PLACE PUBLIC KEYS FOR ALL CONTAINERS"
    docker exec -it ${slave_container_name} /bin/bash /root/mha-ssh/scripts/ssh_auth_keys.sh

    sleep 3

    ## SSH 키 적용
    echo "MHA - RESTART SSH"
    docker exec -it ${mha_container_name} service ssh restart
    echo "MASTER - RESTART SSH"
    docker exec -it ${master_container_name} service ssh restart
    echo "SLAVE - RESTART SSH"
    docker exec -it ${slave_container_name} service ssh restart

  fi
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

create_replication_user() {
  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "CREATE USER IF NOT EXISTS '${replication_user}'@'${machine_slave_ip}' IDENTIFIED BY '${replication_password}';"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "GRANT ALL PRIVILEGES ON *.* TO '${replication_user}'@'${machine_slave_ip}' WITH GRANT OPTION;"
    docker exec ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH PRIVILEGES;"
  fi

  if [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
    docker exec ${slave_container_name} mysql -uroot -p${master_root_password} -e "CREATE USER IF NOT EXISTS '${replication_user}'@'${machine_master_ip}' IDENTIFIED BY '${replication_password}';"
    docker exec ${slave_container_name} mysql -uroot -p${master_root_password} -e "GRANT ALL PRIVILEGES ON *.* TO '${replication_user}'@'${machine_master_ip}' WITH GRANT OPTION;"
    docker exec ${slave_container_name} mysql -uroot -p${master_root_password} -e "FLUSH PRIVILEGES;"
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

    echo -e "Point Slave to Master (IP : ${machine_master_ip}, Bin Log File : ${db_master_bin_log_file}, Bin Log File Pos : ${db_master_bin_log_pos})"

    if [[ ${separated_mode} == true ]]; then
      docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "CHANGE MASTER TO MASTER_HOST='${machine_master_ip}', MASTER_USER='${replication_user}', MASTER_PASSWORD='${replication_password}', MASTER_LOG_FILE='${db_master_bin_log_file}', MASTER_LOG_POS=${db_master_bin_log_pos}, GET_MASTER_PUBLIC_KEY=1, MASTER_PORT=${separated_mode_master_port};"
    else
      docker exec ${slave_container_name} mysql -uroot -p${slave_root_password} -e "CHANGE MASTER TO MASTER_HOST='${machine_master_ip}', MASTER_USER='${replication_user}', MASTER_PASSWORD='${replication_password}', MASTER_LOG_FILE='${db_master_bin_log_file}', MASTER_LOG_POS=${db_master_bin_log_pos}, GET_MASTER_PUBLIC_KEY=1;"
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

  echo "[NOTICE] Read-lock Master"
  docker exec ${mha_container_name} sh -c 'mysql -uroot -p'${master_root_password}' -h'${machine_master_ip}' -P'${machine_master_db_port}' -e "FLUSH TABLES WITH READ LOCK;"'

  echo "[NOTICE] Read-lock Slave"
  docker exec ${mha_container_name} sh -c 'mysql -uroot -p'${slave_root_password}' -h'${machine_slave_ip}' -P'${machine_slave_db_port}' -e "FLUSH TABLES WITH READ LOCK;"'

}

unlock_all() {

  echo "[NOTICE] Read-unlock Master"
  docker exec ${mha_container_name} sh -c 'mysql -uroot -p'${master_root_password}' -h'${machine_master_ip}' -P'${machine_master_db_port}' -e "UNLOCK TABLES;"'

  echo "[NOTICE] Read-unlock Slave"
  docker exec ${mha_container_name} sh -c 'mysql -uroot -p'${slave_root_password}' -h'${machine_slave_ip}' -P'${machine_slave_db_port}' -e "UNLOCK TABLES;"'

}

set_dynamic_env() {
  printf 'machine_master_ip='${machine_master_ip}'\nmachine_slave_ip='${machine_slave_ip}'\nmaster_network_interface_name='${master_network_interface_name}'\nslave_network_interface_name='${slave_network_interface_name}'\nmha_vip='${mha_vip} >./.dynamic_env
}

up_mha_manager() {
  set_dynamic_env
  docker-compose up -d mha-manager
}

set_mha_conf_after_cache_global_vars_after_d_up() {
  # Set MHA configuration
  # sed -i -E "s/(post_max_size\s*=\s*)[^\n\r]+/\1100M/" /usr/local/etc/php/php.ini
  sed -i -E 's/^(password=).*$/\1'${master_root_password}'/' ./mha-manager/conf/app1.conf
  sed -i -E 's/^(repl_user=).*$/\1'${replication_user}'/' ./mha-manager/conf/app1.conf
  sed -i -E 's/^(repl_password=).*$/\1'${replication_password}'/' ./mha-manager/conf/app1.conf
  sed -i -E -z 's/(\[server1\][\n\r\t\s]*hostname[\t\s]*=)[^\n\r]*/\1'${machine_master_ip}'/' ./mha-manager/conf/app1.conf
  sed -i -E -z 's/(\[server2\][\n\r\t\s]*hostname[\t\s]*=)[^\n\r]*/\1'${machine_slave_ip}'/' ./mha-manager/conf/app1.conf
}

set_mha_ssh_root_passwd() {
  # MHA SSH ROOT PASSWORD 설정
  echo "MHA : SSH ROOT PASSWORD 적용"
  docker exec -it ${mha_container_name} sh -c 'echo "root:'${mha_sshd_password}'" | chpasswd'
}

make_changes_to_mha_library() {
  docker exec -it ${mha_container_name} chmod 664 /usr/local/share/perl/5.26.1/MHA/NodeUtil.pm
  docker exec -it ${mha_container_name} sed -i -E -z "s/(\use warnings FATAL => 'all';[\n\r\t\s]*)/\1no warnings qw( redundant );/" /usr/local/share/perl/5.26.1/MHA/NodeUtil.pm
}

start_mha() {
  echo "START MHA MANAGER"
  docker exec -it ${mha_container_name} bash -c "nohup masterha_manager --conf=/etc/mha/app1.conf --last_failover_minute=1 &> /usr/local/mha/log/masterha_manager.log & sleep 5"
  docker exec -it ${mha_container_name} masterha_check_status --conf=/etc/mha/app1.conf
}

set_additional_envs() {
  if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then

    docker exec ${master_container_name} export machine_master_ip=${machine_master_ip}
    docker exec ${master_container_name} export machine_slave_ip=${machine_slave_ip}
    docker exec ${master_container_name} export master_network_interface_name=${master_network_interface_name}
    docker exec ${master_container_name} export mha_vip=${mha_vip}

  elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
    docker exec ${slave_container_name} export machine_master_ip=${machine_master_ip}
    docker exec ${slave_container_name} export machine_slave_ip=${machine_slave_ip}
    docker exec ${slave_container_name} export master_network_interface_name=${master_network_interface_name}
    docker exec ${slave_container_name} export slave_network_interface_name=${slave_network_interface_name}
    docker exec ${slave_container_name} export mha_vip=${mha_vip}

  elif [[ ${separated_mode_who_am_i} == "mha" || ${separated_mode} == false ]]; then
    docker exec ${mha_container_name} export machine_master_ip=${machine_master_ip}
    docker exec ${mha_container_name} export machine_slave_ip=${machine_slave_ip}
    docker exec ${mha_container_name} export master_network_interface_name=${master_network_interface_name}
    docker exec ${mha_container_name} export slave_network_interface_name=${slave_network_interface_name}
    docker exec ${mha_container_name} export mha_vip=${mha_vip}
  fi
}

_main() {

  echo "[SECURITY] Set .env 600 at all times."
  sudo chmod 600 .env

  # Set global variables BEFORE DOCKER IS UP
  cache_global_vars

  initialize_files

  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker image prune -f
    docker rmi 80_mha-manager
  fi
  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker-compose build --no-cache || exit 1
  else
    docker-compose build || exit 1
  fi

  up_mha_manager

  # MASTER ONLY
  create_replication_user

  show_current_db_status

  lock_all

  if [[ ${slave_emergency_recovery} == true ]]; then

    echo "[NOTICE] Create Master Back Up SQL"
    docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' -p '${machine_master_ssh_port}' "mysqldump -uroot -p'${master_root_password}' --all-databases --single-transaction > /var/tmp/all-databases.sql"'

    echo "[NOTICE]  Copy Master Data to Slave"
    docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_slave_ip}' -p '${machine_slave_ssh_port}' "mysql -uroot -p'${slave_root_password}' < /var/tmp/all-databases.sql"'

  fi

  if [[ ${master_emergency_recovery} == true ]]; then

    echo "[NOTICE] Create Slave Back Up SQL"
    docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_slave_ip}' -p '${machine_slave_ssh_port}' "mysqldump -uroot -p'${slave_root_password}' --all-databases --single-transaction > /var/tmp/all-databases.sql"'

    echo "[NOTICE] Copy Slave Data to Master"
    docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' -p '${machine_master_ssh_port}' "mysql -uroot -p'${master_root_password}' < /var/tmp/all-databases.sql"'

  fi

  # Set global variables AFTER DB IS UP
  # Master and Slave IPs are now set
  cache_global_vars_after_d_up
  # SLAVE ONLY
  connect_slave_to_master

  # set_additional_envs

  if [[ ${separated_mode} == false || ${separated_mode_who_am_i} == "mha" ]]; then

    set_mha_conf_after_cache_global_vars_after_d_up

    set_mha_ssh_root_passwd

    make_changes_to_mha_library

  fi

  check_slave_health

  unlock_all

  if [[ ${separated_mode} == false || ${separated_mode_who_am_i} == "mha" ]]; then

    echo "Remove 'app1.failover.complete' to start MHA"
    rm ./mha-manager/work/app1.failover.complete
    sleep 1
    start_mha

  fi

  # https://jhdatabase.tistory.com/19
}

check_ssh_validity() {
  echo "[NOTICE] Test SSH connections from MHA to ${1}"
  status=$(docker exec ${mha_container_name} sh -c 'exec ssh -o BatchMode=yes -o ConnectTimeout=5 root@'${1}' echo ok 2>&1')

  if [[ $status == ok ]]; then
    echo "${1} Valid"
  elif [[ $status == "Warning: Permanently added"* ]]; then
    echo "${1} Valid ($status)"
    exit 1
  elif [[ $status == "Permission denied"* ]]; then
    echo "[ERROR] ${1} invalid. Stopping... ($status)"
    exit 1
  else
    echo "[ERROR] ${1} invalid. Stopping... ($status)"
  fi
}

_main2() {

  echo "[SECURITY] Set .env 600 at all times."
  sudo chmod 600 .env

  sudo chown -R root:1000 ../shares/.ssh

  # Set global variables BEFORE DOCKER IS UP
  cache_global_vars

  initialize_files

  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker image prune -f
    docker rmi 80_mha-manager
  fi
  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker-compose build --no-cache || exit 1
  else
    docker-compose build || exit 1
  fi

  up_mha_manager

  # SSH Validity
  # Prevent the error "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"
  docker exec ${mha_container_name} sh -c 'rm -f /root/.ssh/known_hosts'
  bash ./commands/check-ssh-validity.sh

  lock_all

  if [[ ${slave_emergency_recovery} == true ]]; then

    echo "[NOTICE] Create Master Back Up SQL"
    # docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' -p '${machine_master_ssh_port}' "mysql -uroot -p'${master_root_password}' -e \"FLUSH TABLES WITH READ LOCK;\""'
    docker exec ${mha_container_name} sh -c 'mysqldump -uroot -p'${master_root_password}' -h'${machine_master_ip}' -P'${machine_master_db_port}' --all-databases --single-transaction > /var/tmp/all-databases.sql'

    echo "[NOTICE] Slave Docker-Compose down"
    docker exec ${mha_container_name} sh -c 'exec ssh -t root@'${machine_slave_ip}' -p '${machine_slave_ssh_port}' "cd '${machine_slave_project_root_path}' ; docker-compose down"'

    echo "[NOTICE] Remove Slave DB Data"
    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
    docker exec ${mha_container_name} sh -c 'exec ssh -t root@'${machine_slave_ip}' -p '${machine_slave_ssh_port}' "cd '${machine_slave_project_root_path}' ; mkdir -p '${machine_slave_project_root_path}'/backups/'${timestamp}' ; mv '${mysql_data_path_slave}' '${machine_slave_project_root_path}'/backups/'${timestamp}'"'

    echo -e "[NOTICE] Restart Slave DB"
    docker exec ${mha_container_name} sh -c 'exec ssh -t root@'${machine_slave_ip}' -p '${machine_slave_ssh_port}' "cd '${machine_slave_project_root_path}' ; bash '${machine_slave_project_root_path}'/run.sh"'

    echo "[NOTICE] Copy Master Data to Slave"
    docker exec ${mha_container_name} sh -c 'mysql -uroot -p'${slave_root_password}' -h'${machine_slave_ip}' -P'${machine_slave_db_port}' < /var/tmp/all-databases.sql'

  fi

  if [[ ${master_emergency_recovery} == true ]]; then

    echo "[NOTICE] Create Slave Back Up SQL"
    docker exec ${mha_container_name} sh -c 'mysqldump -uroot -p'${slave_root_password}' -h'${machine_slave_ip}' -P'${machine_slave_db_port}' --all-databases --single-transaction > /var/tmp/all-databases.sql'

    echo "[NOTICE] Master Docker-Compose down"
    docker exec ${mha_container_name} sh -c 'exec ssh -t root@'${machine_master_ip}' -p '${machine_master_ssh_port}' "cd '${machine_master_project_root_path}' ; docker-compose down"'

    echo "[NOTICE] Remove Master DB Data"
    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
    docker exec ${mha_container_name} sh -c 'exec ssh -t root@'${machine_master_ip}' -p '${machine_master_ssh_port}' "cd '${machine_master_project_root_path}' ; mkdir -p '${machine_master_project_root_path}'/backups/'${timestamp}' ; mv '${mysql_data_path_master}' '${machine_master_project_root_path}'/backups/'${timestamp}'"'

    echo -e "[NOTICE] Restart Master DB"
    docker exec ${mha_container_name} sh -c 'exec ssh -t root@'${machine_master_ip}' -p '${machine_master_ssh_port}' "cd '${machine_master_project_root_path}' ; bash '${machine_master_project_root_path}'/run.sh"'

    echo "[NOTICE] Copy Slave Data to Master"
    docker exec ${mha_container_name} sh -c 'mysql -uroot -p'${master_root_password}' -h'${machine_master_ip}' -P'${machine_master_db_port}' < /var/tmp/all-databases.sql'

  fi

  unlock_all

  # (Re)start Master
  #docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_master_ip}' "bash '${machine_master_project_root_path}'/run.sh"'

  # (Re)start Slave
  #docker exec ${mha_container_name} sh -c 'exec ssh root@'${machine_slave_ip}' "bash '${machine_slave_project_root_path}'/run.sh"'

}

_main2
