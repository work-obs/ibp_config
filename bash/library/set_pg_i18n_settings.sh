#!/usr/bin/env bash

set_pg_i18n_settings() {
  local usage="set_pg_i18n_settings <hostname> <postgresql.conf>"
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  set_pg_config "$hostname" "lc_messages" "C.UTF-8" "$config_file"
  set_pg_config "$hostname" "lc_monetary" "C.UTF-8" "$config_file"
  set_pg_config "$hostname" "lc_numeric" "C.UTF-8" "$config_file"
  set_pg_config "$hostname" "lc_time" "C.UTF-8" "$config_file"
}
