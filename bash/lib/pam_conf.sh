#!/bin/bash

# PAM configuration for limits

configure_pam() {
    echo "=== Configuring PAM ==="

    local pam_files=(
        "/etc/pam.d/common-session"
        "/etc/pam.d/common-session-noninteractive"
    )

    local pam_line="session required       pam_limits.so"

    for pam_file in "${pam_files[@]}"; do
        if [ ! -f "$pam_file" ]; then
            echo "WARNING: PAM file not found: $pam_file"
            continue
        fi

        # Check if already configured
        if grep -q "pam_limits.so" "$pam_file"; then
            echo "PAM limits already configured in $pam_file"
            continue
        fi

        # Backup original file
        cp "$pam_file" "${pam_file}.backup.$(date +%Y%m%d_%H%M%S)"

        # Add pam_limits.so at the end
        echo "" >> "$pam_file"
        echo "$pam_line" >> "$pam_file"
        echo "" >> "$pam_file"

        echo "PAM limits configured in $pam_file"
    done

    echo "PAM configuration completed"
    return 0
}
