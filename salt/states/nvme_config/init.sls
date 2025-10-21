# NVME Configuration State (Optional)

{% set enable_nvme = salt['pillar.get']('enable_nvme', False) %}
{% set nvme_mounted = salt['mount.is_mounted']('/mnt/nvme') %}

{% if enable_nvme and nvme_mounted %}

permissions_script:
  file.managed:
    - name: /var/lib/postgresql/permissions.sh
    - source: salt://nvme_config/files/permissions.sh
    - user: postgres
    - group: postgres
    - mode: 755

temp_tablespace_script:
  file.managed:
    - name: /var/lib/postgresql/temp_tablespace.sh
    - source: salt://nvme_config/files/temp_tablespace.sh
    - user: postgres
    - group: postgres
    - mode: 755

nvme_ownership:
  file.directory:
    - name: /mnt/nvme
    - user: postgres
    - group: postgres

systemd_dropin_dir:
  file.directory:
    - name: /etc/systemd/system/postgresql.service.d
    - mode: 755

systemd_nvme_conf:
  file.managed:
    - name: /etc/systemd/system/postgresql.service.d/nvme.conf
    - mode: 644
    - contents: |
        [Service]
        ExecStartPre=/var/lib/postgresql/permissions.sh
        ExecStartPost=/var/lib/postgresql/temp_tablespace.sh
    - require:
      - file: systemd_dropin_dir

reload_systemd:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: systemd_nvme_conf

run_permissions_script:
  cmd.run:
    - name: /var/lib/postgresql/permissions.sh
    - require:
      - file: permissions_script
      - file: nvme_ownership

{% else %}

nvme_skipped:
  test.show_notification:
    - name: NVME configuration skipped
    - text: |
        NVME configuration is disabled or /mnt/nvme is not mounted
        Enable NVME: {{ enable_nvme }}
        NVME Mounted: {{ nvme_mounted }}

{% endif %}
