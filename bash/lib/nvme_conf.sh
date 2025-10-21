#!/bin/bash

# Optional NVME configuration for PostgreSQL

check_nvme_prerequisites() {
    echo "=== Checking NVME Prerequisites ==="

    # Check if /mnt/nvme exists
    if [ ! -d "/mnt/nvme" ]; then
        echo "SKIP: /mnt/nvme does not exist"
        return 1
    fi

    # Check if it's a mount point
    if ! mountpoint -q "/mnt/nvme"; then
        echo "SKIP: /mnt/nvme is not a mount point"
        return 1
    fi

    # Check if it's currently mounted
    if ! mount | grep -q "/mnt/nvme"; then
        echo "SKIP: /mnt/nvme is not currently mounted"
        return 1
    fi

    echo "NVME prerequisites met"
    return 0
}

configure_nvme() {
    echo "=== Configuring NVME for PostgreSQL ==="

    # Check prerequisites
    if ! check_nvme_prerequisites; then
        return 0  # Not an error, just skipped
    fi

    # Create permissions script
    echo "Creating /var/lib/postgresql/permissions.sh"
    cat > /var/lib/postgresql/permissions.sh <<'EOF'
#!/bin/bash
export DIRS="pg_wal pg_backup pg_temp"
for i in $DIRS
do
  mkdir -p /mnt/nvme/$i
  chmod 0700 /mnt/nvme/$i
  chown postgres:postgres /mnt/nvme/$i
done

EOF

    chmod 0755 /var/lib/postgresql/permissions.sh
    chown postgres:postgres /var/lib/postgresql/permissions.sh

    # Change ownership of /mnt/nvme
    echo "Setting ownership of /mnt/nvme to postgres:postgres"
    chown postgres:postgres /mnt/nvme

    # Create systemd drop-in directory
    echo "Creating systemd drop-in configuration"
    local systemd_dir="/etc/systemd/system/postgresql.service.d"
    mkdir -p "$systemd_dir"

    # Create nvme.conf
    cat > "$systemd_dir/nvme.conf" <<'EOF'
[Service]
ExecStartPre=/var/lib/postgresql/permissions.sh
ExecStartPost=/var/lib/postgresql/temp_tablespace.sh
EOF

    # Create temp_tablespace.sh script
    echo "Creating /var/lib/postgresql/temp_tablespace.sh"
    cat > /var/lib/postgresql/temp_tablespace.sh <<'EOF'
#!/bin/bash

psql -U postgres -d postgres <<PSQL_EOF
DROP TABLESPACE IF EXISTS nvme_temp;
CREATE TABLESPACE nvme_temp LOCATION '/mnt/nvme/pg_temp';
GRANT ALL PRIVILEGES ON TABLESPACE nvme_temp TO PUBLIC;
ALTER SYSTEM SET temp_tablespaces = 'nvme_temp';
SELECT pg_reload_conf();
PSQL_EOF

EOF

    chmod 0755 /var/lib/postgresql/temp_tablespace.sh
    chown postgres:postgres /var/lib/postgresql/temp_tablespace.sh

    # Reload systemd
    echo "Reloading systemd daemon"
    systemctl daemon-reload

    # Run permissions script now
    echo "Running permissions script"
    /var/lib/postgresql/permissions.sh

    echo "NVME configuration completed"
    return 0
}
