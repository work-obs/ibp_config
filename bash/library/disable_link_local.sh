#!/usr/bin/env bash

disable_link_local() {
    local usage="disable_link_local <hostname>"
    local hostname="${1:?$usage}"
    local netplan_config="/etc/netplan/*.yaml"

    # shellcheck disable=SC2029
    ssh "$hostname" "
        for config in $netplan_config; do
            [ -f \"\$config\" ] || continue

            echo \"Processing: \$config\"
            cp \"\$config\" \"\${config}.bak\"

            # Get all interface names and add link-local: []
            for iface in \$(yq eval '.network.ethernets | keys | .[]' \"\$config\"); do
                yq eval -i \".network.ethernets.\\\"\$iface\\\".link-local = []\" \"\$config\"
                echo \"Disabled link-local for: \$iface\"
            done
        done

        netplan apply && echo \"Config valid! Run: netplan apply\"
    "
}
