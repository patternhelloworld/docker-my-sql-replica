#!/bin/sh
if [[ ${separated_mode} == false ]]; then
  echo "[SSH TO SLAVE] VIP down"
  ssh root@$(printenv machine_slave_ip) "ifconfig $(printenv slave_network_interface_name):0 down"
  echo "[SSH TO MASTER] VIP up"
  ssh root@$(printenv machine_master_ip) "ifconfig $(printenv master_network_interface_name):0 up $(printenv mha_vip)"
else
  echo "[NOTICE] separated_mode is true."
fi