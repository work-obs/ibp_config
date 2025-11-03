#!/usr/bin/env bash
#
# IBP Migration Tool (via Jumpbox)
# - Migrates any IBP EC2 instance to latest Ubuntu 22.04 with PostgreSQL 14.
# - Executes from jumpbox with SSH access to source and destination servers.
#
# Author  : Frank Claassens
# Created : 15 October 2025
# Updated : Thu 31 October 2025
#

# Source utility libraries
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/lib/rsync_utils.sh"

# Colour constants
readonly BOLD_RED='\033[1;31m' BOLD_GREEN='\033[1;32m' BOLD_YELLOW='\033[1;33m'
readonly BOLD_BLUE='\033[1;34m' BOLD_CYAN='\033[1;36m' BOLD_WHITE='\033[1;37m'
readonly RESET='\033[0m'

# Configuration variables
SOURCE_HOST="${SOURCE_HOST:-}"
SOURCE_PORT="${SOURCE_PORT:-27095}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-smoothie}"
DEST_HOST="${DEST_HOST:-}"
DEST_PORT="${DEST_PORT:-27095}"
DEST_SSH_USER="${DEST_SSH_USER:-smoothie}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/pg_migration/dumps}"
SERVER_FILES_BACKUP_DIR="${SERVER_FILES_BACKUP_DIR:-/tmp/pg_migration/server_files}"
PARALLEL_JOBS="${PARALLEL_JOBS:-2}"
PG_USER="postgres"
BI_CUBE_DETECTED=""

function err() {
  printf '%b[%s]: %s%b\n' "${BOLD_RED}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}" >&2
}

function info() {
  [[ -z "$1" ]] && { err "info: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_BLUE}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}"
}

function warn() {
  [[ -z "$1" ]] && { err "warn: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_YELLOW}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}"
}

function success() {
  [[ -z "$1" ]] && { err "success: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_GREEN}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}"
}

function error() {
  [[ -z "$1" ]] && { err "error: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_RED}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}" >&2
}

#######################################
# Interactively prompts for required migration configuration if not set via environment variables.
# Returns:
#   0 on success, 1 if required values are missing
#######################################
function prompt_required_config() {
  if [[ -z "${SOURCE_HOST}" ]]; then
    read -p "Source Host: " SOURCE_HOST
    if [[ -z "${SOURCE_HOST}" ]]; then
      error "Source host is required"
      return 1
    fi
  fi

  if [[ -z "${SOURCE_SSH_USER}" ]]; then
    read -p "Source SSH User [smoothie]: " input_ssh_user
    SOURCE_SSH_USER="${input_ssh_user:-smoothie}"
    if [[ -z "${SOURCE_SSH_USER}" ]]; then
      error "Source SSH user is required"
      return 1
    fi
  fi

  if [[ -z "${SOURCE_PORT}" ]]; then
    read -p "Source Port [27095]: " input_port
    SOURCE_PORT="${input_port:-27095}"
  fi

  if [[ -z "${DEST_HOST}" ]]; then
    read -p "Destination Host: " DEST_HOST
    if [[ -z "${DEST_HOST}" ]]; then
      error "Destination host is required"
      return 1
    fi
  fi

  if [[ -z "${DEST_SSH_USER}" ]]; then
    read -p "Destination SSH User: " input_ssh_user
    DEST_SSH_USER="${input_ssh_user:-smoothie}"
    if [[ -z "${DEST_SSH_USER}" ]]; then
      error "Destination SSH user is required"
      return 1
    fi
  fi

  if [[ -z "${DEST_PORT}" ]]; then
    read -p "Destination Port [27095]: " input_port
    DEST_PORT="${input_port:-27095}"
  fi

  return 0
}

function validate_environment() {
  echo
  info "[⏳] Validating environment..."

  if [[ -z "${SOURCE_HOST}" ]]; then
    error "SOURCE_HOST is required"
    return 1
  fi

  if [[ -z "${SOURCE_SSH_USER}" ]]; then
    error "SOURCE_SSH_USER is required"
    return 1
  fi

  if [[ -z "${DEST_HOST}" ]]; then
    error "DEST_HOST is required"
    return 1
  fi

  if [[ -z "${DEST_SSH_USER}" ]]; then
    error "DEST_SSH_USER is required"
    return 1
  fi

  if ! ssh -o ConnectTimeout=5 "${SOURCE_SSH_USER}@${SOURCE_HOST}" "echo 'SSH OK'" &> /dev/null; then
    error "Cannot connect to source ${SOURCE_HOST} via SSH"
    return 1
  fi

  if ! ssh -o ConnectTimeout=5 "${DEST_SSH_USER}@${DEST_HOST}" "echo 'SSH OK'" &> /dev/null; then
    error "Cannot connect to destination ${DEST_HOST} via SSH"
    return 1
  fi

  success "[☑️] Environment validation passed"
  
  detect_bi_cube
  if [[ "${BI_CUBE_DETECTED}" == "true" ]]; then
    info "[ℹ️] bi_cube detected on source"
  fi
}

function check_disk_space_source() {
  echo
  info "[⏳] Checking disk space on source server..."

  local available
  available=$(ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "df -BG ${BACKUP_DIR%/*} 2>/dev/null | awk 'NR==2 {print \$4}' | sed 's/G//'")

  if [[ -z "${available}" ]]; then
    available=$(ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "df -BG / | awk 'NR==2 {print \$4}' | sed 's/G//'")
  fi

  if (( available < 10 )); then
    error "Insufficient disk space on source. Available: ${available}GB"
    return 1
  fi

  success "[☑️] Disk space check passed: ${available}GB available on source"
}

function check_disk_space_dest() {
  echo
  info "[⏳] Checking disk space on dest server..."

  local available
  available=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "df -BG ${BACKUP_DIR%/*} 2>/dev/null | awk 'NR==2 {print \$4}' | sed 's/G//'")

  if [[ -z "${available}" ]]; then
    available=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "df -BG / | awk 'NR==2 {print \$4}' | sed 's/G//'")
  fi

  if (( available < 10 )); then
    error "Insufficient disk space on destination. Available: ${available}GB"
    return 1
  fi

  success "[☑️] Disk space check passed: ${available}GB available on dest"
}

function create_backup_directory() {
  echo
  info "[⏳] Creating backup directory on source server..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "mkdir -p ${BACKUP_DIR}" || {
    error "Failed to create backup directory on source"
    return 1
  }

  success "[☑️] Backup directory created on source: ${BACKUP_DIR}"
}

function export_globals() {
  echo
  info "[⏳] Exporting global objects..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "pg_dumpall -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} --globals-only -f ${BACKUP_DIR}/globals.sql" || {
    error "Failed to export global objects"
    return 1
  }

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo chmod 600 ${BACKUP_DIR}/globals.sql"
  success "[☑️] Global objects exported"
}

