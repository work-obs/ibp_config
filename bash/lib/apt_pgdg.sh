#!/bin/bash

# APT PGDG Repository Configuration

configure_pgdg_repository() {
    echo "=== Configuring PGDG Repository ==="

    # Install postgresql-common if not already installed
    if ! dpkg -l | grep -q "^ii  postgresql-common"; then
        echo "Installing postgresql-common..."
        apt-get update
        apt-get install -y postgresql-common
    fi

    # Add PGDG repository
    echo "Adding PGDG repository..."
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y

    # Create APT preferences file
    echo "Creating /etc/apt/preferences.d/pgdg..."
    cat > /etc/apt/preferences.d/pgdg <<'EOF'
Package: *
Pin: release o=pgdg
Pin-Priority: 1001

EOF

    # Check for and remove other pgdg references in preferences.d
    echo "Checking for other PGDG references..."
    for file in /etc/apt/preferences.d/*; do
        if [ "$file" != "/etc/apt/preferences.d/pgdg" ] && [ -f "$file" ]; then
            if grep -q "pgdg" "$file"; then
                echo "WARNING: Found PGDG reference in $file"
                echo "Please manually review and remove if necessary"
            fi
        fi
    done

    # Update package lists
    apt-get update

    echo "PGDG repository configured successfully"
    return 0
}
