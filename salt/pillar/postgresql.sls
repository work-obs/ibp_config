# PostgreSQL Configuration Pillar Data
# Modify these values as needed for your environment

# REQUIRED: PostgreSQL version to install and configure
postgresql_version: "14"

# OPTIONAL: Enable NVME configuration (default: false)
# Only enabled if /mnt/nvme is a mounted filesystem
enable_nvme: false

# OPTIONAL: Custom SQL scripts to execute after configuration
# Provide as a list of absolute paths to SQL files
custom_sql_scripts: []
# Example:
# custom_sql_scripts:
#   - /path/to/init_database.sql
#   - /path/to/create_users.sql
