#!/usr/bin/env bash
#
# PostgreSQL 12 to 14 Migration Tool (via Jumpbox)
# Executes from jumpbox with SSH access to source and destination servers
#
# Author  : Frank Claassens
# Created : 15 October 2025
# Updated : Tue 28 October 2025
#

# Colour constants
readonly BLACK='\033[0;30m' RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m' WHITE='\033[0;37m'
readonly BOLD_BLACK='\033[1;30m' BOLD_RED='\033[1;31m' BOLD_GREEN='\033[1;32m' BOLD_YELLOW='\033[1;33m'
readonly BOLD_BLUE='\033[1;34m' BOLD_MAGENTA='\033[1;35m' BOLD_CYAN='\033[1;36m' BOLD_WHITE='\033[1;37m'
readonly DIM_BLACK='\033[2;30m' DIM_RED='\033[2;31m' DIM_GREEN='\033[2;32m' DIM_YELLOW='\033[2;33m'
readonly DIM_BLUE='\033[2;34m' DIM_MAGENTA='\033[2;35m' DIM_CYAN='\033[2;36m' DIM_WHITE='\033[2;37m'
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
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
PG_USER="postgres"

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
  printf '%b[%s]: %s%b\n\n' "${BOLD_GREEN}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}"
}

function error() {
  [[ -z "$1" ]] && { err "error: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_RED}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}" >&2
}

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
}

function check_disk_space_source() {
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
  info "[⏳] Checking disk space on dest server..."

  local available
  available=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "df -BG ${BACKUP_DIR%/*} 2>/dev/null | awk 'NR==2 {print \$4}' | sed 's/G//'")

  if [[ -z "${available}" ]]; then
    available=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "df -BG / | awk 'NR==2 {print \$4}' | sed 's/G//'")
  fi

  if (( available < 10 )); then
    error "Insufficient disk space on source. Available: ${available}GB"
    return 1
  fi

  success "[☑️] Disk space check passed: ${available}GB available on dest"
}

function create_backup_directory() {
  info "Creating backup directory on source server..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "mkdir -p ${BACKUP_DIR}" || {
    error "Failed to create backup directory on source"
    return 1
  }

  success "Backup directory created on source: ${BACKUP_DIR}"
}

