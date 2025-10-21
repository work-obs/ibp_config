# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PostgreSQL configuration automation for Ubuntu 22.04 with three implementation methods:
- **bash/** - Modular shell scripts with library-based architecture
- **ansible/** - Infrastructure as Code with role-based playbooks
- **salt/** - Configuration management with state files and pillar data

All three methods configure identical PostgreSQL settings, system tuning, and optional NVME storage.

## Repository

- **URL**: https://github.com/work-obs/ibp_config
- **Account**: bkahlerventer
- **Git Automation**: ENABLED - Auto-commit and push after tasks complete

## Architecture

### Bash Implementation (bash/)

**Modular library pattern** where each library handles one configuration aspect:

```
configure_postgresql.sh (main driver)
  ├── lib/variables.sh        # Calculate memory/CPU-based values
  ├── lib/apt_pgdg.sh        # PGDG repository setup
  ├── lib/postgresql_conf.sh # PostgreSQL configuration
  ├── lib/pg_hba_conf.sh     # Authentication rules
  ├── lib/backup.sh          # Backup script + cron
  ├── lib/sysctl_conf.sh     # Kernel parameters
  ├── lib/gai_conf.sh        # IPv6 precedence
  ├── lib/netplan_conf.sh    # Network link-local disable
  ├── lib/limits_conf.sh     # File/memory limits
  ├── lib/pam_conf.sh        # PAM session limits
  ├── lib/nvme_conf.sh       # Optional NVME setup
  └── lib/custom_sql.sh      # Execute custom SQL scripts
```

**Key pattern**: `configure_postgresql.sh` sources all libraries, calculates variables once via `init_variables()`, then calls library functions sequentially. Each library function is idempotent and checks prerequisites.

### Ansible Implementation (ansible/)

**Role-based architecture** with single playbook orchestration:

```
configure_postgresql.yml (main playbook)
  ├── vars.yml                          # Variables file
  ├── roles/pgdg_repository/            # PGDG setup
  ├── roles/postgresql_install/         # Package installation
  ├── roles/system_tuning/              # sysctl, limits, PAM, GAI, netplan
  ├── roles/postgresql_config/          # PostgreSQL conf + backup
  └── roles/nvme_config/                # Optional NVME (conditional)
```

**Key pattern**: Each role has `tasks/main.yml` with tags, `defaults/main.yml` for variables, and optional `handlers/main.yml`. Variables are calculated using Jinja2 filters in templates. Roles use `when:` conditions for optional tasks.

### Salt Implementation (salt/)

**State-based configuration management**:

```
top.sls (state orchestration)
  ├── pillar/postgresql.sls             # Variables/configuration data
  ├── states/pgdg_repository/init.sls   # PGDG setup
  ├── states/postgresql_install/init.sls# Package installation
  ├── states/system_tuning/init.sls     # System configuration
  ├── states/postgresql_config/init.sls # PostgreSQL configuration
  └── states/nvme_config/init.sls       # Optional NVME (conditional)
```

**Key pattern**: States use Jinja2 templating with pillar data. State IDs are unique across all states. Requirements enforce ordering. Optional states use `{% if %}` conditions from pillar data.

### Variable Calculation Logic

All implementations calculate these values from system resources:

```python
memory_bytes = /proc/meminfo MemTotal * 1024
half_memory_gb = max(1, (memory_bytes / 1GB) / 2)
shared_buffers = max(1, memory_bytes / 8 / 1GB)
effective_cache_size = half_memory_gb - shared_buffers
cpu_cores = nproc
workers = max(1, cpu_cores / 2)
other_workers = max(1, cpu_cores / 4)
nr_hugepages = (memory_bytes / 2MB) / 2
```

These variables drive PostgreSQL memory settings and worker processes.

## Commands

### Bash Execution

```bash
# Required: PostgreSQL version
sudo bash/configure_postgresql.sh --version 14

# With custom SQL scripts
sudo bash/configure_postgresql.sh --version 14 \
  --sql-scripts "/path/to/init.sql,/path/to/users.sql"

# With NVME support (requires /mnt/nvme mounted)
sudo bash/configure_postgresql.sh --version 14 --enable-nvme

# Using environment variables
export POSTGRESQL_VERSION=14
export ENABLE_NVME=true
export CUSTOM_SQL_SCRIPTS="/path/to/script1.sql,/path/to/script2.sql"
sudo bash/configure_postgresql.sh
```

### Ansible Execution

```bash
cd ansible

# Edit vars.yml first to set postgresql_version
ansible-playbook configure_postgresql.yml

# Check mode (dry run)
ansible-playbook configure_postgresql.yml --check

# Run specific tags
ansible-playbook configure_postgresql.yml --tags setup      # repo + install
ansible-playbook configure_postgresql.yml --tags tuning     # system tuning
ansible-playbook configure_postgresql.yml --tags config     # postgresql conf
ansible-playbook configure_postgresql.yml --tags nvme       # nvme setup

# Limit to specific hosts
ansible-playbook configure_postgresql.yml --limit db1.example.com
```

### Salt Execution

```bash
# Edit /etc/salt/master file_roots and pillar_roots first
# Edit salt/pillar/postgresql.sls to set postgresql_version

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

# Highstate
sudo salt '*' state.highstate
```

## Development Guidelines

### When Modifying Configuration

All three implementations must stay synchronized. If changing a PostgreSQL setting:

1. Update `bash/lib/postgresql_conf.sh`
2. Update `ansible/roles/postgresql_config/tasks/main.yml` (or template)
3. Update `salt/states/postgresql_config/init.sls` (or template)

### Parameter Handling

All implementations support three sources (priority order):
1. Command-line arguments (Bash) / Playbook vars (Ansible) / Pillar (Salt)
2. Environment variables (Bash only)
3. Defaults (if specified)

**Required**: `postgresql_version` - Must fail if not provided
**Optional**: `custom_sql_scripts` (default: empty), `enable_nvme` (default: false)

### NVME Configuration

Only applied if ALL conditions met:
- `/mnt/nvme` exists
- `/mnt/nvme` is a mount point (`mountpoint -q /mnt/nvme`)
- `/mnt/nvme` is currently mounted

Creates temporary tablespace on NVME with systemd hooks for persistence.

### Testing

```bash
# Bash: Add echo statements to library functions for debugging
# Ansible: Use --check mode and -v/-vv/-vvv for verbosity
# Salt: Use test=True mode and state.show_sls to preview

# Verify PostgreSQL after configuration
sudo -u postgres psql -c "SELECT version();"
sudo -u postgres psql -c "SHOW shared_buffers;"
sudo -u postgres psql -c "SHOW max_worker_processes;"
```

## Critical Files Modified

These files are overwritten/modified by all implementations:
- `/etc/apt/preferences.d/pgdg` - PGDG repository priority
- `/etc/postgresql/${version}/main/postgresql.conf` - Main config
- `/etc/postgresql/${version}/main/pg_hba.conf` - Auth (sets to `trust` for local)
- `/var/lib/postgresql/backup.sh` - Backup script (runs every 6 hours via cron)
- `/etc/sysctl.d/99-ibp.conf` - Kernel parameters (requires reboot)
- `/etc/security/limits.d/ibp.conf` - File/memory limits
- `/etc/pam.d/common-session*` - PAM limits integration
- `/etc/gai.conf` - IPv6 precedence
- `/etc/netplan/*.yaml` - Network link-local disabled

**Security warning**: `pg_hba.conf` is configured with `trust` authentication for local connections. Change to `scram-sha-256` or `md5` for production.

## Source Reference

The original requirements are in `Prompt.md` - this documents the variable calculations, configuration files, and expected behavior. Use this as the source of truth when understanding "why" certain values are calculated or configurations are applied.
