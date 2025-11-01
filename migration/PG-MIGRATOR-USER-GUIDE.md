# IBP PostgreSQL Migration Tool User Guide

## Introduction

The IBP PostgreSQL Migration Tool is a powerful Bash script designed to automate the migration of an IBP (Integrated Business Planning) EC2 instance to a new environment. It handles the entire end-to-end process, from backing up databases and server configuration files on a source server to restoring them on a new destination server. The script is executed from a jumpbox that has SSH access to both the source and destination machines.

This migration process is ideal for upgrading the underlying infrastructure, such as moving to a newer operating system (e.g., Ubuntu 22.04) and a more recent version of PostgreSQL (e.g., PostgreSQL 14), without requiring manual intervention for each step.

## How it Works

The migration tool performs a series of automated steps to ensure a safe and reliable migration. The high-level workflow is as follows:

1.  **Pre-flight Checks**: Before starting the migration, the script validates the environment. It checks for SSH connectivity to both the source and destination servers and verifies that there is sufficient disk space for the backups.

2.  **Backup**: The script connects to the source server and performs a full backup of all PostgreSQL databases. It also archives critical server configuration files, such as those for Jetty, SSH host keys, and other IBP-specific settings.

3.  **Data Transfer**: The backups are compressed into a single archive file, which is then securely transferred from the source server to the destination server via the jumpbox.

4.  **Restore**: On the destination server, the script restores the PostgreSQL databases and moves the server configuration files to their correct locations.

5.  **Post-Restore Tasks**: After the restoration is complete, the script performs several maintenance tasks, such as running `ANALYZE`, `VACUUM`, and `REINDEX` on the databases to ensure optimal performance.

## Prerequisites

Before running the migration tool, please ensure that the following requirements are met:

*   You have a **jumpbox** with SSH access to both the source and destination servers. The script is intended to be run from this jumpbox.
*   The SSH user on the source and destination servers must have **passwordless `sudo` privileges**. This is necessary for the script to perform tasks that require elevated permissions, such as creating directories and managing services.
*   The source and destination servers must have **PostgreSQL installed and running**. The script does not handle the installation of PostgreSQL.
*   The `rsync` and `zstd` packages must be installed on both the source and destination servers. The script will attempt to install `zstd` if it is not present, but it is recommended to have it pre-installed.

## Usage

The script can be run in two ways: by providing the connection details via environment variables or by entering them interactively when prompted.

### Using Environment Variables

You can set the following environment variables before running the script:

*   `SOURCE_HOST`: The hostname or IP address of the source server.
*   `SOURCE_SSH_USER`: The SSH username for the source server (defaults to `smoothie`).
*   `SOURCE_PORT`: The PostgreSQL port on the source server (defaults to `27095`).
*   `DEST_HOST`: The hostname or IP address of the destination server.
*   `DEST_SSH_USER`: The SSH username for the destination server (defaults to `smoothie`).
*   `DEST_PORT`: The PostgreSQL port on the destination server (defaults to `27095`).

Once the environment variables are set, you can run the script as follows:

```bash
./pg-migrator.sh
```

### Interactive Mode

If you do not provide the connection details via environment variables, the script will prompt you to enter them interactively. Simply run the script without any environment variables set:

```bash
./pg-migrator.sh
```

The script will then ask for the source host, destination host, and other required information.

## The Migration Process in Detail

The script executes a sequence of functions to complete the migration. Here is a breakdown of the main stages:

### 1. Initial Setup

The script begins by performing initial checks to ensure the environment is ready for migration. This includes:

*   **Validating SSH Connections**: It tests the SSH connections to the source and destination servers to ensure they are accessible.
*   **Checking Disk Space**: It verifies that there is at least 10GB of free disk space on both servers to accommodate the database dumps and other temporary files.
*   **Creating Backup Directory**: It creates a backup directory on the source server, typically at `/tmp/pg_migration/dumps`.

### 2. Database Backup

Once the initial checks are complete, the script proceeds with backing up the databases on the source server. This involves:

*   **Applying Maintenance Settings**: The script dynamically tunes the PostgreSQL configuration on the source server to optimize it for dump operations. This helps to speed up the backup process.
*   **Exporting Global Objects**: It exports global objects from PostgreSQL, such as roles and tablespaces.
*   **Dumping Databases**: It dumps all user databases in parallel to maximize efficiency. The number of parallel jobs is calculated based on the available CPU cores.

### 3. Archiving and Transfer

After the databases are backed up, the script creates a compressed archive of the database dumps and essential server files. This archive is then transferred to the destination server.

*   **Creating Archive**: A `.tar.zst` archive is created, containing the database dumps and server configuration files.
*   **Transferring the Archive**: The archive is transferred from the source to the destination server through the jumpbox using `rsync`.

### 4. Database Restore

On the destination server, the script restores the databases and server files.

