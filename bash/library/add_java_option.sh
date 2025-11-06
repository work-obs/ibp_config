#!/usr/bin/env bash

# Function to add a value to JAVA_OPTIONS
# Usage: add_java_option "value" [replace_flag]
# replace_flag: 0 = add if not exists, 1 = replace if exists
add_java_option() {
  local usage="add_java_option value replace_bool(0|1) config_file"
  local hostname="${1:?$usage}"
  local value="${1:?$usage}"
  local replace="${2:?$usage}"
  local config_file="${3:?usage}"

  if [ ! -f "$config_file" ]; then
    echo "Error: $config_file not found"
    exit 1
  fi

  # Backup original file
  ssh_cmd "$hostname" "cp \"$config_file\" \"$config_file.$$\""

  # Extract current JAVA_OPTIONS value from remote host
  # shellcheck disable=SC2155
  # shellcheck disable=SC2029
  local current_options=$(get_jetty_java_options "$hostname" "$config_file")

  # Check if value already exists
  if echo "$current_options" | grep -qF -- "$value"; then
    if [ "$replace" -eq 0 ]; then
      echo "Value already exists, skipping: $value"
      return 0
    else
      echo "Value exists, will be replaced: $value"
      # Remove old value first and clean whitespace
      current_options=$(echo "$current_options" | sed "s|$value||g" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    fi
  fi

  # Add new value
  if [ -z "$current_options" ]; then
    current_options="$value"
  else
    current_options="$current_options $value"
  fi

  # Update the remote file
  # shellcheck disable=SC2029
  ssh user@remote "sed -i \"s|^JAVA_OPTIONS=.*|JAVA_OPTIONS=\\\"$current_options\\\"|\" '$config_file'"
  echo "Added: $value"
}
