#!/usr/bin/env bash

get_jetty_java_options() {
  local usage="get_jetty_java_options hostname config_file"
  local hostname="${1:?$usage}"
  local config_file="${3:?usage}"

  # shellcheck disable=SC2029
  # shellcheck disable=SC2155
  local current_options="$(ssh "$hostname" "grep '^JAVA_OPTIONS=' \"$config_file\" | sed 's/^JAVA_OPTIONS=//' | sed 's/^\"\\(.*\\)\"$/\\1/'")"

  echo "$current_options"
}

