#!/usr/bin/env bash

set_pg_comms_settings() {
  local usage="set_pg_comms_settings <hostname> <postgresql.conf>"
  local hostname="${1:?$usage}"
  local config_file="${2:?$usage}"
  set_pg_config "$hostname" "listen_addresses" "*" "$config_file"
  set_pg_config "$hostname" "port" "27095" "$config_file"
  set_pg_config "$hostname" "ssl" "on" "$config_file"
  set_pg_config "$hostname" "ssl_cert_file" "/etc/ssl/certs/ssl-cert-snakeoil.pem" "$config_file"
  set_pg_config "$hostname" "ssl_key_file" "/etc/ssl/private/ssl-cert-snakeoil.key" "$config_file"
}
