# PGDG Repository Configuration State

postgresql-common:
  pkg.installed:
    - name: postgresql-common

add_pgdg_repository:
  cmd.run:
    - name: /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
    - creates: /etc/apt/sources.list.d/pgdg.list
    - require:
      - pkg: postgresql-common

pgdg_apt_preferences:
  file.managed:
    - name: /etc/apt/preferences.d/pgdg
    - mode: 644
    - user: root
    - group: root
    - contents: |
        Package: *
        Pin: release o=pgdg
        Pin-Priority: 1001

update_apt_cache:
  cmd.run:
    - name: apt-get update
    - require:
      - file: pgdg_apt_preferences
