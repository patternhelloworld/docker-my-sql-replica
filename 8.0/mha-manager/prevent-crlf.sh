#!/bin/bash
sed -i -e 's/\r$//' .env .env.example master/Dockerfile slave/Dockerfile master/my.cnf slave/my.cnf docker-compose.yml util.sh