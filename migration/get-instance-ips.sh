#!/bin/bash

# Script to query AWS for EC2 private IPs based on instance names from instance-names.sh
# Writes results to instance-ips.sh as a simple list of IPs for sourcing

# Source the instance names
source ./instance-names.sh

# Output file
OUTPUT_FILE="instance-ips.sh"

# Create header for output file
cat > "$OUTPUT_FILE" << 'EOF'
#!/bin/bash
# EC2 instance private IPs
# Generated from AWS CLI queries based on instance names

INSTANCE_IPS=(
EOF

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed or not in PATH" >&2
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured or invalid" >&2
    exit 1
fi

function get_instance_ip() {
  local usage="get_instance_ip <instance>"
  local instance=${1:?$usage}
  echo "Querying AWS for instance: $instance_name..." >&2

  # Get private IP using AWS CLI
  private_ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$instance_name" \
                "Name=instance-state-name,Values=running" \
      --query "Reservations[0].Instances[0].PrivateIpAddress" \
      --output text 2>/dev/null)

  if [ "$private_ip" = "None" ] || [ -z "$private_ip" ]; then
      echo "Warning: No running instance found with name '$instance_name'" >&2
      private_ip="NOT_FOUND"
  fi

  # return ip
  echo "$instance|$private_ip"

}

# Process each instance and collect IPs
ips=()
for instance_name in "${INSTANCES[@]}"; do
    get_instance_ip $instance_name
    # Add to array
    ips+=("$private_ip")
done

# Write simple array format to output file
for ip in "${ips[@]}"; do
    echo "    \"$ip\"" >> "$OUTPUT_FILE"
done
echo ")" >> "$OUTPUT_FILE"

# Make the output file executable
chmod +x "$OUTPUT_FILE"

echo "Results written to $OUTPUT_FILE" >&2

# Display summary
echo "Summary:" >&2
echo "--------" >&2
for i in "${!INSTANCES[@]}"; do
    printf "%-20s -> %s\n" "${INSTANCES[$i]}" "${ips[$i]}" >&2
done