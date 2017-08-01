#!/bin/bash

set -ex

mkdir -p /var/lib/bucardo
mkdir -p /var/run/bucardo
chown bucardo: /var/lib/bucardo /var/run/bucardo

mkdir -p "${PGDATA}"
chown -R postgres: "${PGDATA}"
chmod 700 "${PGDATA}"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    su -l postgres -c "/usr/lib/postgresql/9.4/bin/pg_ctl -D ${PGDATA} initdb"
    su -l postgres -c "/usr/lib/postgresql/9.4/bin/pg_ctl -D ${PGDATA} start"
    sleep 5
    bucardo install --batch
    su -l postgres -c "/usr/lib/postgresql/9.4/bin/pg_ctl -D ${PGDATA} -m fast stop"
fi

stop() {
    bucardo stop
    su -l postgres -c "/usr/lib/postgresql/9.4/bin/pg_ctl -D ${PGDATA} -m \
                       fast stop"
}

start() {
    su -l postgres -c "/usr/lib/postgresql/9.4/bin/pg_ctl -D ${PGDATA} start"
    bucardo start
}

start

trap "stop" SIGTERM
trap "stop" SIGINT
trap "stop; start" SIGHUP

while true; do
    tail -f /var/log/bucardo/log.bucardo && wait ${!}
done
