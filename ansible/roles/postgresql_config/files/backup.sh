#!/bin/bash
export BACKUPS_TO_KEEP=2
export WAL_ARCHIVE="/var/lib/postgresql/14_wal_archive"
export BACKUP_LOCATION="/mnt/nvme/pg_backup"
export PGPORT=27095

# Backups are ordered oldest = 1, newest = $BACKUPS_TO_KEEP
mv_backups() {
  if [ -d "$BACKUP_LOCATION/1" ]
  then
    rm -rf "$BACKUP_LOCATION/1"
  fi

  for i in `/usr/bin/seq 2 1 $BACKUPS_TO_KEEP`
  do
          mkdir -p "$BACKUP_LOCATION/$i"  # always ensure the dir exist before trying to move it
          mv "$BACKUP_LOCATION/$i" "$BACKUP_LOCATION/$((i - 1))"
  done
}

do_backups() {
  mkdir -p "$BACKUP_LOCATION/$BACKUPS_TO_KEEP"
  pg_basebackup -D "$BACKUP_LOCATION/$BACKUPS_TO_KEEP" -Ft --compress=gzip:9 --checkpoint=fast
}

clean_wal_archive() {
  echo "WAL_ARCHIVE=$WAL_ARCHIVE"
  local backups=$(ls -t "$WAL_ARCHIVE"/*.backup.gz)
  for i in $backups
  do
    b=$(basename "$i")
    echo $b
    pg_archivecleanup  -x .gz "$WAL_ARCHIVE" "$b"
  done
  rm -f "$WAL_ARCHIVE"/*backup.gz
}

cd /var/lib/postgresql

mv_backups
do_backups
clean_wal_archive
