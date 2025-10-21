# PostgreSQL Configuration State

{% set postgresql_version = salt['pillar.get']('postgresql_version', '') %}
{% set total_memory_gb = (grains['mem_total'] / 1024) | int %}
{% set half_memory_gb = [((total_memory_gb / 2) | int), 1] | max %}
{% set shared_buffers_gb = [((total_memory_gb / 8) | int), 1] | max %}
{% set effective_cache_size_gb = [(half_memory_gb - shared_buffers_gb), 1] | max %}
{% set workers = [((grains['num_cpus'] / 2) | int), 1] | max %}
{% set other_workers = [((grains['num_cpus'] / 4) | int), 1] | max %}
{% set custom_sql_scripts = salt['pillar.get']('custom_sql_scripts', []) %}

{% if postgresql_version == '' %}
postgresql_version_required:
  test.fail_without_changes:
    - name: PostgreSQL version must be defined in pillar data
{% else %}

postgresql_directories:
  file.directory:
    - names:
      - /var/lib/postgresql/{{ postgresql_version }}_wal_archive
      - /var/log/postgresql
    - user: postgres
    - group: postgres
    - mode: 700
    - makedirs: True

stop_postgresql_for_config:
  service.dead:
    - name: postgresql
    - require:
      - file: postgresql_directories

reset_wal_segsize:
  cmd.run:
    - name: >
        sudo -u postgres /usr/lib/postgresql/{{ postgresql_version }}/bin/pg_resetwal
        -D /var/lib/postgresql/{{ postgresql_version }}/main --wal-segsize 64
    - onlyif: test -d /var/lib/postgresql/{{ postgresql_version }}/main
    - require:
      - service: stop_postgresql_for_config

backup_postgresql_conf:
  cmd.run:
    - name: >
        cp /etc/postgresql/{{ postgresql_version }}/main/postgresql.conf
        /etc/postgresql/{{ postgresql_version }}/main/postgresql.conf.backup.$(date +%s)
    - onlyif: test -f /etc/postgresql/{{ postgresql_version }}/main/postgresql.conf
    - require:
      - cmd: reset_wal_segsize

# Note: Salt doesn't have a great way to set PostgreSQL config values
# This uses sed to update the configuration file
{% for key, value in {
    'shared_buffers': shared_buffers_gb ~ 'GB',
    'effective_cache_size': effective_cache_size_gb ~ 'GB',
    'maintenance_work_mem': ((shared_buffers_gb * 1024 / 16) | int) ~ 'MB',
    'work_mem': (((shared_buffers_gb * 1024) / (workers * 4)) | int) ~ 'MB',
    'max_worker_processes': workers,
    'max_parallel_workers_per_gather': other_workers,
    'max_parallel_workers': workers,
    'max_parallel_maintenance_workers': other_workers,
    'wal_buffers': '16MB',
    'min_wal_size': '1GB',
    'max_wal_size': '4GB',
    'wal_compression': 'on',
    'archive_mode': 'on',
    'archive_command': "'gzip < %p > /var/lib/postgresql/" ~ postgresql_version ~ "_wal_archive/%f.gz'",
    'wal_keep_size': '1GB',
    'checkpoint_completion_target': '0.9',
    'checkpoint_timeout': '15min',
    'max_connections': '200',
    'superuser_reserved_connections': '3',
    'logging_collector': 'on',
    'log_directory': "'/var/log/postgresql'",
    'log_filename': "'postgresql-%Y-%m-%d_%H%M%S.log'",
    'log_rotation_age': '1d',
    'log_rotation_size': '100MB',
    'log_line_prefix': "'%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '",
    'log_checkpoints': 'on',
    'log_connections': 'on',
    'log_disconnections': 'on',
    'log_lock_waits': 'on',
    'log_temp_files': '0',
    'effective_io_concurrency': '200',
    'random_page_cost': '1.1',
    'default_statistics_target': '100',
    'huge_pages': 'try'
}.items() %}

set_{{ key }}:
  file.replace:
    - name: /etc/postgresql/{{ postgresql_version }}/main/postgresql.conf
    - pattern: '^#*{{ key }}.*'
    - repl: '{{ key }} = {{ value }}'
    - append_if_not_found: True
    - require:
      - cmd: backup_postgresql_conf

{% endfor %}

backup_pg_hba_conf:
  cmd.run:
    - name: >
        cp /etc/postgresql/{{ postgresql_version }}/main/pg_hba.conf
        /etc/postgresql/{{ postgresql_version }}/main/pg_hba.conf.backup.$(date +%s)
    - onlyif: test -f /etc/postgresql/{{ postgresql_version }}/main/pg_hba.conf

pg_hba_conf:
  file.managed:
    - name: /etc/postgresql/{{ postgresql_version }}/main/pg_hba.conf
    - source: salt://postgresql_config/files/pg_hba.conf
    - user: postgres
    - group: postgres
    - mode: 640
    - require:
      - cmd: backup_pg_hba_conf

backup_script:
  file.managed:
    - name: /var/lib/postgresql/backup.sh
    - source: salt://postgresql_config/files/backup.sh
    - user: postgres
    - group: postgres
    - mode: 755

backup_cron:
  cron.present:
    - name: /var/lib/postgresql/backup.sh >/dev/null 2>&1
    - user: postgres
    - minute: 0
    - hour: '2,8,14,20'
    - require:
      - file: backup_script

start_postgresql:
  service.running:
    - name: postgresql
    - enable: True
    - watch:
      - file: pg_hba_conf
      - file: set_*

{% for script in custom_sql_scripts %}
execute_sql_{{ loop.index }}:
  cmd.run:
    - name: sudo -u postgres psql -f {{ script }}
    - require:
      - service: start_postgresql
{% endfor %}

{% endif %}
