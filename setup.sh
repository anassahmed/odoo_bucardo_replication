#!/bin/bash
#####################################################
# A script to setup bucardo replication environment #
#####################################################

set -e

if ${DEBUG:=false}; then set -x; fi

PROJECT_NAME="odoobucardoreplication"
DATABASE_OWNER="odoo"
DATABASE="odoo_test"
REPLICA_USER="replica"
REPLICA_PASSWORD="replica"
BUCARDO_USER="bucardo"
BUCARDO_PASSWORD="bucardo"
BRANCHES="branch1 branch2"

# build any changes in the docker images
if ${BUILD:=false}; then
    docker-compose build
fi

# destroy the current deployed stack
if ${DESTROY:=false}; then
    docker-compose down -v --remove-orphans
fi

# create and start the new stack
docker-compose up -d
sleep 10

# copy configurations to the main master server
docker cp postgresql.conf \
    ${PROJECT_NAME}_master_db_1:/var/lib/postgresql/data/
docker cp pg_hba.conf \
    ${PROJECT_NAME}_master_db_1:/var/lib/postgresql/data/
docker-compose exec --user=postgres master_db mkdir -p \
    /var/lib/postgresql/data/archive
# reload configurations
docker-compose restart master_db
# add replica and bucardo users
docker-compose exec --user=postgres master_db psql -c \
    "CREATE ROLE $REPLICA_USER WITH REPLICATION LOGIN ENCRYPTED PASSWORD \
     '$REPLICA_PASSWORD'; \
     CREATE ROLE $BUCARDO_USER WITH SUPERUSER LOGIN ENCRYPTED PASSWORD \
     '$BUCARDO_PASSWORD'"
# install odoo database with point of sale module
docker-compose exec --user=postgres master_db psql -c \
    "CREATE DATABASE $DATABASE WITH OWNER $DATABASE_OWNER;"
docker-compose run master_odoo -- -d $DATABASE -i point_of_sale --no-xmlrpc \
    --stop-after-init
# add database, its tables, and its sequences to bucardo
docker-compose exec master_bucardo bucardo add db master_db dbname=$DATABASE \
    host=master_db user=$BUCARDO_PASSWORD password=$BUCARDO_PASSWORD
docker-compose exec master_bucardo bucardo add all tables master_db \
    --herd=odoo
docker-compose exec master_bucardo bucardo add all sequences master_db \
    --herd=odoo

for REP in $BRANCHES
do
    # copy a postgres PITR backup to branch database
    docker-compose stop ${REP}_db
    docker-compose run --rm --entrypoint='/bin/bash -c' --user=postgres \
        ${REP}_db "rm -rf /var/lib/postgresql/data/*; \
                   PGPASSWORD=$REPLICA_PASSWORD pg_basebackup -h master_db -U \
                   $REPLICA_USER -D /var/lib/postgresql/data -P --xlog"
    # start the container again after copying the backup
    docker-compose start ${REP}_db
    sleep 10
    # add the slave database to bucardo
    docker-compose exec master_bucardo bucardo add db ${REP}_db \
        dbname=$DATABASE host=${REP}_db user=$BUCARDO_PASSWORD \
        password=$BUCARDO_PASSWORD
done

# add all branch databases in the sync
docker-compose exec master_bucardo bucardo add sync odoo relgroup=odoo \
    dbs=master_db:source,branch1_db:source,branch2_db:source

# show bucardo status
docker-compose exec master_bucardo bucardo status
docker-compose exec master_bucardo bucardo list dbs
docker-compose exec master_bucardo bucardo list syncs
