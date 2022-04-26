#!/bin/sh

trap "postfix stop" SIGINT
trap "postfix stop" SIGTERM
trap "postfix reload" SIGHUP

postfix start

sleep 5
while kill -0 `cat /var/spool/postfix/pid/master.pid | xargs`; do
  sleep 5
done
