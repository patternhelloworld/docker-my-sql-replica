#!/bin/sh
echo "[SSH TO SLAVE] VIP down"
ssh -p "123456" ssh root@$(printenv machine_slave_ip) "ifconfig $(printenv slave_network_interface_name):1 down"
echo "[SSH TO MASTER] VIP up"
ssh -p "123456" ssh root@$(printenv machine_master_ip) "ifconfig $(printenv master_network_interface_name):1 up $(printenv mha_vip)"