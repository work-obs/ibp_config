#!/usr/bin/env bash
# Function to remove maximum heap size settings
# Usage: remove_max_heap
remove_max_heap() {
    local usage="remove_max_heap hostname config_file"
    local hostname="${1:?$usage}"
    local config_file="${2:?$usage}"

    # Backup original file
    cp "$config_file" "$config_file.$$"

    # Extract current JAVA_OPTIONS value
    # shellcheck disable=SC2155
    local current_options=$(get_jetty_java_options "$hostname" "$config_file")

    # Remove any -Xmx settings
    current_options=$(echo "$current_options" | sed -E 's/-Xmx[0-9]+[kKmMgG]?//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    # Update the remote file
    # shellcheck disable=SC2029
    ssh user@remote "sed -i \"s|^JAVA_OPTIONS=.*|JAVA_OPTIONS=\\\"$current_options\\\"|\" '$config_file'"
    echo "Removed all maximum heap size settings"
}
