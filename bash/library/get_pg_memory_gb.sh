#!/usr/bin/env bash

# Function to get memory size in GB divided by 2 (as integer) from remote system
get_pg_memory_gb() {
    local usage="get_pg_memory_gb <hostname>"
    local hostname="${1:?$usage}"
    local memory_kb
    local memory_gb
    local half_memory

    # Get total memory in KB from /proc/meminfo on remote system
    memory_kb=$(ssh "$hostname" "grep '^MemTotal:' /proc/meminfo | awk '{print \$2}'")

    if [[ -z "$memory_kb" ]]; then
        echo "Error: Could not read memory information from $hostname" >&2
        return 1
    fi

    # Convert KB to GB (1024 * 1024 = 1048576)
    memory_gb=$((memory_kb / 1048576))

    # Divide by 2 and ensure it's an integer
    half_memory=$((memory_gb / 2))

    # Ensure minimum of 1 GB
    if [[ $half_memory -lt 1 ]]; then
        half_memory=1
    fi

    echo "$half_memory"
}
