#!/bin/bash

# Configuration - directories to check (space-separated)
DIRECTORIES="/opt /var/lib/postgresql"

# AWS Configuration
AWS_REGION="us-east-1"

SSH_TIMEOUT=30

# Get all running EC2 instances in the region
echo "Loading instance IPs"
. ./instance-ips.sh
if [ -z "$INSTANCE_IPS" ]; then
    echo "No running instances found"
    exit 1
fi

echo "Found instances: $INSTANCE_IPS"
echo "----------------------------------------"

# Function to check directory sizes on a remote ip via SSH
# Parameters: $1 - hostname and IP address "host|ip"
function check_directory_sizes() {
    local host_and_ip="$1"
    local total_size=0

    local oifs=$IFS
    IFS='|' read -ra parts <<< "$host_and_ip"
    IFS=$oifs
    hostname="$parts[0]"
    ip="$parts[1]"
    echo "  Connecting to: $ip"
    
    # SSH to instance and check directory sizes
    for DIR in $DIRECTORIES; do
        if ssh -o ConnectTimeout=$SSH_TIMEOUT "$ip" "test -d '$DIR'" 2>/dev/null; then
            SIZE=$(ssh -o ConnectTimeout=$SSH_TIMEOUT "$ip" "du -sb '$DIR' 2>/dev/null | cut -f1" 2>/dev/null)
            if [ -n "$SIZE" ]; then
                SIZE_MB=$((SIZE / 1024 / 1024))
                echo "  $DIR: ${SIZE_MB}MB"
                total_size=$((total_size + SIZE))
            else
                echo "  $DIR: Unable to get size"
            fi
        else
            echo "  $DIR: Directory not found"
        fi
    done
    
    # Print total for this server
    TOTAL_SIZE_MB=$((total_size / 1024 / 1024))
    echo "  TOTAL: ${TOTAL_SIZE_MB}MB"
    echo "----------------------------------------"
}

# Loop through each instance
for INSTANCE_IP in $INSTANCE_IPS; do
    echo "Processing instance: $INSTANCE_IP"
    check_directory_sizes "$PUBLIC_IP"

done

echo "Directory size check completed!"