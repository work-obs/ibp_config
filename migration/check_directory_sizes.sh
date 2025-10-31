#!/bin/bash

# Configuration - directories to check (space-separated)
DIRECTORIES="/var/log /opt /home"

# AWS Configuration
AWS_REGION="us-east-1"

# SSH Configuration
SSH_USER="ec2-user"
SSH_KEY="~/.ssh/id_rsa"
SSH_TIMEOUT=30
CONNECT_HOST=""

# Get all running EC2 instances in the region
echo "Fetching running EC2 instances in region $AWS_REGION..."
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo "No running instances found in region $AWS_REGION"
    exit 1
fi

echo "Found instances: $INSTANCE_IDS"
echo "----------------------------------------"

# Loop through each instance
for INSTANCE_ID in $INSTANCE_IDS; do
    echo "Processing instance: $INSTANCE_ID"
    
    # Skip auto-detection if CONNECT_HOST is already set
    if [ -z "$CONNECT_HOST" ]; then
        # Get instance public IP or DNS name
        PUBLIC_IP=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[].Instances[].PublicIpAddress" \
            --output text)
        
        if [ -z "$PUBLIC_IP" ]; then
            # Try to get public DNS name if no public IP
            PUBLIC_DNS=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query "Reservations[].Instances[].PublicDnsName" \
                --output text)
            
            if [ -n "$PUBLIC_DNS" ]; then
                CONNECT_HOST="$PUBLIC_DNS"
            else
                echo "  No public IP or DNS found for $INSTANCE_ID, skipping..."
                continue
            fi
        else
            CONNECT_HOST="$PUBLIC_IP"
        fi
    fi
    
    echo "  Connecting to: $CONNECT_HOST"
    
    # SSH to instance and check directory sizes
    TOTAL_SIZE=0
    for DIR in $DIRECTORIES; do
        if ssh -o ConnectTimeout=$SSH_TIMEOUT -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$CONNECT_HOST" "test -d '$DIR'" 2>/dev/null; then
            SIZE=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$CONNECT_HOST" "du -sb '$DIR' 2>/dev/null | cut -f1" 2>/dev/null)
            if [ -n "$SIZE" ]; then
                SIZE_MB=$((SIZE / 1024 / 1024))
                echo "  $DIR: ${SIZE_MB}MB"
                TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            else
                echo "  $DIR: Unable to get size"
            fi
        else
            echo "  $DIR: Directory not found"
        fi
    done
    
    # Print total for this server
    TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))
    echo "  TOTAL: ${TOTAL_SIZE_MB}MB"
    echo "----------------------------------------"
done

echo "Directory size check completed!"