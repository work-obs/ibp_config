#!/usr/bin/env bash

stop_jetty() {
  local usage="stop_jetty <hostname>"
  local hostname="${1:?$usage}"
  ssh "$hostname" "sudo systemctl stop jetty"
}
