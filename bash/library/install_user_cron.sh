#!/usr/bin/env bash

install_user_cron() {
  read -r -d '' usage <<EOF
Usage: install_user_cron <hostname> <user> <schedule> <command> [description]
Example: install_user_cron db-server-01 john '0 2 * * *' '/path/to/backup.sh' 'Daily backup'
EOF
  local hostname=${1:?$usage}
  local user=${2:?$usage}
  local cron_schedule=${3:?$usage}
  local command=${4:?$usage}
  local description="$5"
  local retval


  # Check if user exists on remote system
  # shellcheck disable=SC2029
  if ! ssh "$hostname" "id \"$user\" &>/dev/null"; then
    echo "Error: User '$user' does not exist on $hostname"
    return 1
  fi

  # Create the cron entry
  local cron_entry="$cron_schedule $command"

  # Add description as comment if provided
  if [[ -n "$description" ]]; then
    cron_entry="# $description"$'\n'"$cron_entry"
  fi

  # Get current crontab for the user (suppress error if no crontab exists)
  local current_crontab
  # shellcheck disable=SC2029
  current_crontab=$(ssh "$hostname" "sudo -u \"$user\" crontab -l 2>/dev/null || true")

  # Check if the exact cron job already exists
  if echo "$current_crontab" | grep -Fq "$cron_schedule $command"; then
    echo "Cron job already exists for user $user on $hostname"
    return 0
  fi

    # Add the new cron job
    # shellcheck disable=SC2029
  ssh "$hostname" "
    {
      echo \"$current_crontab\"
      echo \"$cron_entry\"
    } | sudo -u '$user' crontab -
  "
  retval=$?

  if [[ $retval -eq 0 ]]; then
    echo "Successfully installed cron job for user '$user' on $hostname:"
    echo "  Schedule: $cron_schedule"
    echo "  Command: $command"
    [[ -n "$description" ]] && echo "  Description: $description"
  else
    echo "Error: Failed to install cron job"
    return 1
  fi
}
