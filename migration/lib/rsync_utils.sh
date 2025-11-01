#!/usr/bin/env bash
#
# Rsync Utility Functions
# - Simplifies rsync operations with explicit host execution control
#
# Author  : Frank Claassens
# Created : 31 October 2025
#

readonly RSYNC_OPTS="-a -q -A -X -H --perms --links --times --recursive --no-compress --inplace --whole-file --protect-args"

#######################################
# Execute rsync on local host
# Arguments:
#   Source path
#   Destination path
# Returns:
#   0 on success, 1 on failure
#######################################
function rsync_local() {
  [[ $# -lt 2 ]] && { err "rsync_local: requires source and destination"; return 1; }
  local src="$1"
  local dest="$2"
  
  rsync ${RSYNC_OPTS} "${src}" "${dest}"
}

#######################################
# Execute rsync on remote host via SSH
# Arguments:
#   SSH user
#   SSH host
#   Source path (on remote)
#   Destination path (on remote)
#   Optional: sudo user (default: root)
# Returns:
#   0 on success, 1 on failure
#######################################
function rsync_remote() {
  [[ $# -lt 4 ]] && { err "rsync_remote: requires user, host, source, destination"; return 1; }
  local ssh_user="$1"
  local ssh_host="$2"
  local src="$3"
  local dest="$4"
  local sudo_user="${5:-root}"
  
  ssh -q "${ssh_user}@${ssh_host}" "sudo -u ${sudo_user} rsync ${RSYNC_OPTS} ${src} ${dest}"
}

#######################################
# Execute multiple rsync operations on remote host
# Arguments:
#   SSH user
#   SSH host
#   Sudo user (default: root)
#   Array of "source:destination" pairs (remaining args)
# Returns:
#   0 on success, 1 on failure
#######################################
function rsync_remote_batch() {
  [[ $# -lt 4 ]] && { err "rsync_remote_batch: requires user, host, sudo_user, and at least one src:dest pair"; return 1; }
  local ssh_user="$1"
  local ssh_host="$2"
  local sudo_user="$3"
  shift 3
  
  local cmd="sudo -u ${sudo_user} bash <<'RSYNC_EOF'\n"
  
  for pair in "$@"; do
    local src="${pair%%:*}"
    local dest="${pair#*:}"
    cmd+="rsync ${RSYNC_OPTS} ${src} ${dest} || exit 1\n"
  done
  
  cmd+="RSYNC_EOF"
  
  ssh -q "${ssh_user}@${ssh_host}" "${cmd}"
}
