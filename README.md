# PostgreSQL Configuration for Ubuntu 22.04

This repository provides three different methods to configure PostgreSQL database server on Ubuntu 22.04 with optimized settings for performance and reliability.

## Overview

The configuration includes:
- PostgreSQL repository setup (PGDG)
- PostgreSQL installation
- System tuning (sysctl, limits, PAM, GAI, netplan)
- PostgreSQL optimization (memory, workers, WAL, logging)
- Automated backup scripts
- Optional NVME storage configuration

## Available Configuration Methods

1. **Bash Scripts** - Traditional shell scripts with modular libraries
2. **Ansible** - Infrastructure as Code using Ansible playbooks and roles
3. **Salt** - Configuration management using SaltStack states

Choose the method that best fits your infrastructure and workflow.

---

## Method 1: Bash Scripts

### Prerequisites
- Ubuntu 22.04
- Root access (sudo)
- `bc` utility (for calculations)

### Directory Structure
```
bash/
├── lib/                      # Library files
│   ├── variables.sh          # Variable calculations
│   ├── apt_pgdg.sh          # PGDG repository setup
│   ├── postgresql_conf.sh   # PostgreSQL configuration
│   ├── pg_hba_conf.sh       # Authentication configuration
│   ├── backup.sh            # Backup script setup
│   ├── sysctl_conf.sh       # Kernel parameters
│   ├── gai_conf.sh          # GAI configuration
│   ├── netplan_conf.sh      # Network configuration
│   ├── limits_conf.sh       # Security limits
│   ├── pam_conf.sh          # PAM configuration
│   ├── nvme_conf.sh         # NVME setup (optional)
│   └── custom_sql.sh        # Custom SQL execution
└── configure_postgresql.sh  # Main driver script
```

### Usage

#### Basic Configuration
```bash
# Configure PostgreSQL 14
sudo bash/configure_postgresql.sh --version 14
```

#### With Custom SQL Scripts
```bash
sudo bash/configure_postgresql.sh \
  --version 14 \
  --sql-scripts "/path/to/init.sql,/path/to/users.sql"
```

#### With NVME Support
```bash
sudo bash/configure_postgresql.sh \
  --version 14 \
  --enable-nvme
```

#### Using Environment Variables
```bash
export POSTGRESQL_VERSION=14
export ENABLE_NVME=true
export CUSTOM_SQL_SCRIPTS="/path/to/script1.sql,/path/to/script2.sql"

sudo bash/configure_postgresql.sh
```

### Command-line Options
- `-v, --version VERSION` - PostgreSQL version (required)
- `-s, --sql-scripts SCRIPTS` - Comma-separated SQL scripts (optional)
- `-n, --enable-nvme` - Enable NVME configuration (optional)
- `-h, --help` - Display help message

---

## Method 2: Ansible

### Prerequisites
- Ubuntu 22.04 (target system)
- Ansible 2.9+ (control machine)
- Python 3 with PyYAML
- SSH access to target systems
- Sudo privileges on target systems

### Directory Structure
```
ansible/
├── roles/
│   ├── pgdg_repository/     # PGDG repo setup
│   ├── postgresql_install/  # PostgreSQL installation
│   ├── system_tuning/       # System optimization
│   ├── postgresql_config/   # PostgreSQL configuration
│   └── nvme_config/         # NVME setup (optional)
├── configure_postgresql.yml # Main playbook
├── vars.yml                 # Variables file
├── inventory.ini            # Inventory file
└── ansible.cfg             # Ansible configuration
```

### Usage

#### 1. Configure Variables
Edit `ansible/vars.yml`:
```yaml
postgresql_version: "14"
enable_nvme: false
custom_sql_scripts: []
```

#### 2. Configure Inventory
Edit `ansible/inventory.ini`:
```ini
[postgresql_servers]
localhost ansible_connection=local

# Or for remote hosts:
# db1.example.com ansible_host=192.168.1.10 ansible_user=ubuntu
```

#### 3. Run Playbook
```bash
cd ansible

# Run full configuration
ansible-playbook configure_postgresql.yml

# Run specific tags
ansible-playbook configure_postgresql.yml --tags setup
ansible-playbook configure_postgresql.yml --tags config
ansible-playbook configure_postgresql.yml --tags nvme

# Check mode (dry run)
ansible-playbook configure_postgresql.yml --check

# Limit to specific hosts
ansible-playbook configure_postgresql.yml --limit db1.example.com
```

