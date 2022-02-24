#!/bin/bash

# pipefail
# If set, the return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status, or zero if all commands in the pipeline exit successfully. This option is disabled by default.
#set -eo pipefail
#set -eu
# Prevent 'bash' from matching null as string
#shopt -s nullglob

# Prevent collision in reading shell scripts.
git config core.autocrlf false

source ./util.sh

cache_global_vars() {
  # Read .env
  separated_mode=$(get_value_from_env "SEPARATED_MODE")
  separated_mode_who_am_i=$(get_value_from_env "SEPARATED_MODE_WHO_AM_I")
  separated_mode_master_ip=$(get_value_from_env "SEPARATED_MODE_MASTER_IP")
  separated_mode_slave_ip=$(get_value_from_env "SEPARATED_MODE_SLAVE_IP")
  separated_mode_master_port=$(get_value_from_env "SEPARATED_MODE_MASTER_PORT")
  separated_mode_slave_port=$(get_value_from_env "SEPARATED_MODE_SLAVE_PORT")

  master_container_name=$(get_value_from_env "MASTER_CONTAINER_NAME")
  slave_container_name=$(get_value_from_env "SLAVE_CONTAINER_NAME")

  mysql_data_path_master=$(get_value_from_env "MYSQL_DATA_PATH_MASTER")
  mysql_log_path_master=$(get_value_from_env "MYSQL_LOG_PATH_MASTER")
  mysql_data_path_slave=$(get_value_from_env "MYSQL_DATA_PATH_SLAVE")
  mysql_log_path_slave=$(get_value_from_env "MYSQL_LOG_PATH_SLAVE")

  master_root_password=$(get_value_from_env "MYSQL_ROOT_PASSWORD_MASTER")
  slave_root_password=$(get_value_from_env "MYSQL_ROOT_PASSWORD_SLAVE")

  replication_user=$(get_value_from_env "MYSQL_REPLICATION_USER_MASTER")
  replication_password=$(get_value_from_env "MYSQL_REPLICATION_USER_PASSWORD_MASTER")

  expose_port_master=$(get_value_from_env "EXPOSE_PORT_MASTER")
}

create_master_volumes_if_not_exists() {

  if [ -z "$mysql_data_path_master" ]; then echo "MYSQL_DATA_PATH_MASTER on .env : empty" && exit 1; fi
  if [ -z "$mysql_log_path_master" ]; then echo "MYSQL_LOG_PATH_MASTER on .env : empty" && exit 1; fi

  if [[ -d ${mysql_data_path_master} ]]; then
    echo "The directory of 'MYSQL_DATA_PATH_MASTER' already exists."
  else
    sudo mkdir -p ${mysql_data_path_master}
    echo "The directory of 'MYSQL_DATA_PATH_MASTER' has been created."
  fi

  if [[ -d ${mysql_log_path_master} ]]; then
    echo "The directory of 'MYSQL_LOG_PATH_MASTER' already exists."
  else
    sudo mkdir -p ${mysql_log_path_master}
    echo "The directory of 'MYSQL_LOG_PATH_MASTER' has been created."
  fi

  # mysql:mysql does not work only 999:999 works
  # https://stackoverflow.com/a/67775426/7344596
  sudo chown -R 999:999 ${mysql_data_path_master} ${mysql_log_path_master}

}

create_slave_volumes_if_not_exists() {

  if [ -z "$mysql_data_path_slave" ]; then echo "MYSQL_DATA_PATH_SLAVE on .env : empty" && exit 1; fi
  if [ -z "$mysql_log_path_slave" ]; then echo "MYSQL_LOG_PATH_SLAVE on .env : empty" && exit 1; fi

  if [[ -d ${mysql_data_path_slave} ]]; then
    echo "The directory of 'MYSQL_DATA_PATH_SLAVE' already exists."
  else
    sudo mkdir -p ${mysql_data_path_slave}
    echo "The directory of 'MYSQL_DATA_PATH_SLAVE' has been created."
  fi

  if [[ -d ${mysql_log_path_slave} ]]; then
    echo "The directory of 'MYSQL_LOG_PATH_SLAVE' already exists."
  else
    sudo mkdir -p ${mysql_log_path_slave}
    echo "The directory of 'MYSQL_LOG_PATH_SLAVE' has been created."
  fi

  # mysql:mysql does not work only 999:999 works
  # https://stackoverflow.com/a/67775426/7344596
  sudo chown -R 999:999 ${mysql_data_path_slave} ${mysql_log_path_slave}

}

prepare_volumes() {

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      create_master_volumes_if_not_exists
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      create_slave_volumes_if_not_exists
    fi
  elif [[ ${separated_mode} == false ]]; then
    create_master_volumes_if_not_exists
    create_slave_volumes_if_not_exists
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

restart_docker() {

  docker-compose down

  docker-compose build --no-cache || (echo "Check if your docker is available." && exit 1)

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      docker-compose run -d --service-ports db-master
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      docker-compose run -d --service-ports db-slave
    fi
  elif [[ ${separated_mode} == false ]]; then
    docker-compose up -d
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi

}

wait_until_db_up() {

  echo -e "Checking DB ("${1}") is up."

  for retry_count in {1..10}; do
    db_up=$(docker exec -it "${1}" mysql -uroot -p${2} -e "SELECT 1" -s | tail -n 1 | awk {'print $1'}) || db_up=0
    db_up_found=$(echo ${db_up} | egrep '^[^0-9]*1[^0-9]*$' | wc -l)

    if [[ ${db_up_found} -ge 1 ]]; then
      echo -e "DB ("${1}") is up."
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

get_db_master_ip() {

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      echo $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${master_container_name})
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      echo ${separated_mode_master_ip}
    fi
  elif [[ ${separated_mode} == false ]]; then
    echo $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${master_container_name})
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

get_db_slave_ip() {

  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      echo ${separated_mode_slave_ip}
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      echo $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${slave_container_name})
    fi
  elif [[ ${separated_mode} == false ]]; then
    echo $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${slave_container_name})
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

