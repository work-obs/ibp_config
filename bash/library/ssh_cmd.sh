#!/usr/bin/env bash

# ssh_command user@host cmd p1 p2 p3 p4
ssh_cmd() {
  local conn="$1"
  local cmd="${*:2}"
  # shellcheck disable=SC2029
  # shellcheck disable=SC2155
  local output=$(ssh -o StrictHostKeyChecking=no "$conn" "$cmd")
  echo "$output"
}
