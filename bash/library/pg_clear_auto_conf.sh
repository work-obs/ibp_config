#!/usr/bin/env bash

pg_clear_auto_conf() {
    local usage="$0 <hostname> <postgres_config_file> <version>"
    local hostname="${1:?$usage}"
    local version="${2:?$usage}"
    # Clear out /var/lib/postgresql/${version}/main/postgresql.auto.conf
    ssh_cmd "$hostname" "sudo -u root bash -c \" >/var/lib/postgresql/${version}/main/postgresql.auto.conf\""
}
