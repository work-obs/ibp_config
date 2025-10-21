#!/bin/bash

# Variables calculation library for PostgreSQL configuration

# Calculate system memory and derived values
calculate_memory_variables() {
    # Get total memory in bytes
    memory_bytes=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')

    # Calculate half_memory_gb (minimum 1GB)
    half_memory_gb=$(echo "scale=0; ($memory_bytes / 1073741824) / 2" | bc)
    if [ "$half_memory_gb" -lt 1 ]; then
        half_memory_gb=1
    fi

    # Calculate shared_buffers (1/8 of memory)
    shared_buffers=$(echo "scale=0; $memory_bytes / 8 / 1073741824" | bc)
    if [ "$shared_buffers" -lt 1 ]; then
        shared_buffers=1
    fi

    # Calculate effective_cache_size
    effective_cache_size=$(echo "scale=0; $half_memory_gb - $shared_buffers" | bc)
    if [ "$effective_cache_size" -lt 1 ]; then
        effective_cache_size=1
    fi

    # Calculate worker values based on CPU cores
    cpu_cores=$(nproc)
    workers=$(echo "scale=0; $cpu_cores / 2" | bc)
    if [ "$workers" -lt 1 ]; then
        workers=1
    fi

    other_workers=$(echo "scale=0; $cpu_cores / 4" | bc)
    if [ "$other_workers" -lt 1 ]; then
        other_workers=1
    fi

    # Calculate hugepages for sysctl
    nr_hugepages=$(echo "scale=0; (($memory_bytes / 2000000) / 2)" | bc)

    # Export all variables
    export memory_bytes
    export half_memory_gb
    export shared_buffers
    export effective_cache_size
    export workers
    export other_workers
    export nr_hugepages
}

# Validate PostgreSQL version parameter
validate_postgresql_version() {
    if [ -z "$postgresql_version" ]; then
        echo "ERROR: postgresql_version is required"
        return 1
    fi

    # Set postgresql_config_file
    postgresql_config_file="/etc/postgresql/${postgresql_version}/main/postgresql.conf"
    export postgresql_config_file

    return 0
}

# Initialize all variables
init_variables() {
    calculate_memory_variables
    validate_postgresql_version || return 1

    echo "=== Calculated Variables ==="
    echo "memory_bytes: $memory_bytes"
    echo "half_memory_gb: ${half_memory_gb}GB"
    echo "shared_buffers: ${shared_buffers}GB"
    echo "effective_cache_size: ${effective_cache_size}GB"
    echo "workers: $workers"
    echo "other_workers: $other_workers"
    echo "nr_hugepages: $nr_hugepages"
    echo "postgresql_version: $postgresql_version"
    echo "postgresql_config_file: $postgresql_config_file"
    echo "============================"

    return 0
}
