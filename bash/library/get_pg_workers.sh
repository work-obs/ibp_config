#!/usr/bin/env bash

get_pg_workers() {
    local usage="get_pg_workers <hostname>"
    local hostname="${1:?$usage}"
    local workers
    local half_cpu

    # Get number of processing units from remote system
    workers=$(ssh "$hostname" "nproc")

    if [[ -z "$workers" || $workers -eq 0 ]]; then
        echo "Error: Could not determine CPU count from $hostname" >&2
        return 1
    fi

    # Divide by 2 and ensure it's an integer
    half_cpu=$((workers / 2))

    # Ensure minimum of 1 CPU
    if [[ $half_cpu -lt 1 ]]; then
        half_cpu=1
    fi

    echo "$half_cpu"
}
