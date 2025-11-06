#!/usr/bin/env bash

#
# Add a line to a file on remote system if it doesn't already exist
file_add_line() {
  local usage="file_add_line <hostname> 'line' 'file'"
  local hostname="${1:?$usage}"
  # shellcheck disable=SC2124
  local line="${@:2:$#-2}"
  # shellcheck disable=SC2124
  local file="${@: -1}"

  # Check if file is readable on remote system
  # shellcheck disable=SC2029
  if ! ssh "$hostname" "[ -r \"$file\" ]"; then
    echo "file: $file unreadable on $hostname"
    return 1
  fi

  # Only search in non-commented lines and add if not found
  # shellcheck disable=SC2029
  if ! ssh "$hostname" "grep -v '^\s*#' \"$file\" 2>/dev/null | grep -qF \"$line\""; then
    ssh "$hostname" "echo \"$line\" | sudo tee -a \"$file\""
  fi
}
