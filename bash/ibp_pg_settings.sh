#!/usr/bin/env bash

# shellcheck disable=SC1090
. ./library/*.sh

main() {
  local usage="$0 <hostname> <postgres_config_file> <version>"
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  local version="${3:?$usage}"

  echo "################################################################################"
  echo "### !!! !!! !!! !!! THIS WILL SHUT DOWN IBP AND THE DATABASE !!! !!! !!! !!! ###"
  echo "#################################################################################"
  read -rp "ARE YOU SURE? Press Enter to continue..."
  read -rp "ARE YOU REALLY SURE? Press Enter to continue..."
  stop_jetty "$hostname"
  stop_postgresql "$hostname"

  pg_clear_auto_conf "$hostname" "$version"
  set_pg_data_warehouse "$hostname" "$config_file"
  create_pg_clean_archive_sh "$hostname" "/var/lib/postgresql/clean_archive.sh"
  install_user_cron "$hostname" "postgres" "0 2 * * *" "/var/lib/postgresql/clean_archive.sh" "Daily backup to clear WAL archive"

  # Setup /etc/security/limits.d/ibp.conf and /etc/pam.d/common-session*
  limits_conf "$hostname"

  ssh_cmd "$hostname" "sudo -u root mv /etc/sysctl.conf /etc/sysctl.d/00-sysctl.conf"
  echo "Moved sysctl.conf to /etc/sysctl.d/00-sysctl.conf and created dummy sysctl.conf because of systemd-sysctl"
  echo "# Avoid using this file, systemd-sysctl ignores this file, create a file under /etc/sysctl.d" | sudo tee /etc/sysctl.conf
  install_sysctld_config "$hostname" "/etc/sysctl.d/ibp.conf"

  # yq needed to patch netplan to remove link_local
  install_yq "$hostname"
  # disable ipv6 in netplan
  disable_link_local "$hostname"

  # make ipv4 priority for outgoing connections
  etc_gai_conf "$hostname"

  echo "reboot the server: $hostname"

}

main "$@"
