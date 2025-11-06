#!/usr/bin/env bash

install_sysctld_config() {
  local usage="install_sysctld_config <hostname> <config_file>"
  local hostname="${1:?$usage}"
  local sysctld_config="${2:?$usage}"

  # shellcheck disable=SC2155
  local memory=$(get_pg_memory_gb "$hostname")

  local hugepages=$(( (memory * 1000) / 2 ))

  # shellcheck disable=SC2155
  local memory_kb=$(ssh "$hostname" "grep '^MemTotal:' /proc/meminfo | awk '{print \$2}'")

  # shellcheck disable=SC2087
  # shellcheck disable=SC2029
  ssh "$hostname" "sudo tee \"$sysctld_config\" > /dev/null" << SYSCTLD
# $hugepages * 2MB ... available for huge pages
vm.nr_hugepages = $hugepages

# port range both values cannot be even or odd - otherwise we get error
# ip_local_port_range: prefer different parity for start/end values.
net.ipv4.ip_local_port_range=1024 64999
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=90
net.ipv4.tcp_tw_reuse=1
net.core.netdev_max_backlog=182757
net.ipv4.neigh.default.gc_thresh3=8192

fs.aio-max-nr=524288
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=724288
kernel.keys.maxbytes=2000000
kernel.keys.maxkeys=2000

vm.max_map_count=262144

fs.file-max=2097152
# SHMMAX and SHMALL should be equal to physical memory of system, value is in kbytes
# SHMMAX is maximum size of a single segment, SHMALL is the size of all shared memory combined for the entire system
kernel.shmmax=$memory_kb
kernel.shmall=$memory_kb
# Try to avoid OOM-Killer
vm.overcommit_memory=2

SYSCTLD


}
