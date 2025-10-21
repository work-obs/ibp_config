#!/bin/bash

# PostgreSQL and System Configuration Script for Ubuntu 22.04
# This script configures PostgreSQL database server with optimized settings

set -e  # Exit on error

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Default values
DEFAULT_POSTGRESQL_VERSION=""
DEFAULT_CUSTOM_SQL_SCRIPTS=" "
DEFAULT_ENABLE_NVME="false"

# Function to display usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Configure PostgreSQL and system settings on Ubuntu 22.04

OPTIONS:
    -v, --version VERSION          PostgreSQL version to configure (required)
    -s, --sql-scripts SCRIPTS      Comma-separated list of SQL scripts to execute (optional)
    -n, --enable-nvme              Enable NVME configuration (optional, default: false)
    -h, --help                     Display this help message

ENVIRONMENT VARIABLES:
    POSTGRESQL_VERSION             PostgreSQL version (overridden by -v)
    CUSTOM_SQL_SCRIPTS             Custom SQL scripts to execute (overridden by -s)
    ENABLE_NVME                    Enable NVME configuration (overridden by -n)

EXAMPLES:
    # Configure PostgreSQL 14
    $0 --version 14

    # Configure with custom SQL scripts
    $0 --version 14 --sql-scripts "/path/to/script1.sql,/path/to/script2.sql"

    # Configure with NVME support
    $0 --version 14 --enable-nvme

    # Using environment variables
    export POSTGRESQL_VERSION=14
    export ENABLE_NVME=true
    $0

EOF
    exit 1
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                postgresql_version="$2"
                shift 2
                ;;
            -s|--sql-scripts)
                custom_sql_scripts="$2"
                shift 2
                ;;
            -n|--enable-nvme)
                enable_nvme="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "ERROR: Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Validate required parameters
validate_parameters() {
    # Check postgresql_version
    if [ -z "$postgresql_version" ]; then
        if [ -z "$POSTGRESQL_VERSION" ]; then
            if [ -n "$DEFAULT_POSTGRESQL_VERSION" ]; then
                postgresql_version="$DEFAULT_POSTGRESQL_VERSION"
            else
                echo "ERROR: PostgreSQL version is required"
                echo "Provide via -v option, POSTGRESQL_VERSION environment variable, or set DEFAULT_POSTGRESQL_VERSION"
                exit 1
            fi
        else
            postgresql_version="$POSTGRESQL_VERSION"
        fi
    fi

    # Check custom_sql_scripts
    if [ -z "$custom_sql_scripts" ]; then
        if [ -n "$CUSTOM_SQL_SCRIPTS" ]; then
            custom_sql_scripts="$CUSTOM_SQL_SCRIPTS"
        else
            custom_sql_scripts="$DEFAULT_CUSTOM_SQL_SCRIPTS"
        fi
    fi

    # Check enable_nvme
    if [ -z "$enable_nvme" ]; then
        if [ -n "$ENABLE_NVME" ]; then
            enable_nvme="$ENABLE_NVME"
        else
            enable_nvme="$DEFAULT_ENABLE_NVME"
        fi
    fi

    # Export variables
    export postgresql_version
    export custom_sql_scripts
    export enable_nvme

    echo "=== Configuration Parameters ==="
    echo "PostgreSQL Version: $postgresql_version"
    echo "Custom SQL Scripts: $custom_sql_scripts"
    echo "Enable NVME: $enable_nvme"
    echo "==============================="
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root (use sudo)"
        exit 1
    fi
}

# Load library files
load_libraries() {
    echo "=== Loading Libraries ==="

    local libraries=(
        "variables.sh"
        "apt_pgdg.sh"
        "postgresql_conf.sh"
        "pg_hba_conf.sh"
        "backup.sh"
        "sysctl_conf.sh"
        "gai_conf.sh"
        "netplan_conf.sh"
        "limits_conf.sh"
        "pam_conf.sh"
        "nvme_conf.sh"
        "custom_sql.sh"
    )

    for lib in "${libraries[@]}"; do
        local lib_path="${LIB_DIR}/${lib}"
        if [ -f "$lib_path" ]; then
            source "$lib_path"
            echo "  Loaded: $lib"
        else
            echo "  ERROR: Library not found: $lib_path"
            exit 1
        fi
    done

    echo "Libraries loaded successfully"
}

# Main execution function
main() {
    echo "========================================"
    echo "PostgreSQL Configuration Script"
    echo "========================================"
    echo ""

    # Check root privileges
    check_root

    # Parse command line arguments
    parse_arguments "$@"

    # Validate parameters
    validate_parameters

    # Load library files
    load_libraries

    # Initialize variables
    echo ""
    if ! init_variables; then
        echo "ERROR: Failed to initialize variables"
        exit 1
    fi

    # Configure PGDG repository
    echo ""
    if ! configure_pgdg_repository; then
        echo "ERROR: Failed to configure PGDG repository"
        exit 1
    fi

    # Install PostgreSQL if not already installed
    echo ""
    echo "=== Installing PostgreSQL ${postgresql_version} ==="
    if ! dpkg -l | grep -q "postgresql-${postgresql_version}"; then
        apt-get install -y "postgresql-${postgresql_version}"
    else
        echo "PostgreSQL ${postgresql_version} already installed"
    fi

    # Configure system settings
    echo ""
    configure_sysctl

    echo ""
    configure_limits

    echo ""
    configure_pam

    echo ""
    configure_gai_conf

    echo ""
    configure_netplan

    # Configure PostgreSQL
    echo ""
    configure_postgresql_conf

    echo ""
    configure_pg_hba_conf

    echo ""
    create_backup_script

    # Optional: NVME configuration
    if [ "$enable_nvme" = "true" ]; then
        echo ""
        configure_nvme
    fi

    # Start PostgreSQL
    echo ""
    echo "=== Starting PostgreSQL ==="
    systemctl enable postgresql
    systemctl start postgresql
    systemctl status postgresql --no-pager

    # Execute custom SQL scripts
    echo ""
    execute_custom_sql

    echo ""
    echo "========================================"
    echo "Configuration completed successfully!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. Review configuration files"
    echo "  2. Test PostgreSQL connection: sudo -u postgres psql"
    echo "  3. Reboot system to apply all kernel parameters"
    echo ""
}

# Run main function
main "$@"
