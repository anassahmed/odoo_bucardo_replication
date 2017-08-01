# Bucardo Odoo Replication

This repository is an experiment to replicate Odoo in multi-branches super
market (using Odoo PoS) with Bucardo (Multi-master replication).

## What's the use case of odoo replication?

The use case is pretty simple, we have a main server (Odoo & PostgreSQL)
installed in the main datacenter of the company, and we have branches all over
the world that work on the PoS module but they don't have a stable connection
to the main server all the time (connection may go away for several days) so
we need to install Odoo & PostgreSQL servers for each branch to be able to
continue working without interruptions and then sync back to the master Odoo &
PostgreSQL servers automatically when the connection gets back online.

## How to use this repo?

To bring the cluster/stack up, just execute the script:

```bash
$ ./setup.sh
```

which will build the needed docker images and deploy them according to the
docker-compose.yml file. you need to have `docker` and `docker-compose` in your
`$PATH` before executing this shell script.

The script will also create a testing database with PoS module on it with demo
data, and replicate it to 2 branches with `pg_basebackup` and then kicks the
bucardo replication.

- The main server should be browsable on the URL: http://localhost:8010
- The branch1 server should be browsable on the URL: http://localhost:8020
- The branch2 server should be browsable on the URL: http://localhost:8030

## How to test?

Start by testing something basic like adding, deleting, and  modifying a bunch
of users on different instances (main, branch1, branch2) and observe the sync
on the other instances.

Then, create new Point of Sales for the branches in the Point of Sale app.
Notice that Bucardo doesn't replicate DDL on its own, so the newly created
PostgreSQL sequences should be replicated and added to bucardo manually first.
We need to stop the branches instances, then replicate the database again with
`pg_basebackup` and add the new sequences to bucardo, then restart it again.

```bash
$ docker-compose stop branch1_db branch2_db
$ docker-compose run --rm --entry-point='/bin/bash -c' --user=postgres \
    branch1_db "rm -rf /var/lib/postgresql/data/*; \
                PGPASSWORD=replica pg_basebackup -h master_db -U \
                replica -D /var/lib/postgresql/data -P --xlog"
$ docker-compose start branch1_db branch2_db
$ docker-compose exec master_bucardo bucardo add all sequences master_db \
    --herd=odoo
$ docker-compose exec master_bucardo bucardo restart
$ docker-compose exec master_bucardo bucardo status # check status
$ docker-compose exec master_bucardo bucardo list dbs # check db statuses
$ docker-compose exec master_bucardo bucardo list syncs # check sync statuses
```

After that, start a session for each branch on a different PoS (preferably with
different users) and start selling, and see the orders being created on the PoS
of each intance.

you can then disconnect one of these servers from the network (to see what
happens when it gets back online) or you can just stop the bucardo instance
altogether, to stop the replication from happening (either way, it's the same
result).

```bash
$ docker-compose stop master_bucardo
# go do some PoS orders on different instances, then get back to restart it
$ docker-compose start master_bucardo
```

## What's the end result of this experiment?

Odoo is not designed with multi-master replication or being a distributed
system in mind. It's - at the end of the day - an ancient typical monolithic
web application. So, you'll notice that problems with sequences will arise
(Bucardo for some reason doesn't synchronize them fast as the tables, or Odoo
maybe caches them somehow) as you'll get some unique primary key violations
because the PostgreSQL sequence gave you the same number the other instance
gave to the previous record.

Also, bucardo (with all of its conflict resolution strategies) will throw data
of one of the instances if they used the same primary key (say you have created
a user with ID 10 on branch1 and created a user with ID 10 on branch2 while
they're being disconnected from network, when they get back online and bucardo
starts to replicate them, it'll take one of the users and throw the other
one!!).

Add to that Bucardo doesn't discover DDL alterations or replicate it, so upon
any module installation, upgrade, or removal, and also PoS (or any
sequence-altering models) will need to be replicated manually (take down the
branches instances, replicate the master database, add the tables/sequences to
bucardo, and restart the branches instances and bucardo server).

Some of these problems can be solved using BDR (Bi-Directional Replication)
from 2ndQuadrant (Especially, the DDL replication thing), but modifications to
Odoo source code should be made to accept such replication (using UUIDs or
Global Sequences for primary keys instead of normal integer sequences will be
one step forward for example).

## What's other options for the setup.sh script?

You can pass `BUILD=true` to re-build images (if there's new changes on them),
and you can pass `DESTROY=true` to remove the old instances and start from
scratch. Also, the script can be debugged by passing the variable `DEBUG=true`
to see the executed commands alongside their output.

```bash
$ DEBUG=true BUILD=true DESTROY=true ./setup.sh
```
