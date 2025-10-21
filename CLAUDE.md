# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains PostgreSQL configuration automation tools for IBP (International Business Platform). It provides three different implementation methods:

1. **Bash Scripts** - Standalone shell scripts with modular library structure
2. **Ansible Playbooks** - Infrastructure as code using Ansible roles and playbooks
3. **Salt States** - Configuration management using SaltStack

## Repository Information

- **Repository**: https://github.com/work-obs/ibp_config
- **Organization**: work-obs
- **Access**: Public repository
- **Primary Account**: bkahlerventer

## Git Workflow Automation

This project uses **permanent git automation** for streamlined development workflow.

### Automated Git Operations

After completing tasks, Claude Code will automatically:

1. **Stage changes**: `git add .` (or specific files as appropriate)
2. **Create commit**: With descriptive message following the format:
   ```
   [Claude Code] Brief summary of changes

   - Detailed change 1
   - Detailed change 2
   - Detailed change 3

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```
3. **Push to remote**: `git push origin <current-branch>`
4. **Verify push**: Confirm successful push to remote repository

### Manual Git Operations

You can still perform manual git operations:
- `git status` - Check working directory status
- `git log` - View commit history
- `git diff` - View changes
- `git branch` - Manage branches
- `git pull` - Pull latest changes

### Branch Strategy

- **master** - Main branch for stable releases
- Feature branches - For development work (create as needed)

### GitHub CLI Integration

The repository is integrated with GitHub CLI (`gh`) for enhanced workflow:
- Create pull requests: `gh pr create`
- View issues: `gh issue list`
- View repository: `gh repo view work-obs/ibp_config`

## Project Structure

```
ibp_config/
├── bash/                    # Bash script implementation
│   ├── lib/                # Modular libraries
│   └── postgresql-config.sh # Main driver script
├── ansible/                # Ansible implementation
│   ├── roles/              # Ansible roles
│   ├── playbooks/          # Main playbooks
│   └── inventory/          # Inventory files
├── salt/                   # Salt implementation
│   ├── salt/               # State files
│   ├── pillar/             # Pillar data
│   └── orchestrate/        # Orchestration files
└── README.md              # Main documentation

```

## Development Commands

### Testing Scripts

```bash
# Test bash script (dry-run)
cd bash
./postgresql-config.sh --dry-run

# Test Ansible playbook
cd ansible
ansible-playbook -i inventory/hosts playbooks/postgresql-setup.yml --check

# Test Salt states
cd salt
salt-call --local state.apply postgresql --test
```

### Running Implementations

```bash
# Run bash script
cd bash
sudo ./postgresql-config.sh

# Run Ansible playbook
cd ansible
ansible-playbook -i inventory/hosts playbooks/postgresql-setup.yml

# Apply Salt states
cd salt
salt-call --local state.apply postgresql
```

## Key Features

All three implementations provide:
- Dynamic resource calculation based on system memory and CPU cores
- PostgreSQL optimization (shared_buffers, work_mem, WAL settings, etc.)
- System tuning (kernel parameters, limits, network configuration)
- Automated backup script generation with cron scheduling
- Optional NVMe storage configuration
- Custom SQL script execution support

## Configuration

### Variables and Parameters

Each implementation uses variables for customization:
- **Memory allocation**: Calculated from system resources
- **Worker processes**: Based on CPU core count
- **Storage paths**: Configurable for data, WAL, and backups
- **Network settings**: Hostname, ports, connection limits
- **Backup settings**: Schedule, retention, destination

### Customization

- **Bash**: Edit variables in `postgresql-config.sh` or `lib/variables.sh`
- **Ansible**: Modify `inventory/group_vars/all.yml` or `playbooks/postgresql-setup.yml`
- **Salt**: Update pillar data in `pillar/postgresql.sls`

## Security Considerations

- Run with appropriate privileges (sudo/root for system changes)
- Review generated configurations before production deployment
- Secure backup destinations with proper permissions
- Use encrypted connections for PostgreSQL (SSL/TLS)
- Review and adjust `pg_hba.conf` for access control
- Store sensitive credentials securely (not in version control)

## Documentation

- **Main README**: Comprehensive usage instructions in `README.md`
- **Bash README**: Specific to bash implementation in `bash/README.md`
- **Ansible README**: Specific to Ansible in `ansible/README.md`
- **Salt README**: Specific to Salt in `salt/README.md`

## Development Notes

- This is an infrastructure automation project, not a web application
- Focus on idempotency and repeatability
- Test in non-production environments first
- Follow infrastructure as code best practices
- Document any configuration changes
- Use descriptive commit messages

## Support and Issues

For bugs, feature requests, or questions:
- Create an issue in the GitHub repository
- Use the GitHub Discussions feature
- Contact the repository maintainers

---

**Last Updated**: 2025-10-21
**Maintained By**: work-obs organization
**License**: (Add license information if applicable)