*   **Applying Maintenance Settings**: Similar to the source server, the script tunes the PostgreSQL configuration on the destination server for optimal restore performance.
*   **Restoring Global Objects**: It restores the global objects first.
*   **Restoring Databases**: The script restores all databases in parallel. Before restoring, it drops any existing databases with the same name to ensure a clean restore.
*   **Restoring Server Files**: It moves the server configuration files from the archive to their final locations on the destination server.

### 5. Post-Migration Validation

After the restore process is complete, the script performs several validation and maintenance tasks to ensure the new database is in a healthy state.

*   **Running `ANALYZE`**: It runs the `ANALYZE` command to update statistics for the query planner.
*   **Running `VACUUM`**: It performs a `VACUUM` to reclaim storage and improve performance.
*   **Running `REINDEX`**: It rebuilds indexes to ensure they are optimal.
*   **Validating Row Counts**: It checks the row counts of the tables to verify data integrity.

By following these steps, the IBP PostgreSQL Migration Tool provides a reliable and automated way to migrate your IBP instances with minimal downtime.

// ... existing code ...
The script will then ask for the source host, destination host, and other required information.

Once the script is running, you will see a header displaying the source and destination connection details.

![Connection Details](images/pg-migrator/Source_Dest_Variable_Top_header.png)

You will then be presented with a menu of options to choose from.

![Main Menu](images/pg-migrator/All_Menu_Options.png)

## The Migration Process in Detail

The script executes a sequence of functions to complete the migration. Here is a breakdown of the main stages:

### 1. Initial Setup

The script begins by performing initial checks to ensure the environment is ready for migration. This includes:

*   **Validating SSH Connections**: It tests the SSH connections to the source and destination servers to ensure they are accessible.
*   **Checking Disk Space**: It verifies that there is at least 10GB of free disk space on both servers to accommodate the database dumps and other temporary files.
*   **Creating Backup Directory**: It creates a backup directory on the source server, typically at `/tmp/pg_migration/dumps`.

![Initial Setup](images/pg-migrator/Menu_Option_2.png)

### 2. Database Backup

Once the initial checks are complete, the script proceeds with backing up the databases on the source server. This involves:

*   **Applying Maintenance Settings**: The script dynamically tunes the PostgreSQL configuration on the source server to optimize it for dump operations. This helps to speed up the backup process.
*   **Exporting Global Objects**: It exports global objects from PostgreSQL, such as roles and tablespaces.
*   **Dumping Databases**: It dumps all user databases in parallel to maximize efficiency. The number of parallel jobs is calculated based on the available CPU cores.

Before starting the backup, you can view a summary of the databases on the source server.

![Source Database Summary](images/pg-migrator/Menu_Option_9.png)

### 3. Archiving and Transfer

After the databases are backed up, the script creates a compressed archive of the database dumps and essential server files. This archive is then transferred to the destination server.

*   **Creating Archive**: A `.tar.zst` archive is created, containing the database dumps and server configuration files.
*   **Transferring the Archive**: The archive is transferred from the source to the destination server through the jumpbox using `rsync`.

### 4. Database Restore

On the destination server, the script restores the databases and server files.

*   **Applying Maintenance Settings**: Similar to the source server, the script tunes the PostgreSQL configuration on the destination server for optimal restore performance.
*   **Restoring Global Objects**: It restores the global objects first.
*   **Restoring Databases**: The script restores all databases in parallel. Before restoring, it drops any existing databases with the same name to ensure a clean restore.
*   **Restoring Server Files**: It moves the server configuration files from the archive to their final locations on the destination server.

After the restore, you can view a summary of the databases on the destination server.

![Destination Database Summary](images/pg-migrator/Menu_Option_10.png)

### 5. Post-Migration Validation

After the restore process is complete, the script performs several validation and maintenance tasks to ensure the new database is in a healthy state.

*   **Running `ANALYZE`**: It runs the `ANALYZE` command to update statistics for the query planner.
*   **Running `VACUUM`**: It performs a `VACUUM` to reclaim storage and improve performance.
*   **Running `REINDEX`**: It rebuilds indexes to ensure they are optimal.
*   **Validating Row Counts**: It checks the row counts of the tables to verify data integrity.

### 6. `bi_cube` Detection

The script includes functionality to detect if the `bi_cube` is present on the source server. This is important for ensuring that all necessary files and configurations related to `bi_cube` are included in the migration.

![bi_cube Detection](images/pg-migrator/Menu_Option_18.png)

### 7. Final Cleanup

At the end of the migration, the script performs a cleanup process to remove temporary files from the source, destination, and jumpbox servers.

![Final Cleanup](images/pg-migrator/Menu_Option_19.png)

## Successful Migration

A successful migration will complete all the steps and display the total execution time.

![Successful Migration 1](images/pg-migrator/Successful_Full_Migration_Run_Time-1.png)
![Successful Migration 2](images/pg-migrator/Successful_Full_Migration_Run_Time-2.png)

By following these steps, the IBP PostgreSQL Migration Tool provides a reliable and automated way to migrate your IBP instances with minimal downtime.
