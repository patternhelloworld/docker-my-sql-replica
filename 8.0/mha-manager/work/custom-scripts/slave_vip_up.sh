#!/bin/sh
ssh root@$(printenv db_master_ip_from_the_others) sudo ifconfig $(printenv master_network_interface_name):1 down || ssh root@$(printenv db_slave_ip_from_the_others) sudo ifconfig $(printenv slave_network_interface_name):1 up
ssh root@$(printenv db_slave_ip_from_the_others) sudo ifconfig $(printenv slave_network_interface_name):1 up
