#!/usr/bin/env bash

backup_file() {
  local usage="backup_file <hostname> <config_file>"
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"

  # Check if config file exists on remote system
  # shellcheck disable=SC2029
  if ! ssh "$hostname" "[[ -f \"$config_file\" ]]"; then
    echo "Error: Config file $config_file not found on $hostname"
    return 1
  fi

  # shellcheck disable=SC2155
  local backup_file="${config_file}.backup.\$(date +%Y%m%d)"
  # shellcheck disable=SC2029
  ssh "$hostname" "
    if [ ! -f \"$backup_file\" ]; then
      cp '$config_file' '$backup_file'
      echo 'Backup created: $backup_file'
    else
      echo 'Backup exist: $backup_file'
    fi
  "
}
