#!/usr/bin/env bash

# Function to set PostgreSQL configuration parameters on remote host
# Usage: set_pg_config <hostname> <setting_name> <value> <config_file>
# Examples:
#   set_pg_config "db-server-01" "max_connections" "200" "/etc/postgresql/15/main/postgresql.conf"
#   set_pg_config "db-server-01" "listen_addresses" "localhost" "/etc/postgresql/15/main/postgresql.conf"
#   set_pg_config "db-server-01" "log_statement" "all" "/etc/postgresql/15/main/postgresql.conf"

set_pg_config() {
  local usage="set_pg_config <hostname> <setting_name> <value> <config_file>"
  local hostname="${1:?$usage}"
  local setting_name="${2:?$usage}"
  local value="${3:?$usage}"
  local config_file="${4:?$usage}"

  # Create backup only if it does not yet exist (only one per day by default)
  backup_file "$hostname" "$config_file"

  # Determine if value needs quotes
  local formatted_value
  if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$value" =~ ^(on|off|true|false|yes|no)$ ]]; then
    # Numeric values or boolean-like values don't need quotes
    formatted_value="$value"
  else
    # String values need single quotes
    formatted_value="'$value'"
  fi

  # Escape special characters in setting name for regex
  # shellcheck disable=SC2155
  # shellcheck disable=SC2016
  local escaped_setting=$(printf '%s\n' "$setting_name" | sed 's/[\[\].*^$()+?{|]/\\&/g')

  # Check if setting already exists (commented or uncommented)
  # shellcheck disable=SC2029
  if ssh "$hostname" "grep -q \"^#\\s*${escaped_setting}\\s*=\" \"$config_file\" || grep -q \"^${escaped_setting}\\s*=\" \"$config_file\""; then
    # Setting exists, update it
    echo "Updating existing setting: $setting_name = $formatted_value"

    # First, comment out any existing uncommented line
    ssh "$hostname" "sed -i \"s/^${escaped_setting}\\s*=.*/#&/\" \"$config_file\""

    # Then, update the commented line (or add new one if only uncommented existed)
    if ssh "$hostname" "grep -q \"^#\\s*${escaped_setting}\\s*=\" \"$config_file\""; then
      ssh "$hostname" "sed -i \"s/^#\\s*${escaped_setting}\\s*=.*/${setting_name} = ${formatted_value}/\" \"$config_file\""
    else
      # Add new line after the commented one we just created
      ssh "$hostname" "sed -i \"/^#${escaped_setting}\\s*=/a\\${setting_name} = ${formatted_value}\" \"$config_file\""
    fi
  else
    # Setting doesn't exist, add it to the end
    echo "Adding new setting: $setting_name = $formatted_value"
    ssh "$hostname" "{
      echo \"\"
      echo \"# Added by set_pg_config on $(date)\"
      echo \"$setting_name = $formatted_value\"
    } >> \"$config_file\""
  fi

  echo "Successfully set $setting_name = $formatted_value in $config_file on $hostname"

  # Verify the change
  echo "Verification:"
  ssh "$hostname" "grep \"^$setting_name\\s*=\" \"$config_file\"" || echo "Warning: Could not find active setting in file"
}
