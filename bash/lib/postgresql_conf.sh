#!/bin/bash

# PostgreSQL configuration file management

configure_postgresql_conf() {
    echo "=== Configuring PostgreSQL ==="

    if [ -z "$postgresql_config_file" ]; then
        echo "ERROR: postgresql_config_file is not set"
        return 1
    fi

    if [ ! -f "$postgresql_config_file" ]; then
        echo "ERROR: PostgreSQL config file not found: $postgresql_config_file"
        return 1
    fi

    # Backup original config
    cp "$postgresql_config_file" "${postgresql_config_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Create directories for PostgreSQL data paths if they don't exist
    local pg_data_dir="/var/lib/postgresql/${postgresql_version}/main"
    local pg_log_dir="/var/log/postgresql"
    local pg_wal_archive="/var/lib/postgresql/${postgresql_version}_wal_archive"

    mkdir -p "$pg_data_dir"
    mkdir -p "$pg_log_dir"
    mkdir -p "$pg_wal_archive"

    chown -R postgres:postgres "$pg_data_dir"
    chown -R postgres:postgres "$pg_log_dir"
    chown -R postgres:postgres "$pg_wal_archive"
    chmod 0700 "$pg_wal_archive"

    # Stop PostgreSQL if running
    systemctl stop postgresql 2>/dev/null || true

    # Reset WAL archive size to 64MB
    echo "Resetting WAL segment size to 64MB..."
    if [ -d "$pg_data_dir" ]; then
        sudo -u postgres /usr/lib/postgresql/${postgresql_version}/bin/pg_resetwal \
            -D "$pg_data_dir" --wal-segsize 64 2>/dev/null || true
    fi

    # Configure PostgreSQL settings
    echo "Updating PostgreSQL configuration..."

    # Helper function to set PostgreSQL config value
    set_pg_config() {
        local key="$1"
        local value="$2"

        # Remove existing setting (commented or uncommented)
        sed -i "/^#*${key}/d" "$postgresql_config_file"

        # Add new setting
        echo "${key} = ${value}" >> "$postgresql_config_file"
    }

    # Memory Settings
    set_pg_config "shared_buffers" "${shared_buffers}GB"
    set_pg_config "effective_cache_size" "${effective_cache_size}GB"
    set_pg_config "maintenance_work_mem" "$(echo "scale=0; $shared_buffers * 1024 / 16" | bc)MB"
    set_pg_config "work_mem" "$(echo "scale=0; ($shared_buffers * 1024) / ($workers * 4)" | bc)MB"

    # Worker Settings
    set_pg_config "max_worker_processes" "$workers"
    set_pg_config "max_parallel_workers_per_gather" "$other_workers"
    set_pg_config "max_parallel_workers" "$workers"
    set_pg_config "max_parallel_maintenance_workers" "$other_workers"

    # WAL Settings
    set_pg_config "wal_buffers" "16MB"
    set_pg_config "min_wal_size" "1GB"
    set_pg_config "max_wal_size" "4GB"
    set_pg_config "wal_compression" "on"
    set_pg_config "archive_mode" "on"
    set_pg_config "archive_command" "'gzip < %p > ${pg_wal_archive}/%f.gz'"
    set_pg_config "wal_keep_size" "1GB"

    # Checkpoint Settings
    set_pg_config "checkpoint_completion_target" "0.9"
    set_pg_config "checkpoint_timeout" "15min"

    # Connection Settings
    set_pg_config "max_connections" "200"
    set_pg_config "superuser_reserved_connections" "3"

    # Logging Settings
    set_pg_config "logging_collector" "on"
    set_pg_config "log_directory" "'${pg_log_dir}'"
    set_pg_config "log_filename" "'postgresql-%Y-%m-%d_%H%M%S.log'"
    set_pg_config "log_rotation_age" "1d"
    set_pg_config "log_rotation_size" "100MB"
    set_pg_config "log_line_prefix" "'%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '"
    set_pg_config "log_checkpoints" "on"
    set_pg_config "log_connections" "on"
    set_pg_config "log_disconnections" "on"
    set_pg_config "log_lock_waits" "on"
    set_pg_config "log_temp_files" "0"

    # Performance Settings
    set_pg_config "effective_io_concurrency" "200"
    set_pg_config "random_page_cost" "1.1"
    set_pg_config "default_statistics_target" "100"

    # Huge Pages
    set_pg_config "huge_pages" "try"

    echo "PostgreSQL configuration completed"
    return 0
}
