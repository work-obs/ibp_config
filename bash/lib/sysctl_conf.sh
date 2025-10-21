#!/bin/bash

# System sysctl configuration for PostgreSQL

configure_sysctl() {
    echo "=== Configuring sysctl settings ==="

    local sysctl_file="/etc/sysctl.d/99-ibp.conf"

    # Create sysctl configuration file
    cat > "$sysctl_file" <<EOF
# memory_bytes / 4000000 (count of 2MB segments of half the memory)
vm.nr_hugepages = ${nr_hugepages}

# port range both values cannot be even or odd - otherwise we get error
# ip_local_port_range: prefer different parity for start/end values.
net.ipv4.ip_local_port_range=1024 64999
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=90
net.ipv4.tcp_tw_reuse=1
net.core.netdev_max_backlog=182757
net.ipv4.neigh.default.gc_thresh3=8192

fs.aio-max-nr=524288
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=724288
kernel.keys.maxbytes=2000000
kernel.keys.maxkeys=2000

vm.max_map_count=262144

fs.file-max=2097152
# SHMMAX and SHMALL should be equal to physical memory of system, value is in bytes
# SHMMAX is maximum size of a single segment, SHMALL is the size of all shared memory combined for the entire system
kernel.shmmax=${memory_bytes}
kernel.shmall=${memory_bytes}
# Try to avoid OOM-Killer
vm.overcommit_memory=2

EOF

    echo "Sysctl configuration created at: $sysctl_file"

    # Apply sysctl settings
    echo "Applying sysctl settings..."
    sysctl -p "$sysctl_file"

    echo "Sysctl configuration completed"
    return 0
}
