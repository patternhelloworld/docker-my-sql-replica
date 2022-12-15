#!/bin/sh

echo "[SSH TO MASTER] VIP down"
ssh root@$(printenv machine_master_ip) "ifconfig $(printenv master_network_interface_name):1 down"
echo "[SSH TO SLAVE] VIP up"
ssh root@$(printenv machine_slave_ip) "ifconfig $(printenv slave_network_interface_name):1 up $(printenv mha_vip)"