#!/bin/bash

# PostgreSQL pg_hba.conf configuration

configure_pg_hba_conf() {
    echo "=== Configuring pg_hba.conf ==="

    local pg_hba_file="/etc/postgresql/${postgresql_version}/main/pg_hba.conf"

    if [ ! -f "$pg_hba_file" ]; then
        echo "ERROR: pg_hba.conf not found: $pg_hba_file"
        return 1
    fi

    # Backup original config
    cp "$pg_hba_file" "${pg_hba_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Create new pg_hba.conf with trust for local connections
    cat > "$pg_hba_file" <<'EOF'
# PostgreSQL Client Authentication Configuration File
# ===================================================
#
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections via Unix domain sockets - trust
local   all             all                                     trust

# IPv4 local connections - trust
host    all             all             127.0.0.1/32            trust

# IPv6 local connections - trust
host    all             all             ::1/128                 trust

# Allow replication connections from localhost
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
EOF

    chown postgres:postgres "$pg_hba_file"
    chmod 0640 "$pg_hba_file"

    echo "pg_hba.conf configured successfully"
    return 0
}
