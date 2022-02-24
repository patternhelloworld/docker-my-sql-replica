# My-SQL-Replica

> Run Master-Slave MySQL DB and Cope with emergency with robust scripts.  

To Start or do recovery process must be [simple](https://github.com/Andrew-Kang-G/my-sql-replica).

## How to Start

Run this simply after coordinating some values on .env.example

```
$ cd 8.0
$ cp -a .env.example .env
$ bash run-replica.sh
```

## Separated Mode (.env)

The mode will be supposed to set Master & Slave on individual instances. Before that, it needs to be tested enough. Now it is recommended to use only "SEPARATED_MODE=false".

## Reference 
Replication in MySQL relies on the two servers beginning with an identical set of data, after which, every query that it is modifies data on the master makes the same changes to the data on the slave.