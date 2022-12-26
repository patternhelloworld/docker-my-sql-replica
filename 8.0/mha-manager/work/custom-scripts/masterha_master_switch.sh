#!/bin/sh
echo "[NOTICE] Switch from Master to Slave"
kill -9 $(pgrep -f 'masterha_manager')
if [[ $(printenv separated_mode) == "true" ]]; then
  masterha_master_switch --master_state=alive --conf=/etc/mha/app1.conf --orig_slave_is_new_master --running_updates_limit=10000 --new_master_host=$(printenv machine_slave_ip)
else
  masterha_master_switch --master_state=alive --conf=/etc/mha/app1.conf --orig_slave_is_new_master --running_updates_limit=10000 --new_master_host=$(printenv docker_slave_ip)
fir