function display_summary() {
  info "[ℹ️] SOURCE Database cluster summary:"

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} postgres -p ${SOURCE_PORT} -c \"
    SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
    FROM pg_database
    WHERE datallowconn
    ORDER BY pg_database_size(datname) DESC;
  \"" || {
    error "Failed to retrieve database summary"
    return 1
  }
}

function display_summary_dest() {
  info "[ℹ️] DEST Database cluster summary:"

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c \"
    SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
    FROM pg_database
    WHERE datallowconn
    ORDER BY pg_database_size(datname) DESC;
  \"" || {
    error "Failed to retrieve database summary"
    return 1
  }
}

#######################################
# Dynamically calculates and applies PostgreSQL performance settings on source server
# based on available CPU cores and RAM to optimize dump operations.
# Returns:
#   0 on success, 1 on failure
#######################################
function set_maintenance_settings_source() {
  echo
  info "[⏳] Setting temporary maintenance settings on source..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    function info() {
      printf '\033[1;34m[%s]: %s\033[0m\n' "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*"
    }

    cpu_cores=\$(nproc)
    parallel_workers=\$((cpu_cores * 3 / 4))
    half_cores=\$((cpu_cores / 2))
    
    total_ram_gb=\$(free -g | awk '/^Mem:/{print \$2}')
    maintenance_mem=\$((total_ram_gb / 4))
    if (( maintenance_mem < 2 )); then
      maintenance_mem=2
    elif (( maintenance_mem > 8 )); then
      maintenance_mem=8
    fi
    
    shared_buffers=\$((total_ram_gb / 4))
    if (( shared_buffers < 2 )); then
      shared_buffers=2
    elif (( shared_buffers > 4 )); then
      shared_buffers=4
    fi
    
    effective_cache=\$((total_ram_gb * 37 / 100))
    if (( effective_cache < 4 )); then
      effective_cache=4
    fi
    
    info "  [-] Detected CPU Cores: \$cpu_cores"
    info "  [-] Parallel Workers (75%): \$parallel_workers"
    info "  [-] Total RAM: \${total_ram_gb}GB"
    info "  [-] Maintenance Work Mem: \${maintenance_mem}GB"
    info "  [-] Shared Buffers: \${shared_buffers}GB"
    info "  [-] Effective Cache Size: \${effective_cache}GB"
    
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET maintenance_work_mem = '\${maintenance_mem}GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET max_parallel_maintenance_workers = \${parallel_workers};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET max_parallel_workers_per_gather = \${half_cores};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET checkpoint_timeout = '1h';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET max_wal_size = '16GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET min_wal_size = '4GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET shared_buffers = '\${shared_buffers}GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET effective_cache_size = '\${effective_cache}GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET wal_compression = 'on';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM SET synchronous_commit = 'off';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "SELECT pg_reload_conf();"

    # sudo systemctl stop postgresql
    # sleep 5
    # sudo -u ${PG_USER} /usr/lib/postgresql/12/bin/pg_resetwal -D /var/lib/postgresql/12/main --wal-segsize 64
    # sudo systemctl start postgresql
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to set maintenance settings on source"
    return 1
  fi

  success "[☑️] Maintenance settings applied on source"
}

#######################################
# Dynamically calculates and applies PostgreSQL performance settings on destination server
# based on available CPU cores and RAM to optimize restore operations.
# Returns:
#   0 on success, 1 on failure
#######################################
function set_maintenance_settings_dest() {
  echo
  info "[⏳] Setting temporary maintenance settings on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    function info() {
      printf '\033[1;34m[%s]: %s\033[0m\n' "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*"
    }

    cpu_cores=\$(nproc)
    parallel_workers=\$((cpu_cores * 3 / 4))
    half_cores=\$((cpu_cores / 2))

    total_ram_gb=\$(free -g | awk '/^Mem:/{print \$2}')
    maintenance_mem=\$((total_ram_gb / 4))
    if (( maintenance_mem < 2 )); then
      maintenance_mem=2
    elif (( maintenance_mem > 8 )); then
      maintenance_mem=8
    fi
    
    shared_buffers=\$((total_ram_gb / 4))
    if (( shared_buffers < 2 )); then
      shared_buffers=2
    elif (( shared_buffers > 4 )); then
      shared_buffers=4
    fi
    
    effective_cache=\$((total_ram_gb * 37 / 100))
    if (( effective_cache < 4 )); then
      effective_cache=4
    fi

    info "  [-] Detected CPU Cores: \$cpu_cores"
    info "  [-] Parallel Workers (75%): \$parallel_workers"
    info "  [-] Total RAM: \${total_ram_gb}GB"
    info "  [-] Maintenance Work Mem: \${maintenance_mem}GB"
    info "  [-] Shared Buffers: \${shared_buffers}GB"
    info "  [-] Effective Cache Size: \${effective_cache}GB"
    
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET maintenance_work_mem = '\${maintenance_mem}GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET max_parallel_maintenance_workers = \${parallel_workers};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET max_parallel_workers_per_gather = \${half_cores};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET checkpoint_timeout = '1h';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET max_wal_size = '16GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET min_wal_size = '4GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET shared_buffers = '\${shared_buffers}GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET effective_cache_size = '\${effective_cache}GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET wal_compression = 'on';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM SET synchronous_commit = 'off';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "SELECT pg_reload_conf();"

    # sudo systemctl stop postgresql
    # sleep 5
    # sudo -u ${PG_USER} /usr/lib/postgresql/14/bin/pg_resetwal -D /var/lib/postgresql/14/main --wal-segsize 64
    # sudo systemctl start postgresql
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to set maintenance settings on destination"
    return 1
  fi

  success "[☑️] Maintenance settings applied on destination"
}

