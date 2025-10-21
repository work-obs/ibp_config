You must provide me with a solution to configure a database and java application on Ubuntu 22.04.

the configuration will happen on individual configuration files, for which you will need root access through sudo

## Variables

Several variables MUST BE available at all times.

### memory\_bytes
This is the available memory in bytes

### half\_memory\_gb
This is half the memory in GB.  If this amounty is less than 1, set it to 1GB

### shared\_buffers
this is 1/8 of memory in the system

### effective\_cache\_size
this is (half\_memory\_gb - shared\_buffers) 

### postgresql\_version
the version of postgresql to configure

### postgresql\_config\_file
string concatenated from /etc/postgresql/ version /main/postgresql.conf

### workers
number consisting of half of the counted cpu cores

### other\_workers
number consisting of 1/4 of cpu cores


## Configuration files

- There will be different formats for the generated code to do the configuration.  That will be bash, ansible, salt
- create a directory for each type.
- Inside each type generate a library, if best practice allows for that. seperate the library items by file type.  For ansible this library will be roles.
- All parameters are variables should have command-line switches and environment variables.  Defaults are only available when specified.  All parameters must be supplied commandline, environment variables or defaults or the command must fail.
- For each type generate driver scripts that provide or update the parameters and variables via commandline parameters, environment variables or defaults
- a variable should be accessible at all times in the script names half_memory and that should be calculated as ((system\_memory\_kb / 1048576) / 2) where system\_memory\_kb is the system in question's memory in kilobytes. 
- a variable should be accessible at all times
- there is an optional set of configs that can be made with an optional parameter / variable for nvme\_wal\_archive

### /etc/apt/preferences.d/pgdp
- install the ubuntu package postgresql-common
- run the command as root: `/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh` to add the postgresql repository pgdg
- create the config file and it should contain the following contents:
```
Package: *
Pin: release o=pgdg
Pin-Priority: 1001

```
- no other file under /etc/apt/preferences.d/ should refer to the pgdg repository

### /etc/postgresql/${postgresql\_version}/main/postgresql.conf

- a list of config variables will be supplied to the code to set the values in the appropriate values to their level.  Certain values are coming from the calculated values specified to be available at all times.  those variables will be mentioned by name and be enclosed with curly braces as follows: {variable}
- where values refer to a file, confirm that the directory and file exist, and if not, create only the directories. Dvalues refering to a file will start with a /
- reset the wal archive size to 64MB using the command `/usr/lib/${postgresql_version}/bin/pg_resetwal -D /var/lib/postgresql/${postgresql_version}/main --wal-segsize 64`


### /etc/postgresql/${postgresql\_version}/main/pg\_hba.conf
- all local connections over unix domain sockets as well as tcp connections originating from localhost should be set to trust

### /var/lib/postgresql/backup.sh
- should contain the following code
```
#!/bin/bash
export BACKUPS_TO_KEEP=2
export WAL_ARCHIVE="/var/lib/postgresql/14_wal_archive"
export BACKUP_LOCATION="/mnt/nvme/pg_backup"
export PGPORT=27095

# Backups are ordered oldest = 1, newest = $BACKUPS_TO_KEEP
mv_backups() {
  if [ -d "$BACKUP_LOCATION/1" ]
  then
    rm -rf "$BACKUP_LOCATION/1"
  fi

  for i in `/usr/bin/seq 2 1 $BACKUPS_TO_KEEP`
  do
          mkdir -p "$BACKUP_LOCATION/$i"  # always ensure the dir exist before trying to move it
          mv "$BACKUP_LOCATION/$i" "$BACKUP_LOCATION/$((i - 1))"
  done
}

do_backups() {
  mkdir -p "$BACKUP_LOCATION/$BACKUPS_TO_KEEP"
  pg_basebackup -D "$BACKUP_LOCATION/$BACKUPS_TO_KEEP" -Ft --compress=gzip:9 --checkpoint=fast
}

clean_wal_archive() {
  echo "WAL_ARCHIVE=$WAL_ARCHIVE"
  local backups=$(ls -t "$WAL_ARCHIVE"/*.backup.gz)
  for i in $backups
  do
    b=$(basename "$i")
    echo $b
    pg_archivecleanup  -x .gz "$WAL_ARCHIVE" "$b"
  done
  rm -f "$WAL_ARCHIVE"/*backup.gz
}

cd /var/lib/postgresql

mv_backups
do_backups
clean_wal_archive

```
- schedule the backup.sh script under postgresql user's cron as a very silent script every 6 hours, starting at 02:00 in the morning

