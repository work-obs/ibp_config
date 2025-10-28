#!/usr/bin/env bash
#
# Gather EC2 instances with arm64 architecture for migration analysis.
#
# Author  : Frank Claassens
# Created : 27 October 2025
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

readonly OUTPUT_FILE="instance-names.sh"

function main() {
  info "Gathering EC2 instances with arm64 architecture..."
  
  # Create bash script header
  cat > "${OUTPUT_FILE}" << 'EOF'
#!/bin/bash

# instance-names.sh
# Format: Each entry contains instance-name|availability-zone
# The script will use these to create volumes in the specified zones

INSTANCES=(
EOF

  # Get instances and format as bash array
  aws ec2 describe-instances \
    --filters "Name=architecture,Values=arm64" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],Placement.AvailabilityZone]' \
    --output text | \
    awk '{print "    \"" $1"|"$2"\""}' >> "${OUTPUT_FILE}"
  
  # Close the array
  echo ")" >> "${OUTPUT_FILE}"
  
  if [[ $? -eq 0 ]]; then
    chmod +x "${OUTPUT_FILE}"
    local count
    count=$(grep -c '".*|.*"' "${OUTPUT_FILE}")
    success "Found ${count} arm64 instances. Bash script saved to ${OUTPUT_FILE}"
  else
    error "Failed to gather EC2 instances"
    exit 1
  fi
}

main "$@"
