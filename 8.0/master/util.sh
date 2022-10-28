#!/bin/bash

cache_global_vars() {
  # Read .env
  master_emergency_recovery=$(get_value_from_env "MASTER_EMERGENCY_RECOVERY")
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
  mha_container_name=$(get_value_from_env "MHA_CONTAINER_NAME")

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

get_value_from_env(){
  value=''
  re='^[[:space:]]*('${1}'[[:space:]]*=[[:space:]]*)(.+)[[:space:]]*$'

  while IFS= read -r line; do
     if [[ $line =~ $re ]]; then                       # match regex
        #declare -p BASH_REMATCH
        value=${BASH_REMATCH[2]}
     fi
                                      # print each line
  done < <(grep "" .env)  # To read the last line

  echo ${value} # return.
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


wait_until_db_up_remote() {

  echo -e "[NOTICE] Checking DB ("${1}") is up."

  for retry_count in {1..10}; do
    db_up=$(docker exec ${3} mysql -uroot -h${1} -p${2} -e "SELECT 1" -s | tail -n 1 | awk {'print $1'}) || db_up=0
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