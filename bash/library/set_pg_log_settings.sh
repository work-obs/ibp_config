#!/usr/bin/env bash

set_pg_log_settings() {
  local usage="set_pg_log_settings <hostname> <postgresql.conf>"
  # shellcheck disable=SC2034
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"

  set_pg_config "$hostname" "log_destination" "stderr" "$config_file"
  set_pg_config "$hostname" "logging_collector" "on" "$config_file"

  set_pg_config "$hostname" "log_filename" "postgresql_log.%a" "$config_file"
  set_pg_config "$hostname" "log_truncate_on_rotation" "on" "$config_file"
  set_pg_config "$hostname" "log_rotation_size" "0" "$config_file"
  set_pg_config "$hostname" "log_min_duration_statement" "5000" "$config_file"
  set_pg_config "$hostname" "log_checkpoints" "on" "$config_file"


  set_pg_config "$hostname" "log_line_prefix" "%t [%p-%l] %q%u@%d " "$config_file"
  set_pg_config "$hostname" "log_lock_waits" "on" "$config_file"
  set_pg_config "$hostname" "log_statement" "ddl" "$config_file"
  set_pg_config "$hostname" "log_temp_files" "0" "$config_file"

  set_pg_config "$hostname" "track_activities" "on" "$config_file"
  set_pg_config "$hostname" "track_counts" "on" "$config_file"

  set_pg_config "$hostname" "track_functions" "all" "$config_file"

}