### Available Tags
- `repository` - PGDG repository setup
- `install` - PostgreSQL installation
- `setup` - Repository and installation
- `tuning` - System tuning
- `system` - System configuration
- `config` - PostgreSQL configuration
- `postgresql` - PostgreSQL-specific configuration
- `nvme` - NVME configuration
- `optional` - Optional components

---

## Method 3: Salt (SaltStack)

### Prerequisites
- Ubuntu 22.04
- Salt Master and Minion installed
- Minion registered with Master
- Root/sudo privileges

### Directory Structure
```
salt/
├── states/
│   ├── pgdg_repository/     # PGDG repo setup
│   ├── postgresql_install/  # PostgreSQL installation
│   ├── system_tuning/       # System optimization
│   ├── postgresql_config/   # PostgreSQL configuration
│   └── nvme_config/         # NVME setup (optional)
├── pillar/
│   ├── top.sls             # Pillar top file
│   └── postgresql.sls      # PostgreSQL pillar data
└── top.sls                 # State top file
```

### Usage

#### 1. Configure Salt File Roots
Edit `/etc/salt/master`:
```yaml
file_roots:
  base:
    - /path/to/ibp_config/salt/states

pillar_roots:
  base:
    - /path/to/ibp_config/salt/pillar
```

Restart Salt Master:
```bash
sudo systemctl restart salt-master
```

#### 2. Configure Pillar Data
Edit `salt/pillar/postgresql.sls`:
```yaml
postgresql_version: "14"
enable_nvme: false
custom_sql_scripts: []
```

#### 3. Apply States
```bash
# Apply all states
sudo salt '*' state.apply

# Apply specific states
sudo salt '*' state.apply pgdg_repository
sudo salt '*' state.apply postgresql_install
sudo salt '*' state.apply system_tuning
sudo salt '*' state.apply postgresql_config
sudo salt '*' state.apply nvme_config

# Test mode (dry run)
sudo salt '*' state.apply test=True

# Apply to specific minions
sudo salt 'db1.example.com' state.apply
```

#### 4. Highstate
```bash
# Apply highstate (all states from top.sls)
sudo salt '*' state.highstate

# Highstate in test mode
sudo salt '*' state.highstate test=True
```

---

## Configuration Details

### Calculated Variables

All methods automatically calculate these values based on system resources:

- **memory_bytes** - Total system memory in bytes
- **half_memory_gb** - Half of system memory in GB (minimum 1GB)
- **shared_buffers** - 1/8 of total memory
- **effective_cache_size** - half_memory_gb - shared_buffers
- **workers** - Half of CPU cores
- **other_workers** - Quarter of CPU cores
- **nr_hugepages** - Hugepages for shared memory

### System Files Modified

1. `/etc/apt/preferences.d/pgdg` - APT preferences for PGDG
2. `/etc/postgresql/${version}/main/postgresql.conf` - PostgreSQL settings
3. `/etc/postgresql/${version}/main/pg_hba.conf` - Authentication
4. `/var/lib/postgresql/backup.sh` - Backup script
5. `/etc/sysctl.d/99-ibp.conf` - Kernel parameters
6. `/etc/gai.conf` - Address resolution
7. `/etc/netplan/*.yaml` - Network configuration
8. `/etc/security/limits.d/ibp.conf` - Resource limits
9. `/etc/pam.d/common-session*` - PAM configuration

### PostgreSQL Settings Applied

**Memory Settings:**
- shared_buffers = calculated based on system memory
- effective_cache_size = calculated
- maintenance_work_mem = calculated
- work_mem = calculated

**Worker Settings:**
- max_worker_processes = half of CPU cores
- max_parallel_workers = half of CPU cores
- max_parallel_workers_per_gather = quarter of CPU cores
- max_parallel_maintenance_workers = quarter of CPU cores

**WAL Settings:**
- WAL segment size = 64MB
- wal_buffers = 16MB
- min_wal_size = 1GB
- max_wal_size = 4GB
- wal_compression = on
- archive_mode = on (with gzip compression)

**Performance Settings:**
- effective_io_concurrency = 200
- random_page_cost = 1.1
- huge_pages = try