function revert_maintenance_settings_source() {
  echo
  info "[⏳] Reverting maintenance settings to defaults on source..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET maintenance_work_mem;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET max_parallel_maintenance_workers;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET max_parallel_workers_per_gather;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET checkpoint_timeout;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET max_wal_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET min_wal_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET shared_buffers;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET effective_cache_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET wal_compression;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "ALTER SYSTEM RESET synchronous_commit;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -c "SELECT pg_reload_conf();"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to revert maintenance settings on source"
    return 1
  fi

  success "[☑️] Maintenance settings reverted to defaults on source"
}

function revert_maintenance_settings_dest() {
  info "[⏳] Reverting maintenance settings to defaults on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET maintenance_work_mem;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET max_parallel_maintenance_workers;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET max_parallel_workers_per_gather;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET checkpoint_timeout;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET max_wal_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET min_wal_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET shared_buffers;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET effective_cache_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET wal_compression;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "ALTER SYSTEM RESET synchronous_commit;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "SELECT pg_reload_conf();"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to revert maintenance settings on destination"
    return 1
  fi

  success "[☑️] Maintenance settings reverted to defaults on destination"
}

function detect_bi_cube() {
  if [[ -n "${BI_CUBE_DETECTED}" ]]; then
    [[ "${BI_CUBE_DETECTED}" == "true" ]]
    return $?
  fi
  
  if ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "test -f /etc/profile.d/ibp.sh" 2>/dev/null; then
    BI_CUBE_DETECTED="true"
    return 0
  else
    BI_CUBE_DETECTED="false"
    return 1
  fi
}

