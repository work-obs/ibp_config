#!/usr/bin/env bash

stop_postgresql() {
  local usage="stop_postgresql <hostname>"
  local hostname="${1:?$usage}"
  ssh "$hostname" "sudo systemctl stop postgresql"
}
