#!/usr/bin/env bash

set_pg_io_settings() {
  local usage="set_pg_io_settings <hostname> <postgresql.conf>"
  # shellcheck disable=SC2034
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  set_pg_config "$hostname" "effective_io_concurrency" "200" "$config_file"
  set_pg_config "$hostname" "fsync" "on" "$config_file"
  set_pg_config "$hostname" "synchronous_commit" "local" "$config_file"
  set_pg_config "$hostname" "full_page_writes" "on" "$config_file"
  set_pg_config "$hostname" "checkpoint_timeout" "30min" "$config_file"
  set_pg_config "$hostname" "checkpoint_completion_target" "0.9" "$config_file"
  set_pg_config "$hostname" "checkpoint_warning" "30s" "$config_file"
  set_pg_config "$hostname" "random_page_cost" "4.0" "$config_file"
  set_pg_config "$hostname" "default_statistics_target" "3000" "$config_file"
  set_pg_config "$hostname" "bgwriter_lru_maxpages" "1000" "$config_file"

}
