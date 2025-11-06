#!/usr/bin/env bash

etc_gai_conf() {
  local usage="etc_gai_conf <hostname>"
  local hostname="${1:?$usage}"
  file_add_line "$hostname" 'precedence ::ffff:0:0/96  100' /etc/gai.conf
}