get_db_master_bin_log_file() {
  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      echo $(docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $1'})
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      echo $(docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -h${separated_mode_master_ip} -p${separated_mode_master_port} -e "show master status" -s | tail -n 1 | awk {'print $1'})
    fi
  elif [[ ${separated_mode} == false ]]; then
    echo $(docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $1'})
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

get_db_master_bin_log_pos() {
  if [[ ${separated_mode} == true ]]; then
    if [[ ${separated_mode_who_am_i} == "master" ]]; then
      echo $(docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $2'})
    elif [[ ${separated_mode_who_am_i} == "slave" ]]; then
      echo $(docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -h${separated_mode_master_ip} -p${separated_mode_master_port} -e "show master status" -s | tail -n 1 | awk {'print $2'})
    fi
  elif [[ ${separated_mode} == false ]]; then
    echo $(docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "show master status" -s | tail -n 1 | awk {'print $2'})
  else
    echo "SEPARATED_MODE on .env : empty"
    exit 1
  fi
}

cache_global_vars_after_d_up() {
  db_master_ip=$(get_db_master_ip)
  db_slave_ip=$(get_db_slave_ip)
  db_master_bin_log_file=$(get_db_master_bin_log_file)
  db_master_bin_log_pos=$(get_db_master_bin_log_pos)
}

create_replication_user(){
    if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
      docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "CREATE USER IF NOT EXISTS '${replication_user}'@'${db_slave_ip}' IDENTIFIED BY '${replication_password}';"
      docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "GRANT ALL PRIVILEGES ON *.* TO '${replication_user}'@'${db_slave_ip}' WITH GRANT OPTION;"
      docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH PRIVILEGES;"
      docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "FLUSH TABLES WITH READ LOCK;"
      docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "UNLOCK TABLES;"
    fi
}

show_current_db_status(){
    if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
      echo -e "Master DB List"
      docker exec -it ${master_container_name} mysql -uroot -p${master_root_password} -e "show databases;"
    elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
      echo -e "Slave DB List"
      docker exec -it ${slave_container_name} mysql -uroot -p${slave_root_password} -e "show databases;"
    fi

    if [[ ${separated_mode_who_am_i} == "master" || ${separated_mode} == false ]]; then
      echo -e "Current Master DB settings"
      docker exec -it ${master_container_name} cat /etc/mysql/my.cnf
    elif [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
      echo -e "Current Slave DB settings"
      docker exec -it ${slave_container_name} cat /etc/mysql/my.cnf
    fi
}

connect_slave_to_master(){
    if [[ ${separated_mode_who_am_i} == "slave" || ${separated_mode} == false ]]; then
      echo -e "Stopping Slave..."
      docker exec -it ${slave_container_name} mysql -uroot -p${slave_root_password} -e "STOP SLAVE;"
      docker exec -it ${slave_container_name} mysql -uroot -p${slave_root_password} -e "RESET SLAVE ALL;"
      echo -e "Point Slave to Master (IP : ${db_master_ip}, Bin Log File : ${db_master_bin_log_file}, , Bin Log File Pos : ${db_master_bin_log_pos})"
      docker exec -it ${slave_container_name} mysql -uroot -p${slave_root_password} -e "CHANGE MASTER TO MASTER_HOST='${db_master_ip}', MASTER_USER='${replication_user}', MASTER_PASSWORD='${replication_password}', MASTER_LOG_FILE='${db_master_bin_log_file}', MASTER_LOG_POS=${db_master_bin_log_pos}, GET_MASTER_PUBLIC_KEY=1;"
      echo -e "Starting Slave..."
      docker exec -it ${slave_container_name} mysql -uroot -p${slave_root_password} -e "START SLAVE;"
      echo -e "Current Replication Status"
      docker exec -it ${slave_container_name} mysql -uroot -p${slave_root_password} -e "SHOW SLAVE STATUS\G;"
    fi
}


_main() {

  # Set global variables BEFORE DOCKER IS UP
  cache_global_vars

  prepare_volumes

  restart_docker

  # If the following error comes up, that means the DB is not yet up, so we need to give it a proper time to be up.
  # ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' (2)
  echo -e "Waiting for DB to be up..."
  wait_until_db_up "${master_container_name}" "${master_root_password}"
  wait_until_db_up "${slave_container_name}" "${slave_root_password}"

  # Set global variables AFTER DB IS UP
  cache_global_vars_after_d_up

  # MASTER ONLY
  create_replication_user

  # docker exec -it ${master_container_name} mysqldump -uroot -ppassword –all-databases –master-data > /var/tmp/data.sql

  # docker exec -it ${slave_container_name} rm -rf /var/lib/mysql/*
  # docker exec -it ${slave_container_name} mysqld -uroot -ppassword --initialize-insecure --basedir=/usr/ --datadir=/var/lib/mysql --user=mysql
  # docker exec -it ${slave_container_name} mysqldump -uroot -ppassword < /var/tmp/data.sql

  show_current_db_status

  # SLAVE ONLY
  connect_slave_to_master

}
_main
