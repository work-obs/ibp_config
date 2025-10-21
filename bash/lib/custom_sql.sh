#!/bin/bash

# Custom PostgreSQL SQL scripts execution

execute_custom_sql() {
    echo "=== Executing custom SQL scripts ==="

    # Check if custom_sql_scripts parameter is set and not just whitespace
    if [ -z "$custom_sql_scripts" ] || [ "$custom_sql_scripts" = " " ]; then
        echo "No custom SQL scripts specified, skipping"
        return 0
    fi

    # Split scripts by comma or space and execute each
    IFS=',' read -ra SCRIPTS <<< "$custom_sql_scripts"

    for script in "${SCRIPTS[@]}"; do
        # Trim whitespace
        script=$(echo "$script" | xargs)

        if [ -z "$script" ]; then
            continue
        fi

        if [ ! -f "$script" ]; then
            echo "WARNING: SQL script not found: $script"
            continue
        fi

        echo "Executing SQL script: $script"
        if sudo -u postgres psql -f "$script"; then
            echo "  SUCCESS: $script executed successfully"
        else
            echo "  ERROR: Failed to execute $script"
            return 1
        fi
    done

    echo "Custom SQL scripts execution completed"
    return 0
}