### /etc/sysctl.d/99-ibp.conf
- a file containing the content with variable substitution from pre-calculated values above
```
# memory_bytes / 4000000 (count of 2MB segments of half the memory)
vm.nr_hugepages = {((memory_bytes / 2000000) / 2)}

# port range both values cannot be even or odd - otherwise we get error
# ip_local_port_range: prefer different parity for start/end values.
net.ipv4.ip_local_port_range=1024 64999
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=90
net.ipv4.tcp_tw_reuse=1
net.core.netdev_max_backlog=182757
net.ipv4.neigh.default.gc_thresh3=8192

fs.aio-max-nr=524288
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=724288
kernel.keys.maxbytes=2000000
kernel.keys.maxkeys=2000

vm.max_map_count=262144

fs.file-max=2097152
# SHMMAX and SHMALL should be equal to physical memory of system, value is in kbytes
# SHMMAX is maximum size of a single segmant, SHMALL is the size of all shared memory combined for the entire system
kernel.shmmax={memory_bytes}
kernel.shmall={memory_bytes}
# Try to avoid OOM-Killer
vm.overcommit_memory=2

```

### /etc/gai.conf
- add to the end of the file 2 lines as follows
```
precedence ::ffff:0:0/96  100

```

### /etc/netplan/\*.yaml or /etc/netplan/\*.yml
- add a line underneath every ethernet interface as follows: 'link-local: []' 
- Example:
```
# This file is generated from information provided by the datasource.  Changes
# to it will not persist across an instance reboot.  To disable cloud-init's
# network configuration capabilities, write a file
# /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg with the following:
# network: {config: disabled}
network:
    ethernets:
        ens3:
            dhcp4: true
            dhcp6: false
            match:
                macaddress: 02:02:58:ef:06:4f
            set-name: ens3
            link-local: []
    version: 2
```

### /etc/security/limits.d/ibp.conf
- the config file should contain:
```
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
```

### /etc/pam.d/common-session and /etc/pam.d/common-session-noninteractive
- the config files should have at the end the following lines
```
session required       pam_limits.so

```

## Optional psql component
- add an optional variable / parameter to list any custom plsql scripts to execute as part of the configuration
- if this parameter is empty, do not bomb the script, just do not execute it.  The default for this parameter is a string with a single space in it

## optional nvme\_wal\_archive
- add this component to the resultant code
- if /mnt/nvme exists, is a mount point, and currently mounted then do this component.  If all 3 conditions are not all met, print a statement why this section is not done and exit.

### /var/lib/postgresql/permissions.sh
- this file must have this content:
```
#!/bin/bash
export DIRS="pg_wal pg_backup pg_temp"
for i in $DIRS
do
  mkdir -p /mnt/nvme/$i
  chmod 0700 /mnt/nvme/$i
  chown postgres:postgres /mnt/nvme/$i
done

```
- set permissions on this file as 0755
- as root change ownership of /mnt/nvme to postgres:postgres

### /etc/systemd/service/postgresql.service.d/nvme.conf

- create the directory /etc/systemd/service/postgresql.service.d
- create the config file and add the following content
```
[Service]
ExecStartPre=/var/lib/postgresql/permissions.sh
ExecStartPost=/var/lib/postgresql/temp_tablespace.sh
```
- then execute the following command as root: `systemctl daemon-reload`

### /var/lib/postgresql/temp_tablespace.sh
- create the config file and add the following content to it
```
#!/bin/bash

psql -U postgres -d postgres <<EOF
DROP TABLESPACE IF EXISTS nvme_temp;
CREATE TABLESPACE nvme_temp LOCATION '/mnt/nvme/pg_temp';
GRANT ALL PRIVILEGES ON TABLESPACE nvme_temp TO PUBLIC;
ALTER SYSTEM SET temp_tablespaces = 'nvme_temp';
SELECT pg_reload_conf();
EOF

```


