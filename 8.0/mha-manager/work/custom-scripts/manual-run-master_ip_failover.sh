#!/bin/bash
if [[ $(printenv separated_mode) == "true" ]]; then
  /usr/local/mha/work/custom-scripts/master_ip_failover --command=start --ssh_user=root --orig_master_host=$(printenv machine_master_ip) --orig_master_ip=$(printenv machine_master_ip) --orig_master_port=$(printenv machine_master_db_port) --new_master_host=$(printenv machine_slave_ip) --new_master_ip=$(printenv machine_slave_ip) --new_master_port=$(printenv machine_slave_db_port) --new_master_password=$(printenv MYSQL_ROOT_PASSWORD)
else
  /usr/local/mha/work/custom-scripts/master_ip_failover --command=start --ssh_user=root --orig_master_host=$(printenv docker_master_ip) --orig_master_ip=$(printenv docker_master_ip) --orig_master_port=3306 --new_master_host=$(printenv docker_slave_ip) --new_master_ip=$(printenv docker_slave_ip) --new_master_port=3306 --new_master_password=$(printenv MYSQL_ROOT_PASSWORD)
fi
# masterha_master_switch --master_state=alive --conf=/etc/mha/app1.conf