#######################################
# Dumps all user databases from source server in parallel using pg_dump with directory format.
# Automatically calculates optimal parallelism based on CPU cores and executes dumps concurrently.
# Returns:
#   0 on success, 1 if any database dump fails
#######################################
function dump_databases() {
  display_summary

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo find ${BACKUP_DIR} -mindepth 1 ! -name 'globals.sql' -exec rm -rf {} + 2>/dev/null || true" || {
    error "Failed to clear backup directory"
    return 1
  }

  info "[⏳] Dumping databases in parallel..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    databases=\$(psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');")
    if [[ -z "\${databases}" ]]; then
      echo "WARN: No user databases found"
      exit 0
    fi

    echo
    echo "-----------------------"
    echo "-- DATABASES TO DUMP --"
    echo "-----------------------"
    echo "\${databases}"
    echo "-----------------------"
    echo

    cpu_cores=\$(nproc)
    half_cores=\$((cpu_cores / 2))
    parallel_jobs=\$((half_cores / 2))
    if (( parallel_jobs < 2 )); then
      parallel_jobs=2
    fi    
    
    echo "INFO: Using \${parallel_jobs} parallel jobs per database dump"
    echo
    echo "INFO: Starting parallel database dumps..."
    
    pids=()
    failed=0
    
    for db in \${databases}; do
      (
        echo "INFO: [START] Dumping database: \${db}"
        mkdir -p ${BACKUP_DIR}/\${db}.dump
        if pg_dump -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -Fd -j \${parallel_jobs} -f ${BACKUP_DIR}/\${db}.dump \${db}; then
          echo "INFO: [DONE] Successfully dumped database: \${db}"
        else
          echo "ERROR: [FAILED] Failed to dump database: \${db}"
          exit 1
        fi
      ) &
      pids+=(\$!)
    done
    
    echo "INFO: Waiting for all database dumps to complete..."
    for pid in "\${pids[@]}"; do
      if ! wait "\${pid}"; then
        failed=1
      fi
    done
    
    if [[ \${failed} -eq 1 ]]; then
      echo "ERROR: One or more database dumps failed"
      exit 1
    fi

    chmod -R 700 ${BACKUP_DIR}/*.dump
    echo "INFO: All database dumps completed successfully"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Database dump failed"
    return 1
  fi

  success "[☑️] All databases dumped successfully"
}

#######################################
# Creates compressed tar archive of database dumps and server configuration files using zstd.
# Conditionally includes bi_cube files if detected, applies path transformations for proper extraction.
# Returns:
#   0 on success
#######################################
function create_archive() {
  info "[⏳] Creating TAR FILE on source..."
  
  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    function info() {
      printf '\033[1;34m[%s]: %s\033[0m\n' "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*"
    }
    
    sudo apt install zstd -y -qq > /dev/null 2>&1
    
    if [[ "${BI_CUBE_DETECTED}" == "true" ]]; then
      cd /tmp && sudo -u root tar --use-compress-program="zstd -T0 -3" -cf pg_dumps.tar.zst \\
        pg_migration/dumps/ \\
        --transform 's,^opt,pg_migration/server_files/opt,' \\
        --transform 's,^etc/default/jetty,pg_migration/server_files/etc/default/jetty,' \\
        --transform 's,^home/smoothie/Scripts,pg_migration/server_files/home/smoothie/Scripts,' \\
        --transform 's,^etc/ssh/ssh_host,pg_migration/server_files/etc/ssh/ssh_host,' \\
        --transform 's,^etc/salt/minion_id,pg_migration/server_files/etc/salt/minion_id,' \\
        --transform 's,^home/smoothie/bi_cube,pg_migration/server_files/home/smoothie/bi_cube,' \\
        --transform 's,^etc/profile.d/ibp,pg_migration/server_files/etc/profile.d/ibp,' \\
        --exclude='opt/fluent-bit' \\
        -C / opt/ \\
        -C / etc/default/ jetty \\
        -C / home/smoothie/ Scripts/ \\
        -C / etc/ssh/ ssh_host* \\
        -C / etc/salt/ minion_id \\
        -C / home/smoothie/ bi_cube* \\
        -C / etc/profile.d/ ibp* 2>/dev/null || true
    else
      cd /tmp && sudo -u root tar --use-compress-program="zstd -T0 -3" -cf pg_dumps.tar.zst \\
        pg_migration/dumps/ \\
        --transform 's,^opt,pg_migration/server_files/opt,' \\
        --transform 's,^etc/default/jetty,pg_migration/server_files/etc/default/jetty,' \\
        --transform 's,^home/smoothie/Scripts,pg_migration/server_files/home/smoothie/Scripts,' \\
        --transform 's,^etc/ssh/ssh_host,pg_migration/server_files/etc/ssh/ssh_host,' \\
        --transform 's,^etc/salt/minion_id,pg_migration/server_files/etc/salt/minion_id,' \\
        --exclude='opt/fluent-bit' \\
        -C / opt/ \\
        -C / etc/default/ jetty \\
        -C / home/smoothie/ Scripts/ \\
        -C / etc/ssh/ ssh_host* \\
        -C / etc/salt/ minion_id 2>/dev/null || true
    fi
    
    archive_size=\$(du -sh /tmp/pg_dumps.tar.zst | awk '{print \$1}')
    info " - TAR SIZE: \${archive_size}"
    
    sudo chown smoothie:smoothie /tmp/pg_dumps.tar.zst
ENDSSH
  success "[☑️] Created: /tmp/pg_dumps.tar.zst"
}

function extract_archive() {
  info "[⏳] EXTRACTING TAR FILE: on destination"

  # NOTE: The tar file will extract to the following structure:
  #
  # /tmp/pg_migration/
  # ├── dumps/                    # Database dumps from dump_databases()
  # │   ├── globals.sql
  # │   └── *.dump/
  # └── server_files/             # Server configuration files
  #     ├── opt/
  #     ├── etc/
  #     │   ├── default/jetty
  #     │   ├── ssh/ssh_host*
  #     │   └── salt/minion_id
  #     └── home/smoothie/Scripts/

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    sudo apt install zstd -y -qq > /dev/null 2>&1
    sleep 1
    cd /tmp && sudo -u root tar --use-compress-program="zstd -T0" -xf pg_dumps.tar.zst
ENDSSH
  success "[☑️] Extracted: /tmp/pg_migration"
}

function generate_checksums() {
  echo
  info "[⏳] Generating MD5 checksum: /tmp/pg_dumps.tar.zst"

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    sudo -u smoothie touch /tmp/checksums.txt
    #cd /tmp && sudo -u root md5sum pg_dumps.tar.zst > /tmp/checksums.txt
    sudo chown smoothie:smoothie /tmp/checksums.txt
ENDSSH
  success "[☑️] Checksum generated: /tmp/checksums.txt"
}

function validate_checksums() {
  # info "[⏳] Validating checksums on destination..."
  # # ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "cd /tmp && md5sum -c checksums.txt" || {
  # #   error "Checksum validation failed"
  # #   return 1
  # # }
  success "[☑️] Checksums validated"
}

function transfer_to_destination() {
  info "[⏳] TAR FILE TRANSFER: SOURCE ---> JUMPBOX ---> DESTINATION"

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "mkdir -p ${BACKUP_DIR} 2>/dev/null" || {
    error "Failed to create directory '${BACKUP_DIR}' on destination"
    return 1
  }

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<'ENDSSH'
    function info() {
      printf '\033[1;34m[%s]: %s\033[0m\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
    }
    archive_size=$(du -sh /tmp/pg_dumps.tar.zst | awk '{print $1}')
    info "  [-] TAR SIZE: ${archive_size}"
ENDSSH

  transfer_via_jumpbox || return 1

  success "[☑️] 🎉 TAR FILE TRANSFER: done 🎉"
}

function transfer_via_jumpbox() {
  info "  [-] COPYING: SOURCE ---> JUMPBOX"
  mkdir -p /tmp/pg_transfer

  # TODO: NB => USE THIS INSTEAD:
  # SOURCE_HOST=xylem
  # DEST_HOST=172.20.21.152 (basearm_u22)
  #
  # ssh "$SOURCE_SSH_USER@$SOURCE_HOST" "cd /tmp && sudo -u root tar cf - pg_migration/dumps/ --exclude='opt/fluent-bit' -C / opt/ -C / etc/default/ jetty -C / home/smoothie/ Scripts/ -C / etc/ssh/ ssh_host* -C / etc/salt/ minion_id | zstd -T0 -3" | ssh "$DEST_SSH_USER@$DEST_HOST" "cat > /tmp/pg_dumps.tar.zst"
  #
  # ## Benefits Including Disk & IOPS Considerations
  #
  # ### JUMPBOX (Minimal Impact)
  # Disk Space: 0 bytes used
  # • Data streams through memory buffers only
  # • No files written to disk
  #
  # IOPS: ~0 disk operations
  # • Only SSH process memory and network I/O
  # • No disk read/write operations
  #
  # ### SOURCE_HOST (Optimal Efficiency)
  # Disk Space: 0 bytes additional storage
  # • No intermediate tar.zst file created
  # • Only reads existing 18.44 GB of backup files
  #
  # IOPS: Read-only operations
  # • Sequential reads of backup files (~350 files)
  # • No write IOPS consumed
  # • Saves ~18.44 GB of write IOPS + subsequent read IOPS if file was created locally
  #
  # Estimated IOPS saved:
  # • Avoids writing compressed archive: ~4,000-6,000 write IOPS (for ~5-7 GB compressed)
  # • Avoids reading it back for transfer: ~4,000-6,000 read IOPS
  # • **Total: ~8,000-12,000 IOPS saved**
  #
  # ### DEST_HOST (Write-Only)
  # Disk Space: Only final compressed file (~5-7 GB estimated)
  # • Single compressed archive written
  # • No intermediate uncompressed data
  #
  # IOPS: Write-only operations
  # • Sequential writes of compressed stream
  # • ~4,000-6,000 write IOPS for final file

  rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args --human-readable -e "ssh -q" "${SOURCE_SSH_USER}@${SOURCE_HOST}:/tmp/pg_dumps.tar.zst" "${SOURCE_SSH_USER}@${SOURCE_HOST}:/tmp/checksums.txt" /tmp/pg_transfer/ || {
    error "Failed to pull from source"
    return 1
  }

  info "  [-] COPYING: JUMPBOX ---> DESTINATION"
  rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args --human-readable -e "ssh -q" /tmp/pg_transfer/pg_dumps.tar.zst /tmp/pg_transfer/checksums.txt "${DEST_SSH_USER}@${DEST_HOST}:/tmp/" || {
    error "Failed to push to destination"
    return 1
  }
}

function restore_globals() {
  info "[⏳] Restoring global objects..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -v ON_ERROR_STOP=0 -f ${BACKUP_DIR}/globals.sql" || {
    warn "Some global objects already exist (this is normal)"
  }

  success "[☑️] Global objects restored"
}

#######################################
# Restores all databases on destination server in parallel using pg_restore.
# Drops existing databases, recreates them, and restores with optimal parallelism based on CPU cores.
# Returns:
#   0 on success, 1 if any database restore fails
#######################################
function restore_databases() {
  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "ls -d ${BACKUP_DIR}/*.dump 2>/dev/null" | xargs -n1 basename | sed 's/.dump$//')
  if [[ -z "${databases}" ]]; then
    warn "No database dumps found"
    return 0
  fi

  echo "-------------------------------------"
  echo "-- SUMMARY OF DATABASES TO RESTORE --"
  echo "-------------------------------------"
  echo "${databases}"
  echo "-------------------------------------"
  echo

  info "[⏳] Restoring databases in parallel..."
  
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    databases=\$(ls -d ${BACKUP_DIR}/*.dump 2>/dev/null | xargs -n1 basename | sed 's/.dump\$//')
    
    if [[ -z "\${databases}" ]]; then
      echo "WARN: No database dumps found"
      exit 0
    fi
    
    cpu_cores=\$(nproc)
    half_cores=\$((cpu_cores / 2))
    parallel_jobs=\$((half_cores / 2))
    if (( parallel_jobs < 2 )); then
      parallel_jobs=2
    fi
    
    echo "INFO: Using \${parallel_jobs} parallel jobs per database restore"
    echo
    echo "INFO: Starting parallel database restores..."
    
    pids=()
    failed=0
    
    for db in \${databases}; do
      (
        echo "INFO: [START] Restoring database: \${db}"
        
        if sudo -u postgres psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "DROP DATABASE IF EXISTS \${db};" && \
           sudo -u postgres createdb -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} \${db} && \
           pg_restore -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -j \${parallel_jobs} -d \${db} ${BACKUP_DIR}/\${db}.dump; then
          echo "INFO: [DONE] Successfully restored database: \${db}"
        else
          echo "ERROR: [FAILED] Failed to restore database: \${db}"
          exit 1
        fi
      ) &
      pids+=(\$!)
    done
    
    echo "INFO: Waiting for all database restores to complete..."
    for pid in "\${pids[@]}"; do
      if ! wait "\${pid}"; then
        failed=1
      fi
    done
    
    if [[ \${failed} -eq 1 ]]; then
      echo "ERROR: One or more database restores failed"
      exit 1
    fi
    
    echo "INFO: All database restores completed successfully"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Database restore failed"
    return 1
  fi

  success "[☑️] All databases restored"
}

function run_analyse() {
  echo
  info "[⏳] Executing ANALYZE on all databases..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info " - Analysing database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'ANALYZE VERBOSE;' 2>/dev/null" || {
      warn "[⚠️] ANALYZE failed for ${db}"
    }
  done

  success "[☑️] ANALYZE completed"
}

function run_vacuum() {
  echo
  info "[⏳] Executing VACUUM ANALYZE on all databases..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info " - Vacuuming database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'VACUUM ANALYZE;'" || {
      warn "[⚠️] VACUUM failed for ${db}"
    }
  done

  success "[☑️] VACUUM completed"
}

function run_reindex() {
  echo
  info "[⏳] Executing REINDEX on all databases..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    sleep 1
    info " - Re-Indexing database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'REINDEX DATABASE ${db};'" || {
      warn "[⚠️] REINDEX failed for ${db}"
    }
  done

  success "[☑️] REINDEX completed"
}

function validate_row_counts() {
  echo
  info "[⏳] Validating table row counts..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info " - Checking row counts for database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'SELECT schemaname, relname, n_live_tup FROM pg_stat_user_tables ORDER BY schemaname, relname;'" || {
      warn "[⚠️] Row count validation failed for ${db}"
    }
  done

  success "[☑️] Row count validation completed"
}

function validate_constraints() {
  echo
  info "[⏳] Validating constraints..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info " - Checking constraints for database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'SELECT conname, contype, convalidated FROM pg_constraint;' 2>/dev/null" || {
      warn "[⚠️] Constraint validation failed for ${db}"
    }
  done

  success "[☑️] Constraint validation completed"
}

function validate_extensions() {
  echo
  info "[⏳] Validating extensions..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info " - Checking extensions for database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'SELECT extname, extversion FROM pg_extension;'" || {
      warn "[⚠️] Extension validation failed for ${db}"
    }
  done

  success "[☑️] Extension validation completed"
}

function stopdw_source() {
  echo
  info "[⏳] Stopping DW on SOURCE..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo -u smoothie stopdw" || {
    error "Execution of stopdw failed."
    return 1
  }
}

function stopdw_dest() {
  echo
  info "[⏳] Stopping DW on DEST..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo -u smoothie stopdw" || {
    error "Execution of stopdw failed."
    return 1
  }
}

function startdw_source() {
  echo
  info "[⏳] Starting DW on SOURCE..."
  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo -u smoothie startdw" || {
    error "Execution of startdw failed."
    return 1
  }
  # NOTE: We want to sleep for 3s before starting the archiving process
  #       otherwise we overwhelm the startdw process.
  sleep 3
}

function startdw_dest() {
  echo
  info "[⏳] Starting DW on DEST..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo -u smoothie startdw" || {
    error "Execution of startdw failed."
    return 1
  }
}

# Restores server configuration files from the backup archive to their original locations 
# on the destination server, including jetty config, SSH host keys, salt minion ID,
# smoothie scripts and bi_cube files if present
function restore_server_files() { 
  info "[⏳] Moving source files to final locations on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    sudo -u root rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args ${SERVER_FILES_BACKUP_DIR}/etc/default/jetty /etc/default/
    
    sudo -u root rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args ${SERVER_FILES_BACKUP_DIR}/etc/ssh/ /etc/ssh/
    
    sudo -u root rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args ${SERVER_FILES_BACKUP_DIR}/etc/salt/minion_id /etc/salt/
    
    sudo -u root rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args ${SERVER_FILES_BACKUP_DIR}/home/ /home/
    
    sudo -u root rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args ${SERVER_FILES_BACKUP_DIR}/opt/ /opt/

    # Restore bi_cube files
    sudo -u root rsync -a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args ${SERVER_FILES_BACKUP_DIR}/etc/profile.d/ /etc/profile.d/
ENDSSH

  if [[ $? -ne 0 ]]; then
    warn "[⚠️] Failed to move server files to final locations on destination"
    return 0
  fi

  success "[☑️] Restored source server files"
}

function rename_smoothie_folder() {
  info "[⏳] Renaming /opt/smoothie11 to /opt/smoothie11_old on destination..."
  
  if ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "test -d /opt/smoothie11"; then
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo mv /opt/smoothie11 /opt/smoothie11_old" || {
      error "Failed to rename /opt/smoothie11 to /opt/smoothie11_old"
      return 1
    }
    success "[☑️] Successfully renamed /opt/smoothie11 to /opt/smoothie11_old"
  elif ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "test -d /opt/smoothie11_old"; then
    success "[☑️] /opt/smoothie11_old already exists - skipping rename"
  else
    warn "Neither /opt/smoothie11 nor /opt/smoothie11_old exists - skipping rename"
  fi
}

#######################################
# Configures bi_cube environment on destination server including file ownership,
# Python virtual environment creation, and required package installation.
# Returns:
#   0 on success, 1 if virtual environment setup fails
#######################################
function configure_bi_cube_on_dest() {
  if [[ "${BI_CUBE_DETECTED}" != "true" ]]; then
    info "[ℹ️] bi_cube not detected - skipping setup"
    return 0
  fi
  
  echo
  info "[⏳] Configuring bi_cube on destination..."
  
  if true; then
    info " - bi_cube: setup is required"
    info " - bi_cube: setting ownership"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
      sudo chown -R smoothie:smoothie /tmp/pg_migration/server_files/etc/profile.d/ibp*
      sudo chown -R smoothie:smoothie /tmp/pg_migration/server_files/home/smoothie/bi_cube*
      for script in bi_cube_fetch_logs_connections.sh bi_cube_fetch_logs_queries.sh bi_cube_whitelist_ips.sh; do
        if [[ -f "/tmp/pg_migration/server_files/home/smoothie/${script}" ]]; then
          sudo chown root:smoothie "/tmp/pg_migration/server_files/home/smoothie/${script}"
        fi
      done
ENDSSH
    success " - bi_cube: ownership successfully set"

    info "[⏳] Cleaning up old bi_cube installation..."
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo rm -rf /opt/bi_cube_ip_whitelist/{bin,lib}" || {
      warn "[⚠️] Failed to remove old bi_cube directories (may not exist)"
    }

    info "[⏳] Installing python3-venv for bi_cube"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
      sudo apt install -y python3-venv
      python3 -m venv /opt/bi_cube_ip_whitelist/ || exit 1
      source /opt/bi_cube_ip_whitelist/bin/activate
      pip install boto3 mysql-connector-python psycopg2-binary privatebinapi || exit 1
ENDSSH
    if [[ $? -ne 0 ]]; then
      error "Failed to create virtual environment or install packages"
      return 1
    fi
    success "[☑️] Python virtual environment created and packages installed"
    success "[☑️] bi_cube setup completed successfully"
  else
    info " - bi_cube: setup is not required"
    return 0
  fi
}

#######################################
# Synchronizes timezone configuration from source to destination server.
# Attempts multiple methods to read timezone and verifies successful application.
# Returns:
#   0 on success, 1 if timezone cannot be determined or set
#######################################
function sync_timezone() {
  echo
  info "[⏳] Synchronizing timezone from source to destination..."

  info " - Reading timezone from source server..."
  local source_timezone
  source_timezone=$(ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "cat /etc/timezone 2>/dev/null")

  if [[ -z "${source_timezone}" ]]; then
    warn "Could not read /etc/timezone from source, trying timedatectl..."
    source_timezone=$(ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "timedatectl show -p Timezone --value 2>/dev/null")
  fi

  if [[ -z "${source_timezone}" ]]; then
    error "Failed to determine timezone from source server"
    return 1
  fi

  success " - Source timezone: ${source_timezone}"
  info " - Getting current timezone on destination..."

  local dest_timezone
  dest_timezone=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "cat /etc/timezone 2>/dev/null")

  if [[ -z "${dest_timezone}" ]]; then
    dest_timezone=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "timedatectl show -p Timezone --value 2>/dev/null")
  fi

  if [[ -n "${dest_timezone}" ]]; then
    info " - Current destination timezone: ${dest_timezone}"
  fi

  if [[ "${source_timezone}" == "${dest_timezone}" ]]; then
    success "[☑️] Timezones already match - no changes needed"
    return 0
  fi

  info " - Setting timezone on destination to: ${source_timezone}"
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo timedatectl set-timezone ${source_timezone}"

  info " - Verifying timezone change..."
  local new_timezone
  new_timezone=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "timedatectl show -p Timezone --value 2>/dev/null")

  if [[ "${new_timezone}" == "${source_timezone}" ]]; then
    success "[☑️] Timezone successfully synchronized to: ${source_timezone}"
  else
    error "Timezone verification failed. Expected: ${source_timezone}, Got: ${new_timezone}"
    return 1
  fi

  return 0
}

function reseed_dest_hostkey_to_knownhosts_file() {
  echo
  info "[⏳] Preload the destination SSH host key to '/home/smoothie/.ssh/known_hosts'"

  sudo -u smoothie ssh-keygen -f "/home/smoothie/.ssh/known_hosts" -R "$DEST_HOST" >/dev/null 2>&1 </dev/null
  sudo -u smoothie ssh-keyscan $DEST_HOST >> "/home/smoothie/.ssh/known_hosts" 2>&1 </dev/null

  success "[☑️] Successfully added the destination SSH host key to '/home/smoothie/.ssh/known_hosts'"
}

function update_hosts_file_dest() {
  echo
  info "[⏳] Retrieving source hostname from local /etc/hosts..."
  local source_hostname
  source_hostname=$(grep -i "${SOURCE_HOST}" /etc/hosts | awk '{print $2}')

  if [[ -z "${source_hostname}" ]]; then
    error "Failed to retrieve hostname for ${SOURCE_HOST} from local /etc/hosts"
    return 1
  fi

  success " - Source hostname: ${source_hostname}"
  info " - Updating /etc/hosts file on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    sudo hostnamectl set-hostname "${source_hostname}"
    sudo sed -i '/^127.0.0.1.*localhost/d' /etc/hosts
    echo "127.0.0.1 localhost ${source_hostname}" | sudo tee -a /etc/hosts > /dev/null
ENDSSH

  if [[ $? -ne 0 ]]; then
    warn "[⚠️] Failed to update /etc/hosts file on destination"
    return 0
  fi

  success "[☑️] Successfully updated /etc/hosts on destination"
}

#######################################
# Updates bash PS1 prompt in .bashrc on destination to reflect the source hostname.
# Searches for basearm pattern and replaces with actual hostname.
# Returns:
#   0 on success or if pattern not found
#######################################
function update_bashrc_ps1_dest() {
  echo
  info "[⏳] Updating PS1 prompt in /home/smoothie/.bashrc on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<'ENDSSH'
    hostname=$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)
    echo "  [-] HOSTNAME: ${hostname}"
    echo

    if [[ -z "${hostname}" ]]; then
      echo "ERROR: Failed to retrieve hostname"
      exit 1
    fi

    if grep -q 'PS1="basearm-' /home/smoothie/.bashrc; then
      tmpfile=$(mktemp) || exit 1
      sed "s|PS1=\"basearm-[^\\]*\\\\w> \"|PS1=\"${hostname}\\\\w> \"|" /home/smoothie/.bashrc > "${tmpfile}" || exit 1
      cat "${tmpfile}" > /home/smoothie/.bashrc || exit 1
      rm -f "${tmpfile}"
      
      if grep -q "PS1=\"${hostname}" /home/smoothie/.bashrc; then
        echo "SUCCESS: PS1 updated to ${hostname}"
      else
        echo "ERROR: PS1 update verification failed"
        exit 1
      fi
    else
      echo "WARN: No basearm PS1 entry found in .bashrc"
      exit 0
    fi
ENDSSH

  if [[ $? -ne 0 ]]; then
    warn "[⚠️] Failed to update PS1 in .bashrc on destination"
    return 0
  fi

  success "[☑️] Successfully updated PS1 prompt in .bashrc"
  info "Note: Changes will take effect on next SSH login"
}

function apply_mambo_cron_schedules() {
  echo
  info "[⏳] Applying mambo crontab schedules..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    sudo -u smoothie /opt/smoothie11/mambo/UpdateSchedule.sh
    echo
    sudo -u smoothie crontab -l
ENDSSH

  if [[ $? -ne 0 ]]; then
    warn "[⚠️] Failed to apply mambo crontab schedules"
    return 0
  fi

  success "[☑️] Crontab schedules applied"
}

function update_host_key() {
  echo
  info "[⏳] Updating host key for ${SOURCE_HOST}..."
  local source_hostname
  source_hostname=$(grep -i "${SOURCE_HOST}" /etc/hosts | awk '{print $2}')
  sudo /home/smoothie/update_known_hosts.sh $source_hostname || {
    error "Failed to update host key for ${source_hostname}"
    return 1
  }

  success "[☑️] Updated host key for $source_hostname"
}

function final_cleanup() {
  echo
  info "[⏳] Performing final cleanup..."
  info "  [-] Cleaning up SOURCE_HOST: ${SOURCE_HOST}"

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    # TODO: Uncomment the commented statements below
    sudo rm -rf /tmp/pg_migration 2>/dev/null
    sudo rm -f /tmp/pg_dumps.tar.zst 2>/dev/null
    sudo rm -f /tmp/checksums.txt 2>/dev/null
ENDSSH

  if [[ $? -ne 0 ]]; then
    warn "Failed to perform final cleanup on source"
    return 1
  fi

  info "  [-] Cleaning up DEST_HOST: ${DEST_HOST}"
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    # TODO: Uncomment the commented statements below
    # sudo rm -rf /opt/smoothie11_old 2>/dev/null
    sudo rm -rf /tmp/etc 2>/dev/null
    sudo rm -rf /tmp/home 2>/dev/null
    sudo rm -rf /tmp/pg_migration 2>/dev/null
    sudo rm -f /tmp/pg_dumps.tar.zst 2>/dev/null
    sudo rm -f /tmp/checksums.txt 2>/dev/null
ENDSSH

  if [[ $? -ne 0 ]]; then
    warn "Failed to perform final cleanup on destination"
    return 1
  fi

  info "Cleaning up jumpbox"
  sudo rm -rf /tmp/pg_transfer 2>/dev/null || {
    warn "Failed to cleanup /tmp/pg_transfer on jumpbox"
  }

  success "[☑️] Final cleanup completed"
}

function show_execution_time() {
  local start_time=$1
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local hours=$((duration / 3600))
  local minutes=$(((duration % 3600) / 60))
  local seconds=$((duration % 60))

  printf '\n%b' "${BOLD_CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
  printf '%b' "${BOLD_WHITE}Execution Time: "

  if (( hours > 0 )); then
    printf '%dh %dm %ds' "${hours}" "${minutes}" "${seconds}"
  elif (( minutes > 0 )); then
    printf '%dm %ds' "${minutes}" "${seconds}"
  else
    printf '%ds' "${seconds}"
  fi

  printf '%b\n' "${RESET}"
  printf '%b' "${BOLD_CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
}

#######################################
# Orchestrates complete end-to-end migration workflow from source to destination.
# Executes all migration phases with timing metrics for each stage.
# Returns:
#   0 on success, 1 if any step fails
#######################################
function full_migration() {
  info "[🚀] Starting full migration process..."
  local start_time
  local full_migration_start_time

  start_time=$(date +%s)
  full_migration_start_time=$(date +%s)
  
  validate_environment || return 1
  check_disk_space_source || return 1
  check_disk_space_dest || return 1
  create_backup_directory || return 1
  stopdw_source || return 1
  stopdw_dest || return 1
  
  start_time=$(date +%s)
  set_maintenance_settings_source || return 1
  export_globals || return 1
  dump_databases || return 1
  revert_maintenance_settings_source || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  startdw_source || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  create_archive || return 1
  generate_checksums || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  transfer_to_destination || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  validate_checksums || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  extract_archive || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  set_maintenance_settings_dest || return 1
  restore_globals || return 1
  restore_databases || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  run_analyse || return 1
  run_vacuum || return 1
  run_reindex || return 1
  validate_row_counts || return 1
  validate_constraints || return 1
  validate_extensions || return 1
  revert_maintenance_settings_dest || return 1
  show_execution_time "${start_time}" || return 1

  rename_smoothie_folder || return 1

  start_time=$(date +%s)
  restore_server_files || return 1
  show_execution_time "${start_time}" || return 1

  start_time=$(date +%s)
  configure_bi_cube_on_dest || return 1
  show_execution_time "${start_time}" || return 1
  
  reseed_dest_hostkey_to_knownhosts_file || return 1
  sync_timezone || return 1
  update_hosts_file_dest || return 1
  update_bashrc_ps1_dest || return 1
  apply_mambo_cron_schedules || return 1
  display_summary_dest || return 1
  update_host_key || return 1
  final_cleanup || return 1

  # TODO: On deploy, remove salt-key -d INSTANCE and salt-key -a INSTANCE
  # TODO: startdw_dest || return 1

  show_execution_time "${full_migration_start_time}" || return 1
  success "[✅] 🎉 Full migration completed successfully! 🎉"
}

function show_menu() {
  # clear
  printf '%b\n' "${BOLD_CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
  printf '%b\n' "${BOLD_CYAN}║ IBP Migration Tool - Ubuntu 22.04 + PG14 (via Jumpbox) ║${RESET}"
  printf '%b\n' "${BOLD_CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
  printf '\n'
  printf '%b\n' "${BOLD_WHITE}Source: ${SOURCE_SSH_USER}@${SOURCE_HOST}${RESET}"
  printf '%b\n' "${BOLD_WHITE}Destination: ${DEST_SSH_USER}@${DEST_HOST}${RESET}"
  printf '%b\n' "${BOLD_WHITE}Backup Directory: /tmp/pg_migration ${RESET}"
  printf '\n'
  printf '%b\n' "${BOLD_GREEN}1)${RESET} Full Migration (All Steps)"
  printf '%b\n' "${BOLD_GREEN}2)${RESET} Pre-Migration (Validate ENV, Disk Space Check & Backup Dir Creation)"
  printf '%b\n' "${BOLD_GREEN}3)${RESET} Dump Databases (SOURCE)"
  printf '%b\n' "${BOLD_GREEN}4)${RESET} Compress and Checksum (SOURCE)"
  printf '%b\n' "${BOLD_GREEN}5)${RESET} Transfer to Destination (SOURCE+DEST)"
  printf '%b\n' "${BOLD_GREEN}6)${RESET} Restore Databases (Extract Archive,Restore Globals,Restore DBs) (DEST)"
  printf '%b\n' "${BOLD_GREEN}7)${RESET} Post-Restore - Maintenance (Analyze,Vacuum,ReIndex) (DEST)"
  printf '%b\n' "${BOLD_GREEN}8)${RESET} Post-Restore - Data Validation Suite (DEST)"
  printf '%b\n' "${BOLD_GREEN}9)${RESET} Print summary of Databases (SOURCE)"
  printf '%b\n' "${BOLD_GREEN}10)${RESET} Print Summary of Databases (DEST)"
  printf '%b\n' "${BOLD_GREEN}11)${RESET} Backup & Restore Server Files (SOURCE+DEST))"
  printf '%b\n' "${BOLD_GREEN}12)${RESET} Rename Smoothie Folder (DEST)"
  printf '%b\n' "${BOLD_GREEN}13)${RESET} Setup bi_cube (DEST)"
  printf '%b\n' "${BOLD_GREEN}14)${RESET} Sync Timezone (DEST)"
  printf '%b\n' "${BOLD_GREEN}15)${RESET} Update /etc/hosts (DEST)"
  printf '%b\n' "${BOLD_GREEN}16)${RESET} Update .bashrc PS1 Prompt (DEST)"
  printf '%b\n' "${BOLD_GREEN}17)${RESET} Apply Mambo Cron Schedules (DEST)"
  printf '%b\n' "${BOLD_GREEN}18)${RESET} Check bi_cube Detection (SOURCE)"
  printf '%b\n' "${BOLD_GREEN}19)${RESET} Final Cleanup (SOURCE+DEST+JUMPBOX)"
  printf '%b\n' "${BOLD_GREEN}20)${RESET} Quit"
  printf '\n'
  printf '%b' "${BOLD_YELLOW}Select option: ${RESET}"
}

function main() {
  prompt_required_config || exit 1

  while true; do
    show_menu
    read -r choice

    local start_time
    start_time=$(date +%s)

    case "${choice}" in
      1)
        full_migration
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      2)
        validate_environment && check_disk_space_source && check_disk_space_dest && create_backup_directory
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      3)
        validate_environment && check_disk_space_source && check_disk_space_dest && create_backup_directory && set_maintenance_settings_source && export_globals && dump_databases && revert_maintenance_settings_source
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      4)
        create_archive && generate_checksums
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      5)
        transfer_to_destination && validate_checksums
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      6)
        extract_archive && set_maintenance_settings_dest && restore_globals && restore_databases && revert_maintenance_settings_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      7)
        set_maintenance_settings_dest && run_analyse && run_vacuum && run_reindex && revert_maintenance_settings_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      8)
        set_maintenance_settings_dest && validate_row_counts && validate_constraints && validate_extensions && revert_maintenance_settings_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      9)
        display_summary
        read -p "Press Enter to continue..."
        ;;
      10)
        display_summary_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      11)
        rename_smoothie_folder && restore_server_files
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      12)
        rename_smoothie_folder
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      13)
        configure_bi_cube_on_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      14)
        sync_timezone
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      15)
        update_hosts_file_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      16)
        update_bashrc_ps1_dest
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      17)
        apply_mambo_cron_schedules
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      18)
        validate_environment
        if [[ "${BI_CUBE_DETECTED}" == "true" ]]; then
          success "[☑️] bi_cube is detected on source"
        else
          info "[ℹ️] bi_cube is NOT detected on source"
        fi
        read -p "Press Enter to continue..."
        ;;
      19)
        final_cleanup
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      20|q)
        info "Exiting..."
        exit 0
        ;;
      *)
        error "Invalid option"
        read -p "Press Enter to continue..."
        ;;
    esac
  done
}

main "$@"
