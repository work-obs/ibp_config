#!/bin/bash

# PostgreSQL backup script configuration

create_backup_script() {
    echo "=== Creating PostgreSQL backup script ==="

    local backup_script="/var/lib/postgresql/backup.sh"

    # Create the backup script
    cat > "$backup_script" <<'EOF'
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

EOF

    # Set permissions
    chown postgres:postgres "$backup_script"
    chmod 0755 "$backup_script"

    echo "Backup script created at: $backup_script"

    # Schedule in cron for postgres user
    echo "=== Scheduling backup script in crontab ==="

    # Create cron entry (runs every 6 hours starting at 02:00)
    local cron_entry="0 2,8,14,20 * * * /var/lib/postgresql/backup.sh >/dev/null 2>&1"

    # Check if cron entry already exists for postgres user
    if sudo -u postgres crontab -l 2>/dev/null | grep -q "backup.sh"; then
        echo "Cron entry already exists for backup.sh"
    else
        # Add to postgres user's crontab
        (sudo -u postgres crontab -l 2>/dev/null; echo "$cron_entry") | sudo -u postgres crontab -
        echo "Cron entry added to postgres user's crontab"
    fi

    echo "Backup script configuration completed"
    return 0
}
