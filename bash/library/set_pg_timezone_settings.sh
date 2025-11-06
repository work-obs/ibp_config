#!/usr/bin/env bash

set_pg_timezone_settings() {
  local usage="set_pg_timezone_settings <hostname> <timezone> <postgresql.conf>"
  local hostname="${1:?$usage}"
  local tz="${2:?$usage}"
  local config_file="${3:?$usage}"
  set_pg_config "$hostname" "timezone" "$tz" "$config_file"
  set_pg_config "$hostname" "log_timezone" "$tz" "$config_file"
}