function export_globals() {
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

function set_maintenance_settings_source() {
  info "[⏳] Setting temporary maintenance settings on source..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    cpu_cores=\$(nproc)
    half_cores=\$((cpu_cores / 2))
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET maintenance_work_mem = '2GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET max_parallel_maintenance_workers = \${cpu_cores};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET max_parallel_workers_per_gather = \${half_cores};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET checkpoint_timeout = '1h';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET max_wal_size = '64GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "SELECT pg_reload_conf();"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to set maintenance settings on source"
    return 1
  fi

  success "[☑️] Maintenance settings applied on source"
}

function set_maintenance_settings_dest() {
  info "[⏳] Setting temporary maintenance settings on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    cpu_cores=\$(nproc)
    half_cores=\$((cpu_cores / 2))
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET maintenance_work_mem = '2GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET max_parallel_maintenance_workers = \${cpu_cores};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET max_parallel_workers_per_gather = \${half_cores};" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET checkpoint_timeout = '1h';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM SET max_wal_size = '64GB';" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "SELECT pg_reload_conf();"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to set maintenance settings on destination"
    return 1
  fi

  success "[☑️] Maintenance settings applied on destination"
}

function revert_maintenance_settings_source() {
  info "[⏳] Reverting maintenance settings to defaults on source..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET maintenance_work_mem;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET max_parallel_maintenance_workers;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET max_parallel_workers_per_gather;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET checkpoint_timeout;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET max_wal_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "SELECT pg_reload_conf();"
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
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET maintenance_work_mem;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET max_parallel_maintenance_workers;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET max_parallel_workers_per_gather;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET checkpoint_timeout;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "ALTER SYSTEM RESET max_wal_size;" && \
    psql -h 127.0.0.1 -U ${PG_USER} -p 27095 -c "SELECT pg_reload_conf();"
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to revert maintenance settings on destination"
    return 1
  fi

  success "[☑️] Maintenance settings reverted to defaults on destination"
}

function dump_databases() {
  display_summary

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo find ${BACKUP_DIR} -mindepth 1 ! -name 'globals.sql' -exec rm -rf {} + 2>/dev/null || true" || {
    error "Failed to clear backup directory"
    return 1
  }

  info "[⏳] Dumping databases in parallel..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    databases=\$(psql -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');")
    echo "FOUND THESE DATABASES TO DUMP: ${databases}"

    if [[ -z "\${databases}" ]]; then
      echo "WARN: No user databases found"
      exit 0
    fi

    max_concurrent=4
    count=0
    pids=()

    for db in \${databases}; do
      echo "INFO: Dumping database: \${db}"
      mkdir -p ${BACKUP_DIR}/\${db}.dump
      pg_dump -h 127.0.0.1 -U ${PG_USER} -p ${SOURCE_PORT} -Fd -j ${PARALLEL_JOBS} -f ${BACKUP_DIR}/\${db}.dump \${db} &
      pids+=(\$!)
      ((count++))

      if (( count >= max_concurrent )); then
        for pid in "\${pids[@]}"; do
          wait "\${pid}" || exit 1
        done
        pids=()
        count=0
      fi
    done

    for pid in "\${pids[@]}"; do
      wait "\${pid}" || exit 1
    done

    chmod -R 700 ${BACKUP_DIR}/*.dump
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Database dump failed"
    return 1
  fi

  success "[☑️] All databases dumped successfully"
}

function create_archive() {
  info "[⏳] Creating compressed archive on source..."
  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    function info() {
      printf '\033[1;34m[%s]: %s\033[0m\n' "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*"
    }
    sudo apt install zstd -y -qq > /dev/null 2>&1
    pg_migration_dir_size=\$(sudo du -sh /tmp/pg_migration)
    info "  [-] Total size: \$pg_migration_dir_size"

    cd /tmp && sudo -u root tar -I 'zstd -3 -T0' -cf pg_dumps.tar.zst pg_migration/
    sudo chown smoothie:smoothie /tmp/pg_dumps.tar.zst
ENDSSH
  success "[☑️] Archive created: /tmp/pg_dumps.tar.zst"
}

function generate_checksums() {
  info "[⏳] Generating checksums on source..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    cd /tmp && sudo -u root sha256sum pg_dumps.tar.zst > /tmp/checksums.txt
    sudo chown smoothie:smoothie /tmp/checksums.txt
ENDSSH
  success "[☑️] Checksums generated: /tmp/checksums.txt"
}

function transfer_to_destination() {
  info "Transferring archive to destination..."

  if [[ -z "${DEST_HOST}" ]]; then
    read -p "Destination Host: " DEST_HOST
    if [[ -z "${DEST_HOST}" ]]; then
      error "Destination host is required"
      return 1
    fi
  fi

  if [[ -z "${DEST_PORT}" ]]; then
    read -p "Destination Port [27095]: " input_port
    DEST_PORT="${input_port:-27095}"
  fi

  if [[ -z "${DEST_SSH_USER}" ]]; then
    read -p "Destination SSH User: " DEST_SSH_USER
    if [[ -z "${DEST_SSH_USER}" ]]; then
      error "Destination SSH user is required"
      return 1
    fi
  fi

  info "Connecting to ${DEST_SSH_USER}@${DEST_HOST}"

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "mkdir -p ${BACKUP_DIR} 2>/dev/null" || {
    error "Failed to create destination directory"
    return 1
  }

  info "[⏳] Pulling files from source to jumpbox..."
  mkdir -p /tmp/pg_transfer
  rsync -az --progress -e "ssh -q" "${SOURCE_SSH_USER}@${SOURCE_HOST}:/tmp/pg_dumps.tar.zst" "${SOURCE_SSH_USER}@${SOURCE_HOST}:/tmp/checksums.txt" /tmp/pg_transfer/ || {
    error "Failed to pull from source"
    return 1
  }

  info "[⏳] Pushing files from jumpbox to destination..."
  rsync -az --progress -e "ssh -q" /tmp/pg_transfer/pg_dumps.tar.zst /tmp/pg_transfer/checksums.txt "${DEST_SSH_USER}@${DEST_HOST}:/tmp/" || {
    error "Failed to push to destination"
    return 1
  }

  rm -rf /tmp/pg_transfer
  success "[☑️] Transfer completed"
}

function validate_checksums() {
  info "[⏳] Validating checksums on destination..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "cd /tmp && sha256sum -c checksums.txt" || {
    error "Checksum validation failed"
    return 1
  }

  success "[☑️] Checksums validated"
}

function extract_archive() {
  info "[⏳] Extracting archive on destination..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    sudo apt install zstd -y -qq > /dev/null 2>&1
    sleep 1
    cd /tmp && sudo -u root tar -I zstd -xf pg_dumps.tar.zst
ENDSSH
  success "[☑️] Archive extracted"
}

function restore_globals() {
  info "[⏳] Restoring global objects..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -v ON_ERROR_STOP=0 -f ${BACKUP_DIR}/globals.sql" || {
    warn "Some global objects already exist (this is normal)"
  }

  success "[☑️] Global objects restored"
}

function restore_databases() {
  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "ls -d ${BACKUP_DIR}/*.dump 2>/dev/null" | xargs -n1 basename | sed 's/.dump$//')
  if [[ -z "${databases}" ]]; then
    warn "No database dumps found"
    return 0
  fi

  echo -e "-------------------------------------"
  echo -e "-- SUMMARY OF DATABASES TO RESTORE --"
  echo -e "-------------------------------------"
  echo -e "${databases}"
  echo -e "-------------------------------------"
  echo ""

  info "[⏳] Restoring databases in parallel..."
  for db in ${databases}; do
    info "Restoring database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
      psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -c "DROP DATABASE IF EXISTS ${db};" || exit 1
      createdb -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} ${db} || exit 1
      pg_restore -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -j ${PARALLEL_JOBS} -d ${db} ${BACKUP_DIR}/${db}.dump || exit 1
ENDSSH
    if [[ $? -ne 0 ]]; then
      error "Failed to restore database: ${db}"
      return 1
    fi
  done

  success "[☑️] All databases restored"
}

function run_analyze() {
  info "[⏳] Running ANALYZE on all databases..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info "Analyzing database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'ANALYZE VERBOSE;'" || {
      warn "ANALYZE failed for ${db}"
    }
  done

  success "[☑️] ANALYZE completed"
}

function run_vacuum() {
  info "[⏳] Running VACUUM ANALYZE on all databases..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info "Vacuuming database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'VACUUM ANALYZE;'" || {
      warn "VACUUM failed for ${db}"
    }
  done

  success "[☑️] VACUUM completed"
}

function run_reindex() {
  info "[⏳] Running REINDEX on all databases..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info "Reindexing database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'REINDEX DATABASE ${db};'" || {
      warn "REINDEX failed for ${db}"
    }
  done

  success "[☑️] REINDEX completed"
}

function validate_row_counts() {
  info "[⏳] Validating table row counts..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info "Checking row counts for database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'SELECT schemaname, relname, n_live_tup FROM pg_stat_user_tables ORDER BY schemaname, relname;'" || {
      warn "Row count validation failed for ${db}"
    }
  done

  success "[☑️] Row count validation completed"
}

function validate_constraints() {
  info "[⏳] Validating constraints..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info "Checking constraints for database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'SELECT conname, contype, convalidated FROM pg_constraint;'" || {
      warn "Constraint validation failed for ${db}"
    }
  done

  success "[☑️] Constraint validation completed"
}

function validate_extensions() {
  info "[⏳] Validating extensions..."

  local databases
  databases=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -t -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');\"")

  for db in ${databases}; do
    info "Checking extensions for database: ${db}"
    ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "psql -h 127.0.0.1 -U ${PG_USER} -p ${DEST_PORT} -d ${db} -c 'SELECT extname, extversion FROM pg_extension;'" || {
      warn "Extension validation failed for ${db}"
    }
  done

  success "[☑️] Extension validation completed"
}

function stopdw_source() {
  info "[⏳] Stopping DW on SOURCE..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo -u smoothie stopdw" || {
    error "Execution of stopdw failed."
    return 1
  }
}

function stopdw_dest() {
  info "[⏳] Stopping DW on DEST..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo -u smoothie stopdw" || {
    error "Execution of stopdw failed."
    return 1
  }
}

function startdw_source() {
  info "[⏳] Starting DW on SOURCE..."

  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "sudo -u smoothie startdw" || {
    error "Execution of startdw failed."
    return 1
  }
}

function startdw_dest() {
  info "[⏳] Starting DW on DEST..."

  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo -u smoothie startdw" || {
    error "Execution of startdw failed."
    return 1
  }
}

function update_host_key() {
  info "[⏳] Updating host key for ${SOURCE_HOST}..."

  # TODO: $SOURCE_HOST WILL MOST LIKELY BE AN IP ADDRESS, ENSURE THAT 
  #       IT RESOLVES TO HOST NAME BY GETTING THE HOST ENTRY ON LASTION FROM /etc/hosts
  # THE BELOW SCRIPT EXPECTS THE HOSTNAME, NOT THE IP
  sudo /home/smoothie/update_known_hosts.sh $SOURCE_HOST
}

function backup_server_files() {
  info "[⏳] Backing up server files on source..."
  ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" bash <<ENDSSH
    function info() {
      printf '%b[%s]: %s%b\n' "\033[1;34m" "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*" "\033[0m"
    }
    function warn() {
      printf '%b[%s]: %s%b\n' "\033[1;33m" "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*" "\033[0m"
    }
    function error() {
      printf '%b[%s]: %s%b\n' "\033[1;31m" "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*" "\033[0m" >&2
    }
    function success() {
      printf '%b[%s]: %s%b\n\n' "\033[1;32m" "\$(date +'%Y-%m-%d %H:%M:%S')" "\$*" "\033[0m"
    }

    mkdir -p "${SERVER_FILES_BACKUP_DIR}" || {
      error "Failed to create server files backup directory"
      return 1
    }

    info "Copying /opt/ from source..."
    sudo -u root rsync -avPHz --relative /opt/ "${SERVER_FILES_BACKUP_DIR}/" || {
      warn "Failed to copy /opt/* (may not exist or be empty)"
    }

    info "Copying /etc/default/jetty from source..."
    sudo -u root rsync -avPHz --relative /etc/default/jetty "${SERVER_FILES_BACKUP_DIR}/" || {
      warn "Failed to copy /etc/default/jetty (may not exist)"
    }

    info "Copying /home/smoothie/Scripts/* from source..."
    sudo -u root rsync -avPHz --relative /home/smoothie/Scripts/ "${SERVER_FILES_BACKUP_DIR}/" || {
      warn "Failed to copy /home/smoothie/Scripts/* (may not exist or be empty)"
    }

    info "Copying SSH host keys from source..."
    sudo -u root rsync -avPHz --relative /etc/ssh/ssh_host* "${SERVER_FILES_BACKUP_DIR}/" || {
      warn "Failed to copy SSH host keys (may not have permissions)"
    }

    success "[☑️] Server files backup completed. Files stored in: ${SERVER_FILES_BACKUP_DIR}"
ENDSSH
}

function restore_server_files() {
  info "[⏳] Restoring server files from jumpbox to destination..."

  if [[ ! -d "${SERVER_FILES_BACKUP_DIR}" ]]; then
    error "Server files backup directory does not exist: ${SERVER_FILES_BACKUP_DIR}"
    return 1
  fi

  local file_count
  file_count=$(find "${SERVER_FILES_BACKUP_DIR}" -type f 2>/dev/null | wc -l)

  if (( file_count == 0 )); then
    warn "No files found in backup directory to restore"
    return 0
  fi

  info "Found ${file_count} files to restore"

  info "[⏳] Creating necessary directories on destination..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo mkdir -p /opt /etc/default /home/smoothie/Scripts /etc/ssh" || {
    error "Failed to create directories on destination"
    return 1
  }

  info "[⏳] Restoring files to destination..."
  rsync -avPHz --relative "${SERVER_FILES_BACKUP_DIR}/"* "${DEST_SSH_USER}@${DEST_HOST}:/tmp/server_files_restore/" || {
    error "Failed to copy files to destination"
    return 1
  }

  info "[⏳] Moving files to final locations on destination (requires sudo)..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    if [[ -d /tmp/server_files_restore ]]; then
      sudo find /tmp/server_files_restore -name "ssh_host*" -exec mv {} /etc/ssh/ \; 2>/dev/null
      sudo find /tmp/server_files_restore -name "jetty" -exec mv {} /etc/default/ \; 2>/dev/null
      sudo find /tmp/server_files_restore -type f ! -name "ssh_host*" ! -name "jetty" -exec mv {} /opt/ \; 2>/dev/null
      sudo rm -rf /tmp/server_files_restore
    fi
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to move files to final locations on destination"
    return 1
  fi

  success "[☑️] Server files restored to destination"
}

function rename_smoothie_folder() {
  info "[⏳] Renaming /opt/smoothie11 to /opt/smoothie11_old on destination..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo mv /opt/smoothie11 /opt/smoothie11_old" || {
    error "Failed to rename /opt/smoothie11 to /opt/smoothie11_old"
    return 1
  }

  success "[☑️] Successfully renamed /opt/smoothie11 to /opt/smoothie11_old"
}

function setup_bi_cube() {
  info "Checking if bi_cube setup is required..."

  # Check if /etc/profile.d/ibp.sh exists on source
  if ! ssh -q "${SOURCE_SSH_USER}@${SOURCE_HOST}" "test -f /etc/profile.d/ibp.sh"; then
    warn "/etc/profile.d/ibp.sh does not exist on source - skipping bi_cube setup"
    return 0
  fi

  success "/etc/profile.d/ibp.sh found on source - proceeding with bi_cube setup"

  info "[⏳] Backing up bi_cube files from source..."
  rsync -avPHz --relative /home/smoothie/bi_cube* "${SERVER_FILES_BACKUP_DIR}/" || {
    warn "Failed to copy bi_cube files from /home/smoothie/ (may not exist)"
  }

  rsync -avPHz --relative /etc/profile.d/ibp* "${SERVER_FILES_BACKUP_DIR}/" || {
    warn "Failed to copy ibp files from /etc/profile.d/ (may not exist)"
  }

  success "[☑️] bi_cube files backed up on source"

#  info "Transferring bi_cube files to destination..."
#  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo mkdir -p ${SERVER_FILES_BACKUP_DIR}" || {
#    error "Failed to create backup directory on destination"
#    return 1
#  }

#  rsync -avPHz --relative "${SERVER_FILES_BACKUP_DIR}/"* "${DEST_SSH_USER}@${DEST_HOST}:${SERVER_FILES_BACKUP_DIR}/" || {
#    error "Failed to transfer bi_cube files to destination"
#    return 1
#  }
#
#  success "bi_cube files transferred to destination"

  info "[⏳] Setting ownership on destination..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    # Set ownership for ibp files
    if ls /tmp/pg_migration/server_files/etc/profile.d/ibp* 1> /dev/null 2>&1; then
      sudo chown smoothie:smoothie /tmp/pg_migration/server_files/etc/profile.d/ibp*
    fi

    # Set ownership for bi_cube files
    if ls /tmp/pg_migration/server_files/home/smoothie/bi_cube* 1> /dev/null 2>&1; then
      sudo chown smoothie:smoothie /tmp/pg_migration/server_files/home/smoothie/bi_cube*
    fi

    # Set specific ownership for shell scripts
    for script in bi_cube_fetch_logs_connections.sh bi_cube_fetch_logs_queries.sh bi_cube_whitelist_ips.sh; do
      if [[ -f "/tmp/pg_migration/server_files/home/smoothie/${script}" ]]; then
        sudo chown root:smoothie "/tmp/pg_migration/server_files/home/smoothie/${script}"
      fi
    done
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to set ownership on destination"
    return 1
  fi

  success "[☑️] Ownership set successfully"

  info "[⏳] Cleaning up old bi_cube installation..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo rm -rf /opt/bi_cube_ip_whitelist/{bin,lib}" || {
    warn "Failed to remove old bi_cube directories (may not exist)"
  }

  info "[⏳] Installing python3-venv on destination..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo apt install -y python3-venv" || {
    error "Failed to install python3-venv"
    return 1
  }

  success "python3-venv installed"

  info "[⏳] Creating Python virtual environment..."
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" bash <<ENDSSH
    # Create venv
    sudo python3 -m venv /opt/bi_cube_ip_whitelist/ || exit 1

    # Install packages
    sudo -u root "/opt/bi_cube_ip_whitelist/bin/pip install boto3 mysql-connector-python psycopg2-binary privatebinapi" || exit 1
ENDSSH

  if [[ $? -ne 0 ]]; then
    error "Failed to create virtual environment or install packages"
    return 1
  fi

  success "Python virtual environment created and packages installed"
  success "bi_cube setup completed successfully"
}

function sync_timezone() {
  info "[⏳] Synchronizing timezone from source to destination..."

  info "Reading timezone from source server..."
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

  success "Source timezone: ${source_timezone}"

  info "Getting current timezone on destination..."
  local dest_timezone
  dest_timezone=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "cat /etc/timezone 2>/dev/null")

  if [[ -z "${dest_timezone}" ]]; then
    dest_timezone=$(ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "timedatectl show -p Timezone --value 2>/dev/null")
  fi

  if [[ -n "${dest_timezone}" ]]; then
    info "Current destination timezone: ${dest_timezone}"
  fi

  if [[ "${source_timezone}" == "${dest_timezone}" ]]; then
    success "[☑️] Timezones already match - no changes needed"
    return 0
  fi

  info "[⏳] Setting timezone on destination to: ${source_timezone}"
  ssh -q "${DEST_SSH_USER}@${DEST_HOST}" "sudo timedatectl set-timezone ${source_timezone}" || {
    error "Failed to set timezone on destination"
    return 1
  }

  info "[⏳] Verifying timezone change..."
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

function full_migration() {
  info "[⏳] Starting full migration process..."

  validate_environment || return 1
  check_disk_space_source || return 1
  check_disk_space_dest || return 1
  create_backup_directory || return 1
  stopdw_source || return 1
  stopdw_dest || return 1
  set_maintenance_settings_source || return 1
  export_globals || return 1
  dump_databases || return 1
  backup_server_files || return 1
  revert_maintenance_settings_source || return 1
  # startdw_source || return 1
  create_archive || return 1
  generate_checksums || return 1
  transfer_to_destination || return 1
  validate_checksums || return 1
  extract_archive || return 1
  set_maintenance_settings_dest || return 1
  restore_globals || return 1
  restore_databases || return 1
  run_analyze || return 1
  run_vacuum || return 1
  run_reindex || return 1
  validate_row_counts || return 1
  validate_constraints || return 1
  validate_extensions || return 1
  revert_maintenance_settings_dest || return 1
  rename_smoothie_folder || return 1
  # restore_server_files || return 1
  # setup_bi_cube || return 1
  sync_timezone || return 1
  #TODO: Add function to update /etc/hosts on dest
  display_summary_dest || return 1
  startdw_dest || return 1
  update_host_key || return 1
  #TODO: On deploy, remove salt-key -d INSTANCE and salt-key -a INSTANCE
  success "[✅] 🎉 Full migration completed successfully! 🎉"
}

function show_menu() {
  clear
  printf '%b\n' "${BOLD_CYAN}╔═════════════════════════════════════════════════╗${RESET}"
  printf '%b\n' "${BOLD_CYAN}║ PostgreSQL 12 → 14 Migration Tool (via Jumpbox) ║${RESET}"
  printf '%b\n' "${BOLD_CYAN}╚═════════════════════════════════════════════════╝${RESET}"
  printf '\n'
  printf '%b\n' "${BOLD_WHITE}Source: ${SOURCE_SSH_USER}@${SOURCE_HOST}:${SOURCE_PORT}${RESET}"
  printf '%b\n' "${BOLD_WHITE}Destination: ${DEST_SSH_USER}@${DEST_HOST}:${DEST_PORT}${RESET}"
  printf '%b\n' "${BOLD_WHITE}Backup Directory: ${BACKUP_DIR}${RESET}"
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
  printf '%b\n' "${BOLD_GREEN}10)${RESET} Backup Server Files (SOURCE)"
  printf '%b\n' "${BOLD_GREEN}11)${RESET} Restore Server Files (DEST))"
  printf '%b\n' "${BOLD_GREEN}12)${RESET} Rename Smoothie Folder (DEST)"
  printf '%b\n' "${BOLD_GREEN}13)${RESET} Setup bi_cube (DEST)"
  printf '%b\n' "${BOLD_GREEN}14)${RESET} Sync Timezone (DEST)"
  printf '%b\n' "${BOLD_GREEN}15)${RESET} Exit"
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
        set_maintenance_settings_dest && run_analyze && run_vacuum && run_reindex && revert_maintenance_settings_dest
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
        backup_server_files
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      11)
        restore_server_files
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      12)
        rename_smoothie_folder
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      13)
        setup_bi_cube
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      14)
        sync_timezone
        show_execution_time "${start_time}"
        read -p "Press Enter to continue..."
        ;;
      15)
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
