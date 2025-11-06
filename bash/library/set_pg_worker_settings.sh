#!/usr/bin/env bash

set_pg_worker_settings() {
  local usage="set_pg_worker_settings <hostname> <postgresql.conf>"
  # shellcheck disable=SC2034
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  # shellcheck disable=SC2155
  local workers=$(get_pg_workers "$hostname")
  local other_workers=$((workers / 2))

  set_pg_config "$hostname" "max_worker_processes" "$workers" "$config_file"
  set_pg_config "$hostname" "max_parallel_maintenance_workers" "$other_workers" "$config_file"
  set_pg_config "$hostname" "max_parallel_workers_per_gather" "$other_workers" "$config_file"
  set_pg_config "$hostname" "max_parallel_workers" "$workers" "$config_file"
}
