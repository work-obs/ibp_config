#!/bin/bash

# Script to create AWS volumes from AMI golden image
# Usage: ./create-volumes-from-ami.sh <AMI_ID>

set -e

# Check if AMI ID is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <AMI_ID>"
    echo "Example: $0 ami-0123456789abcdef0"
    exit 1
fi

AMI_ID=$1
INSTANCE_FILE="instance-names.sh"

# Check if instance names file exists
if [ ! -f "$INSTANCE_FILE" ]; then
    echo "Error: $INSTANCE_FILE not found!"
    exit 1
fi

# Source the instance names file
source "$INSTANCE_FILE"

echo "Creating volumes from AMI: $AMI_ID"
echo "Processing ${#INSTANCES[@]} instances..."
echo ""

# Function to get tags from an existing instance
get_instance_tags() {
    local instance_name=$1
    local zone=$2
    local region=${zone%?}  # Remove last character to get region from zone
    
    # Query for instance ID by Name tag
    local instance_id=$(aws ec2 describe-instances \
        --region "$region" \
        --filters "Name=tag:Name,Values=$instance_name" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text)
    
    if [ "$instance_id" == "None" ] || [ -z "$instance_id" ]; then
        echo "Warning: Instance $instance_name not found in region $region"
        return 1
    fi
    
    # Get all tags from the instance
    aws ec2 describe-tags \
        --region "$region" \
        --filters "Name=resource-id,Values=$instance_id" \
        --query "Tags[?Key!='Name'].{Key:Key,Value:Value}" \
        --output json
}

# Function to get snapshot ID from AMI
get_ami_snapshot() {
    local ami_id=$1
    local region=$2
    
    aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId" \
        --output text
}

# Function to get volume size from AMI
get_ami_volume_size() {
    local ami_id=$1
    local region=$2
    
    aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query "Images[0].BlockDeviceMappings[0].Ebs.VolumeSize" \
        --output text
}

# Process each instance
for instance_data in "${INSTANCES[@]}"; do
    # Parse instance name and zone
    IFS=':' read -r instance_name zone <<< "$instance_data"
    region=${zone%?}
    
    echo "----------------------------------------"
    echo "Processing: $instance_name in zone $zone"
    
    # Create volume name
    volume_name="${instance_name}-u22-prepared"
    
    # Get snapshot ID from AMI
    snapshot_id=$(get_ami_snapshot "$AMI_ID" "$region")
    if [ "$snapshot_id" == "None" ] || [ -z "$snapshot_id" ]; then
        echo "Error: Could not get snapshot from AMI $AMI_ID in region $region"
        continue
    fi
    
    # Get volume size from AMI
    volume_size=$(get_ami_volume_size "$AMI_ID" "$region")
    if [ "$volume_size" == "None" ] || [ -z "$volume_size" ]; then
        echo "Error: Could not get volume size from AMI $AMI_ID in region $region"
        continue
    fi
    
    echo "  Snapshot ID: $snapshot_id"
    echo "  Volume Size: ${volume_size}GB"
    
    # Get tags from existing instance
    echo "  Fetching tags from instance..."
    instance_tags=$(get_instance_tags "$instance_name" "$zone")
    
    if [ $? -ne 0 ]; then
        echo "  Skipping due to error fetching tags"
        continue
    fi
    
    # Create volume from snapshot
    echo "  Creating volume: $volume_name"
    volume_id=$(aws ec2 create-volume \
        --region "$region" \
        --availability-zone "$zone" \
        --snapshot-id "$snapshot_id" \
        --volume-type gp3 \
        --size "$volume_size" \
        --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=$volume_name}]" \
        --query "VolumeId" \
        --output text)
    
    if [ -z "$volume_id" ]; then
        echo "  Error: Failed to create volume"
        continue
    fi
    
    echo "  Volume created: $volume_id"
    
    # Apply additional tags from the instance
    if [ "$instance_tags" != "[]" ] && [ -n "$instance_tags" ]; then
        echo "  Applying instance tags to volume..."
        
        # Convert JSON tags to AWS CLI format
        tag_specs=$(echo "$instance_tags" | jq -r '.[] | "Key=\(.Key),Value=\(.Value)"' | tr '\n' ' ')
        
        if [ -n "$tag_specs" ]; then
            aws ec2 create-tags \
                --region "$region" \
                --resources "$volume_id" \
                --tags $tag_specs
            echo "  Tags applied successfully"
        fi
    fi
    
    echo "  ✓ Completed: $volume_name ($volume_id)"
    echo ""
done

echo "========================================="
echo "Volume creation process completed!"
