#!/usr/bin/env bash

limits_conf() {
  local usage="limits_conf <hostname>"
  local hostname="${1:?$usage}"

  ssh "$hostname" "sudo tee /etc/security/limits.d/ibp.conf > /dev/null" << 'LIMITS_CONF'
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
LIMITS_CONF

  file_add_line "$hostname" 'session required       pam_limits.so' /etc/pam.d/common-session
  file_add_line "$hostname" 'session required       pam_limits.so' /etc/pam.d/common-session-noninteractive
}
