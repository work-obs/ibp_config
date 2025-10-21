#!/bin/bash

# Security limits configuration

configure_limits() {
    echo "=== Configuring security limits ==="

    local limits_file="/etc/security/limits.d/ibp.conf"

    # Create limits configuration file
    cat > "$limits_file" <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

    echo "Security limits configured at: $limits_file"
    return 0
}
