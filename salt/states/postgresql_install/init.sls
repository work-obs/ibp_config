# PostgreSQL Installation State

{% set postgresql_version = salt['pillar.get']('postgresql_version', '') %}

{% if postgresql_version == '' %}
postgresql_version_required:
  test.fail_without_changes:
    - name: PostgreSQL version must be defined in pillar data
{% else %}

postgresql_{{ postgresql_version }}:
  pkg.installed:
    - pkgs:
      - postgresql-{{ postgresql_version }}
      - postgresql-client-{{ postgresql_version }}
      - postgresql-contrib-{{ postgresql_version }}

postgresql_service:
  service.enabled:
    - name: postgresql
    - require:
      - pkg: postgresql_{{ postgresql_version }}

{% endif %}
