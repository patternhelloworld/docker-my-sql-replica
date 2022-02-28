# Docker-My-SQL-Replica

> Run Master-Slave MySQL DB and Cope with emergency with robust scripts.  

To Start DB or do recovery process must be [simple](https://github.com/Andrew-Kang-G/my-sql-replica).

## How to Start

Run this simply after coordinating some values on .env.example

```
$ cd 8.0
$ cp -a .env.example .env
$ bash run-replica.sh
```

## Emergency Recovery Mode (.env)

When the Slave DB is corrupted, this mode removes all its data and points it back to the Master DB automatically.

```
SLAVE_EMERGENCY_RECOVERY=true
## The mode is currently working in case of "SEPARATED_MODE=false"
SEPARATED_MODE=false
```

## Separated Mode (.env)

The mode is for Master & Slave to be deployed on each instance. Make sure firewalls are open on your network layer. All the commands and .envs are the same for both Master and Slave.

- .env
```
# Example

SEPARATED_MODE=true
SEPARATED_MODE_WHO_AM_I=master
SEPARATED_MODE_MASTER_IP=172.27.0.20
SEPARATED_MODE_MASTER_PORT=3506
SEPARATED_MODE_SLAVE_IP=172.27.0.58
SEPARATED_MODE_SLAVE_PORT=3507
```

- Master
```
$ cd 8.0
$ cp -a .env.example .env
$ bash run-replica.sh
```

- Slave
```
$ cd 8.0
$ cp -a .env.example .env
$ bash run-replica.sh
```

## Reference 
Replication in MySQL relies on the two servers beginning with an identical set of data, after which, every query that it is modifies data on the master makes the same changes to the data on the slave.