# Salt State Top File
# Defines which states are applied to which minions

base:
  '*':
    - pgdg_repository
    - postgresql_install
    - system_tuning
    - postgresql_config
    - nvme_config
