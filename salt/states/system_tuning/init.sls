# System Tuning State for PostgreSQL

{% set memory_total_mb = grains['mem_total'] %}
{% set memory_bytes = memory_total_mb * 1024 * 1024 %}
{% set nr_hugepages = ((memory_bytes / 2000000) / 2) | int %}

sysctl_config:
  file.managed:
    - name: /etc/sysctl.d/99-ibp.conf
    - source: salt://system_tuning/files/99-ibp.conf.jinja
    - template: jinja
    - mode: 644
    - user: root
    - group: root
    - context:
        memory_bytes: {{ memory_bytes | int }}
        nr_hugepages: {{ nr_hugepages }}

apply_sysctl:
  cmd.run:
    - name: sysctl -p /etc/sysctl.d/99-ibp.conf
    - onchanges:
      - file: sysctl_config

security_limits:
  file.managed:
    - name: /etc/security/limits.d/ibp.conf
    - mode: 644
    - user: root
    - group: root
    - contents: |
        * soft nofile 1048576
        * hard nofile 1048576
        * soft memlock unlimited
        * hard memlock unlimited

pam_common_session:
  file.append:
    - name: /etc/pam.d/common-session
    - text: session required       pam_limits.so

pam_common_session_noninteractive:
  file.append:
    - name: /etc/pam.d/common-session-noninteractive
    - text: session required       pam_limits.so

gai_config:
  file.append:
    - name: /etc/gai.conf
    - text: |

        precedence ::ffff:0:0/96  100
