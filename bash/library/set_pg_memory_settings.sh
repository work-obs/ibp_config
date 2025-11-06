#!/usr/bin/env bash

set_pg_memory_settings() {
    local usage="set_pg_memory_settings <hostname> <postgresql.conf>"
  # shellcheck disable=SC2034
    local hostname="${1:?$usage}"
    local config_file="${2:?$usage}"
    # shellcheck disable=SC2155
    local memory=$(get_pg_memory_gb "$hostname")
    local shared_buffers=$((memory / 4))
    # shellcheck disable=SC2034
    local effective_cache_size=$((memory - shared_buffers))
    # Each connection get its own work_mem allocated, thus more memory used
    set_pg_config "$hostname" "max_connections" "360" "$config_file"
    set_pg_config "$hostname" "work_mem" "128MB" "$config_file"

    set_pg_config "$hostname" "shared_buffers" "${shared_buffers}GB" "$config_file"
    set_pg_config "$hostname" "effective_cache_size" "${effective_cache_size}GB" "$config_file"

    set_pg_config "$hostname" "huge_pages" "on" "$config_file"
    set_pg_config "$hostname" "maintenance_work_mem" "2GB" "$config_file"
}
