#!/usr/bin/env bash
#
# Create new EBS volume from golden AMI snapshot matching instance volume properties.
#
# Author  : Frank Claassens
# Created : Thu 30 October 2025
#

# Color constants
readonly BLACK='\033[0;30m' RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m' WHITE='\033[0;37m'
readonly BOLD_BLACK='\033[1;30m' BOLD_RED='\033[1;31m' BOLD_GREEN='\033[1;32m' BOLD_YELLOW='\033[1;33m'
readonly BOLD_BLUE='\033[1;34m' BOLD_MAGENTA='\033[1;35m' BOLD_CYAN='\033[1;36m' BOLD_WHITE='\033[1;37m'
readonly DIM_BLACK='\033[2;30m' DIM_RED='\033[2;31m' DIM_GREEN='\033[2;32m' DIM_YELLOW='\033[2;33m'
readonly DIM_BLUE='\033[2;34m' DIM_MAGENTA='\033[2;35m' DIM_CYAN='\033[2;36m' DIM_WHITE='\033[2;37m'
readonly RESET='\033[0m'

function err() {
  printf '%b[%s]: %s%b\n' "${BOLD_RED}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}" >&2
}

function info() {
  [[ -z "$1" ]] && { err "info: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_BLUE}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}"
}

function success() {
  [[ -z "$1" ]] && { err "success: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_GREEN}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}"
}

function error() {
  [[ -z "$1" ]] && { err "error: message cannot be empty"; return 1; }
  printf '%b[%s]: %s%b\n' "${BOLD_RED}" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" "${RESET}" >&2
}

function calculate_new_size() {
  local current_size=$1
  local increased_size=$(( current_size * 120 / 100 ))
  local remainder=$(( increased_size % 10 ))
  
  if (( remainder == 0 )); then
    echo "${increased_size}"
  elif (( remainder <= 5 )); then
    echo $(( increased_size - remainder + 5 ))
  else
    echo $(( increased_size - remainder + 10 ))
  fi
}

readonly SNAPSHOT_ID="snap-0aed3f217d1434783"

function main() {
  local instance_name="$1"
  
  if [[ -z "${instance_name}" ]]; then
    error "Usage: $0 INSTANCE_NAME"
    exit 1
  fi
  
  info "Fetching instance ID for: ${instance_name}"
  local instance_id
  instance_id=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${instance_name}" --query 'Reservations[0].Instances[0].InstanceId' --output text)
  
  if [[ -z "${instance_id}" || "${instance_id}" == "None" ]]; then
    error "Instance not found: ${instance_name}"
    exit 1
  fi
  
  info "Found instance: ${instance_id}"
  
  info "Fetching attached volumes..."
  local volumes
  volumes=$(aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=${instance_id}" --query 'Volumes[].VolumeId' --output text)
  
  local volume_count
  volume_count=$(echo "${volumes}" | wc -w)
  
  if (( volume_count >= 2 )); then
    error "Instance has ${volume_count} volumes attached. Only instances with 1 volume are supported."
    exit 1
  fi
  
  if (( volume_count == 0 )); then
    error "No volumes attached to instance"
    exit 1
  fi
  
  local volume_id="${volumes}"
  info "Processing volume: ${volume_id}"
  
  local volume_info
  volume_info=$(aws ec2 describe-volumes --volume-ids "${volume_id}" --query 'Volumes[0].[Size,AvailabilityZone,Tags]' --output json)
  
  local volume_size
  volume_size=$(echo "${volume_info}" | jq -r '.[0]')
  local availability_zone
  availability_zone=$(echo "${volume_info}" | jq -r '.[1]')
  local tags
  tags=$(echo "${volume_info}" | jq -c '.[2]')
  
  local new_size
  new_size=$(calculate_new_size "${volume_size}")
  
  info "Current volume size: ${volume_size} GB"
  info "New volume size: ${new_size} GB"
  info "Availability zone: ${availability_zone}"
  
  local new_name="${instance_name}-u22-prepared"
  local tag_spec
  tag_spec=$(echo "${tags}" | jq --arg name "${new_name}" 'map(if .Key == "Name" then .Value = $name else . end) | map("{Key=\(.Key),Value=\(.Value)}") | join(",")')
  tag_spec=$(echo "${tag_spec}" | tr -d '"')
  
  info "Tags: ${tag_spec}"
  info "Creating new volume: ${new_name}"
  local new_volume_id
  new_volume_id=$(aws ec2 create-volume --snapshot-id "${SNAPSHOT_ID}" --volume-type gp3 --size "${new_size}" --iops 6000 --throughput 256 --availability-zone "${availability_zone}" --tag-specifications "ResourceType=volume,Tags=[${tag_spec}]" --query 'VolumeId' --output text)
  
  if [[ -z "${new_volume_id}" ]]; then
    error "Failed to create volume"
    exit 1
  fi
  
  success "Created new volume: ${new_volume_id} (${new_name})"
}

main "$@"
