#!/usr/bin/env bash

pg_wal_set_segsize() {
  local usage="pg_wal_set_segsize <hostname> <wal_size>"
  # shellcheck disable=SC2034
  local hostname="${1:?$usage}"
  local wal_size="${2:?$usage}"
  local version="${3:?$usage}"

  local pg_resetwal="/usr/lib/postgresql/${version}/bin/pg_resetwal"
  local data_dir="/var/lib/postgresql/${version}/main"

  # shellcheck disable=SC2029
  if ssh "$hostname" "[ -d \"$data_dir\" ]"; then   # Only run the command if $data_dir exists remotely
    # Run pg_resetwal
    echo "Running pg_resetwal to set WAL segment size to ${wal_size}..."

    if ssh_cmd "$hostname" "sudo -u postgres \"$pg_resetwal --wal-segsize=${wal_size} -D $data_dir\""; then
      echo "✓ Successfully set WAL segment size for PostgreSQL ${version}"
    else
      echo "✗ Failed to set WAL segment size for PostgreSQL ${version}"
      echo "Please check the error above"
    fi
  fi


}
