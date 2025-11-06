#!/usr/bin/env bash

set_pg_wal_settings() {
  local usage="set_pg_wal_settings <hostname> <postgresql.conf> <version>"
  local wal_segsize="64MB"

  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  local version="${3:?$usage}"
  set_pg_config "$hostname" "wal_level" "archive" "$config_file"
  set_pg_config "$hostname" "max_wal_senders" "10" "$config_file"
  set_pg_config "$hostname" "wal_sync_method" "fsync" "$config_file"
  set_pg_config "$hostname" "wal_buffers" "$wal_segsize" "$config_file" # Cannot be larger that the WAL segment size
  set_pg_config "$hostname" "max_wal_size" "16GB" "$config_file"
  set_pg_config "$hostname" "min_wal_size" "4GB" "$config_file"
  set_pg_config "$hostname" "wal_compression" "on" "$config_file"
  set_pg_config "$hostname" "archive_mode" "on" "$config_file"

  ssh "$hostname" "sudo -u postgres mkdir -p /var/lib/postgresql/wal_archive"
  set_pg_config "$hostname" "archive_command" "gzip < %p > /var/lib/postgresql/wal_archive/%f.gz" "$config_file"
  set_pg_config "$hostname" "restore_command" "gunzip < /var/lib/postgresql/wal_archive/%f.gz > %p" "$config_file"
  set_pg_config "$hostname" "wal_keep_size" "12288" "$config_file"

    # This must happen with database stopped to reset wal
   pg_wal_set_segsize "$hostname" "$wal_segsize" "$version"
}
