#!/usr/bin/env bash

create_pg_clean_archive_sh() {
  local usage="create_pg_backup_sh <hostname> <path_to_backup_script>"
  local hostname="${1:?$usage}"
  local create_pg_clean_archive_sh="${2:?$usage}"

  # literal heredoc as root on remote system
  # shellcheck disable=SC2029
  ssh "$hostname" "sudo -u root tee '$create_pg_clean_archive_sh' > /dev/null" << 'PG_BACKUP_SH'
#!/bin/bash
# /usr/local/bin/cleanup_wal_archive.sh

ARCHIVE_DIR="/var/lib/postgresql/archive"
DATA_DIR="/var/lib/postgresql/14/main"

# Get the oldest WAL we still need
OLDEST_WAL=$(pg_controldata -D "$DATA_DIR" | \
  grep "Latest checkpoint's REDO WAL file" | \
  awk '{print $6}')

if [ -n "$OLDEST_WAL" ]; then
    # Actually clean up
    pg_archivecleanup -d "$ARCHIVE_DIR" "$OLDEST_WAL"
else
    echo "$(date): ERROR - Could not determine oldest WAL"
    exit 1
fi

PG_BACKUP_SH
  # shellcheck disable=SC2029
  ssh "$hostname" "
    sudo bash -c 'command -p chown postgres:postgres \"$create_pg_clean_archive_sh\"'
    sudo bash -c 'command -p chmod 755 \"$create_pg_clean_archive_sh\"'
  "
}
