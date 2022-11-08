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
  sudo rm -f ./slave/etc/all-databases.sql
}

create_host_folders_if_not_exists() {

  arr_variable=("$mysql_data_path_slave" "$mysql_log_path_slave" "$mysql_file_path_slave" "$mysql_etc_path_slave")

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

re_up_slave() {

  docker-compose down
  docker-compose up -d db-slave

}

_main() {

  echo "[SECURITY] Set .env 600 at all times."
  sudo chmod 600 .env

  echo "[SECURITY] Set my.cnf 999:1000 at all times (999 is 'mysql' user and 1000 is for the host user)"
  sudo chown -R 999:1000 ./slave/log
  sudo chown 999:1000 ./slave/my.cnf

  sudo chown -R root:1000 ../shares/.ssh

  # Set global variables BEFORE DOCKER IS UP
  cache_global_vars

  initialize_files

  create_host_folders_if_not_exists

  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker image prune -f
    docker rmi 80_db-slave
  fi
  if [[ ${docker_layer_corruption_recovery} == true ]]; then
    docker-compose build --no-cache || exit 1
  else
    docker-compose build || exit 1
  fi

  if [[ ${slave_emergency_recovery} == true ]]; then
    docker-compose down
    sudo rm -rf ${mysql_data_path_slave}
    echo -e "[IMPORTANT] Removed all slave data as 'slave_emergency_recovery' is on."
  fi

  re_up_slave

  # If the following error comes up, that means the DB is not yet up, so we need to give it a proper time to be up.
  # ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' (2)
  echo -e "Waiting for DB to be up..."

  wait_until_db_up "${slave_container_name}" "${slave_root_password}"

  docker exec ${mha_container_name} sh -c 'rm -f /root/.ssh/known_hosts'
  docker exec ${slave_container_name} sh -c 'service ssh restart'

}
_main
