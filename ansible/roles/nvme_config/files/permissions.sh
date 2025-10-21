#!/bin/bash
export DIRS="pg_wal pg_backup pg_temp"
for i in $DIRS
do
  mkdir -p /mnt/nvme/$i
  chmod 0700 /mnt/nvme/$i
  chown postgres:postgres /mnt/nvme/$i
done
