#!/bin/bash

# Netplan configuration

configure_netplan() {
    echo "=== Configuring Netplan ==="

    # Find all netplan configuration files
    local netplan_files=$(find /etc/netplan -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)

    if [ -z "$netplan_files" ]; then
        echo "No netplan configuration files found"
        return 0
    fi

    # Process each netplan file
    for netplan_file in $netplan_files; do
        echo "Processing: $netplan_file"

        # Backup original file
        cp "$netplan_file" "${netplan_file}.backup.$(date +%Y%m%d_%H%M%S)"

        # Check if link-local is already configured
        if grep -q "link-local:" "$netplan_file"; then
            echo "  link-local already configured in $netplan_file"
            continue
        fi

        # Use Python to properly edit YAML file
        python3 <<EOF
import yaml
import sys

try:
    with open('$netplan_file', 'r') as f:
        config = yaml.safe_load(f)

    # Navigate to ethernets section
    if 'network' in config and 'ethernets' in config['network']:
        for interface, settings in config['network']['ethernets'].items():
            # Add link-local: [] to each interface
            if settings is None:
                settings = {}
            settings['link-local'] = []
            config['network']['ethernets'][interface] = settings

    # Write back to file
    with open('$netplan_file', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

    print("  Updated $netplan_file")
except Exception as e:
    print(f"  Error processing $netplan_file: {e}", file=sys.stderr)
    sys.exit(1)
EOF

        if [ $? -ne 0 ]; then
            echo "  WARNING: Failed to update $netplan_file with Python, trying sed approach"

            # Fallback: use sed to add link-local after each interface definition
            # This is a simplified approach and may not work for all YAML structures
            sed -i '/^[[:space:]]*[a-z0-9]*:$/a\            link-local: []' "$netplan_file"
        fi
    done

    # Test netplan configuration
    echo "Testing netplan configuration..."
    if netplan generate; then
        echo "Netplan configuration is valid"
    else
        echo "WARNING: Netplan configuration test failed"
        echo "Please manually review /etc/netplan/*.yaml files"
    fi

    echo "Netplan configuration completed"
    echo "NOTE: Run 'netplan apply' to apply changes"
    return 0
}
