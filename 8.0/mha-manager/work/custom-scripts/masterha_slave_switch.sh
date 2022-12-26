#!/bin/sh
echo "[NOTICE] Switch from Slave to Master"
kill -9 $(pgrep -f 'masterha_manager')
  masterha_master_switch --master_state=alive --conf=/etc/mha/app1.conf --orig_master_is_new_slave --running_updates_limit=10000 --new_master_host=$(printenv docker_master_ip)