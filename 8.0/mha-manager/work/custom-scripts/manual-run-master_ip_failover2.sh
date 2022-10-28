#!/bin/bash
/usr/local/mha/work/custom-scripts/master_ip_failover --command=start --ssh_user=root --orig_master_host=$(printenv db_slave_ip_from_the_others) --orig_master_ip=$(printenv db_slave_ip_from_the_others) --orig_master_port=3306 --new_master_host=$(printenv db_master_ip_from_the_others) --new_master_ip=$(printenv db_master_ip_from_the_others) --new_master_port=3306 --new_master_password=$(printenv MYSQL_ROOT_PASSWORD)
# masterha_master_switch --master_state=alive --conf=/etc/mha/app1.conf
