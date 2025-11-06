#!/usr/bin/env bash

# main entry point
set_pg_data_warehouse() {
  # shellcheck disable=SC2034
  local usage="set_pg_data_warehouse <hostname> <postgresql.conf> <version>"
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  local version="${3:?$usage}"

  set_pg_comms_settings "$hostname" "$config_file" # All the communications settings
  set_pg_wal_settings "$hostname" "$config_file" "$version"# Set all the wal settings
  set_pg_i18n_settings "$hostname" "$config_file" # i18n
  set_pg_timezone_settings "$hostname" "Etc/UTC" "$config_file"
  set_pg_log_settings "$hostname" "$config_file"
  set_pg_worker_settings "$hostname" "$config_file"
  set_pg_io_settings "$hostname" "$config_file"
  set_pg_memory_settings "$hostname" "$config_file"
}
