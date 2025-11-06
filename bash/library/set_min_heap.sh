#!/usr/bin/env bash

# Function to set minimum heap size
# Usage: set_min_heap "20g"
set_min_heap() {
  local usage="set_min_heap hostname value config_file"
    local hostname="${1:?$usage}"
    local heap_size="${2:?$usage}"
    local config_file="${3:?$usage}"

    if [ ! -f "$config_file" ]; then
        echo "Error: $config_file not found"
        exit 1
    fi

    # Backup original file
    cp "$config_file" "$config_file.$$"

    # Extract current JAVA_OPTIONS value
    # shellcheck disable=SC2155
    local current_options=$(get_jetty_java_options "$hostname" "$config_file")

    # Remove any existing -Xms settings
    current_options=$(echo "$current_options" | sed -E 's/-Xms[0-9]+[kKmMgG]?//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    # Add new -Xms setting
    if [ -z "$current_options" ]; then
        current_options="-Xms${heap_size}"
    else
        current_options="$current_options -Xms${heap_size}"
    fi

    # Update the file
    sed -i "s|^JAVA_OPTIONS=.*|JAVA_OPTIONS=\"$current_options\"|" "$config_file"
    echo "Set minimum heap size to: -Xms${heap_size}"
}
