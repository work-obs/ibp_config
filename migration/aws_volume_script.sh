#!/bin/bash

# Script: create-volumes-from-ami.sh
# Description: Creates AWS volumes from an AMI golden image for multiple instances
# Usage: ./create-volumes-from-ami.sh <AMI_ID> <instance-names-file>

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if required arguments are provided
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <AMI_ID> [instance-names-file]"
    log_error "Example: $0 ami-0abcdef1234567890 instance-names.sh"
    exit 1
fi

AMI_ID=$1
INSTANCE_FILE=${2:-"instance-names.sh"}

# Validate AMI ID format
if [[ ! $AMI_ID =~ ^ami-[a-f0-9]{8,17}$ ]]; then
    log_error "Invalid AMI ID format: $AMI_ID"
    exit 1
fi

# Check if instance names file exists
if [ ! -f "$INSTANCE_FILE" ]; then
    log_error "Instance names file not found: $INSTANCE_FILE"
    exit 1
fi

log_info "Starting volume creation process..."
log_info "AMI ID: $AMI_ID"
log_info "Instance file: $INSTANCE_FILE"

# Source the instance names file
source "$INSTANCE_FILE"

# Verify INSTANCES array is populated
if [ ${#INSTANCES[@]} -eq 0 ]; then
    log_error "No instances found in $INSTANCE_FILE"
    exit 1
fi

# Function to get AMI details
get_ami_details() {
    local ami_id=$1
    local region=$2
    
    aws ec2 describe-images \
        --image-ids "$ami_id" \
        --region "$region" \
        --query 'Images[0]' \
        --output json 2>/dev/null
}

# Function to get instance details and tags
get_instance_details() {
    local instance_name=$1
    local region=$2
    
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$instance_name" \
        --region "$region" \
        --query 'Reservations[0].Instances[0]' \
        --output json 2>/dev/null
}

# Function to create volume from AMI snapshot
create_volume_from_ami() {
    local ami_id=$1
    local instance_name=$2
    local zone=$3
    local region=$4
    local tags=$5
    
    log_info "Processing instance: $instance_name in zone: $zone"
    
    # Get AMI details
    ami_details=$(get_ami_details "$ami_id" "$region")
    
    if [ -z "$ami_details" ] || [ "$ami_details" == "null" ]; then
        log_error "AMI $ami_id not found in region $region"
        return 1
    fi
    
    # Get root device snapshot ID from AMI
    snapshot_id=$(echo "$ami_details" | jq -r '.BlockDeviceMappings[] | select(.DeviceName == .Ebs.SnapshotId) | .Ebs.SnapshotId // empty')
    
    # If above doesn't work, try getting the first EBS snapshot
    if [ -z "$snapshot_id" ]; then
        snapshot_id=$(echo "$ami_details" | jq -r '.BlockDeviceMappings[0].Ebs.SnapshotId // empty')
    fi
    
    if [ -z "$snapshot_id" ] || [ "$snapshot_id" == "null" ]; then
        log_error "No snapshot found in AMI $ami_id"
        return 1
    fi
    
    log_info "Found snapshot: $snapshot_id"
    
    # Get volume size and type from AMI
    volume_size=$(echo "$ami_details" | jq -r '.BlockDeviceMappings[0].Ebs.VolumeSize // 8')
    volume_type=$(echo "$ami_details" | jq -r '.BlockDeviceMappings[0].Ebs.VolumeType // "gp3"')
    
    log_info "Creating volume (Size: ${volume_size}GB, Type: $volume_type)..."
    
    # Create the volume
    volume_id=$(aws ec2 create-volume \
        --snapshot-id "$snapshot_id" \
        --availability-zone "$zone" \
        --volume-type "$volume_type" \
        --size "$volume_size" \
        --region "$region" \
        --query 'VolumeId' \
        --output text)
    
    if [ -z "$volume_id" ]; then
        log_error "Failed to create volume for $instance_name"
        return 1
    fi
    
    log_info "Volume created: $volume_id"
    
    # Wait for volume to be available
    log_info "Waiting for volume to become available..."
    aws ec2 wait volume-available \
        --volume-ids "$volume_id" \
        --region "$region"
    
    # Apply tags to the volume
    if [ -n "$tags" ]; then
        log_info "Applying tags to volume..."
        aws ec2 create-tags \
            --resources "$volume_id" \
            --tags "$tags" \
            --region "$region"
    fi
    
    log_info "Successfully created volume $volume_id for $instance_name"
    echo "$instance_name,$zone,$volume_id" >> volume-creation-report.csv
    
    return 0
}

# Main processing loop
log_info "Processing ${#INSTANCES[@]} instance(s)..."

# Create report file
echo "InstanceName,Zone,VolumeID" > volume-creation-report.csv

success_count=0
fail_count=0

for instance_entry in "${INSTANCES[@]}"; do
    # Parse instance name and zone
    IFS='|' read -r instance_name zone <<< "$instance_entry"
    
    # Extract region from zone (e.g., us-east-1a -> us-east-1)
    region="${zone%?}"
    
    log_info "----------------------------------------"
    
    # Get instance details to retrieve tags
    instance_details=$(get_instance_details "$instance_name" "$region")
    
    if [ -z "$instance_details" ] || [ "$instance_details" == "null" ]; then
        log_warn "Instance $instance_name not found in region $region. Creating volume without instance tags."
        tags="Key=Name,Value=${instance_name}-volume Key=CreatedFrom,Value=$AMI_ID"
    else
        # Extract tags from instance
        instance_tags=$(echo "$instance_details" | jq -r '.Tags // [] | map("Key=" + .Key + ",Value=" + .Value) | join(" ")')
        
        if [ -n "$instance_tags" ]; then
            tags="$instance_tags Key=CreatedFrom,Value=$AMI_ID"
        else
            tags="Key=Name,Value=${instance_name}-volume Key=CreatedFrom,Value=$AMI_ID"
        fi
    fi
    
    # Create volume
    if create_volume_from_ami "$AMI_ID" "$instance_name" "$zone" "$region" "$tags"; then
        ((success_count++))
    else
        ((fail_count++))
        log_error "Failed to create volume for $instance_name"
    fi
done

log_info "----------------------------------------"
log_info "Volume creation completed!"
log_info "Successful: $success_count"
log_info "Failed: $fail_count"
log_info "Report saved to: volume-creation-report.csv"

exit 0