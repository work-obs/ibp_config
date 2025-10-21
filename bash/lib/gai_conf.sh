#!/bin/bash

# GAI (getaddrinfo) configuration

configure_gai_conf() {
    echo "=== Configuring /etc/gai.conf ==="

    local gai_file="/etc/gai.conf"

    # Check if the configuration already exists
    if grep -q "precedence ::ffff:0:0/96  100" "$gai_file" 2>/dev/null; then
        echo "GAI configuration already present"
        return 0
    fi

    # Backup original file if it exists
    if [ -f "$gai_file" ]; then
        cp "$gai_file" "${gai_file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Add the configuration to the end of the file
    echo "" >> "$gai_file"
    echo "precedence ::ffff:0:0/96  100" >> "$gai_file"
    echo "" >> "$gai_file"

    echo "GAI configuration completed"
    return 0
}