**Logging:**
- logging_collector = on
- Detailed log formatting with timestamps, users, databases
- Log rotation by size (100MB) and age (1 day)

### Authentication

Local connections (Unix socket and 127.0.0.1) are configured with `trust` authentication for ease of development. **Change this for production systems!**

### Backup Configuration

- Automated backups every 6 hours (02:00, 08:00, 14:00, 20:00)
- Keeps 2 backup versions
- WAL archive cleanup after backups
- Backups compressed with gzip

### Optional NVME Configuration

When enabled and `/mnt/nvme` is mounted:
- Creates directories: `pg_wal`, `pg_backup`, `pg_temp`
- Sets up temporary tablespace on NVME
- Configures systemd service hooks

**Requirements:**
- `/mnt/nvme` must exist
- Must be a mount point
- Must be currently mounted

---

## Post-Installation Steps

After running any configuration method:

1. **Verify PostgreSQL is running:**
   ```bash
   sudo systemctl status postgresql
   ```

2. **Test database connection:**
   ```bash
   sudo -u postgres psql
   ```

3. **Check PostgreSQL version:**
   ```bash
   sudo -u postgres psql -c "SELECT version();"
   ```

4. **Review logs:**
   ```bash
   sudo tail -f /var/log/postgresql/postgresql-*.log
   ```

5. **Verify system parameters:**
   ```bash
   sysctl -a | grep -E "vm.nr_hugepages|kernel.shm|vm.overcommit"
   ```

6. **Reboot (recommended):**
   ```bash
   sudo reboot
   ```
   This ensures all kernel parameters are properly applied.

---

## Troubleshooting

### PostgreSQL won't start
- Check logs: `sudo journalctl -u postgresql -n 50`
- Verify data directory permissions: `ls -la /var/lib/postgresql/`
- Check configuration syntax: `sudo -u postgres /usr/lib/postgresql/14/bin/postgres -D /var/lib/postgresql/14/main -C shared_buffers`

### NVME configuration skipped
- Verify `/mnt/nvme` exists: `ls -la /mnt/nvme`
- Check if mounted: `mountpoint /mnt/nvme`
- Check mount status: `mount | grep nvme`

### Performance issues
- Review PostgreSQL logs for slow queries
- Check `shared_buffers` and `effective_cache_size` values
- Monitor with: `sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"`

### Network configuration issues
- Netplan changes require manual YAML editing
- Test netplan: `sudo netplan generate`
- Apply netplan: `sudo netplan apply`

---

## Security Considerations

### Production Hardening

Before deploying to production:

1. **Change pg_hba.conf authentication:**
   ```
   # Change from 'trust' to 'md5' or 'scram-sha-256'
   local   all   all   scram-sha-256
   host    all   all   127.0.0.1/32   scram-sha-256
   ```

2. **Set PostgreSQL passwords:**
   ```sql
   ALTER USER postgres PASSWORD 'strong_password';
   ```

3. **Restrict network access:**
   - Only allow specific IP addresses in pg_hba.conf
   - Configure firewall rules

4. **Enable SSL/TLS:**
   - Generate certificates
   - Configure `ssl = on` in postgresql.conf

5. **Review and adjust limits:**
   - File descriptors may need adjustment for high-connection workloads
   - Monitor actual resource usage

---

## Variables Reference

### Bash Environment Variables
- `POSTGRESQL_VERSION` - PostgreSQL version
- `CUSTOM_SQL_SCRIPTS` - Comma-separated SQL script paths
- `ENABLE_NVME` - Enable NVME (true/false)

### Ansible Variables (vars.yml)
- `postgresql_version` - PostgreSQL version (string)
- `enable_nvme` - Enable NVME (boolean)
- `custom_sql_scripts` - List of SQL script paths

### Salt Pillar Variables
- `postgresql_version` - PostgreSQL version (string)
- `enable_nvme` - Enable NVME (boolean)
- `custom_sql_scripts` - List of SQL script paths

---

## License

This configuration is provided as-is for use in PostgreSQL deployments on Ubuntu 22.04.

## Support

For issues or questions:
1. Check PostgreSQL documentation: https://www.postgresql.org/docs/
2. Review Ubuntu documentation: https://help.ubuntu.com/
3. Check configuration logs for errors

---

## Version History

- **1.0** - Initial release with Bash, Ansible, and Salt implementations
