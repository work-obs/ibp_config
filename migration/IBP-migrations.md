
## Preparation

1. On the `temporary instance` create an ssh key as `root`:
```bash
ssh-keygen -t ed25519
```
2. Copy the contents of `/root/.ssh/id_ed25519.pub` to the `old instance` in `/root/.ssh/authorized_keys`.
3. If you are unable to SSH/rsync, update `/etc/ssh/sshd_config` on the `old instance` with the below values and then run `systemctl restart ssh`:
```bash
PermitRootLogin yes
AllowUsers smoothie www-data root
AllowGroups www-data smoothie root
```
2. On the `temporay instance` run `stopdw`.
3. On the `temporary instance` rename the smoothie folder:
```bash
mv /opt/smoothie11 /opt/smoothie11_old
```
5. Copy all the necessary files over on the `temporary instance` from the `old instance`:
```bash
rsync -avPHz <source_ip>:/opt/* /opt/
rsync -avPHz <source_ip>:/etc/default/jetty /etc/default/jetty
rsync -avPHz <source_ip>:/home/smoothie/Scripts/* /home/smoothie/Scripts/
rsync -avPHz <source_ip>:/etc/ssh/ssh_host* /etc/ssh/
```
6. Only if `/etc/profile.d/ibp.sh` exists on the `old instance`, do the following (run on `temporary instance` as root):
```bash
rsync -avPHz <source_ip>:/home/smoothie/bi_cube* /home/smoothie/
rsync -avPHz <source_ip>:/etc/profile.d/ibp* /etc/profile.d/

chown smoothie:smoothie /etc/profile.d/ibp*
chown smoothie:smoothie /home/smoothie/bi_cube*
chown root:smoothie /home/smoothie/{bi_cube_fetch_logs_connections.sh,bi_cube_fetch_logs_queries.sh,bi_cube_whitelist_ips.sh}
rm -r /opt/bi_cube_ip_whitelist/{bin,lib}

apt install python3-venv

python3 -m venv /opt/bi_cube_ip_whitelist/
source /opt/bi_cube_ip_whitelist/bin/activate
pip install boto3 mysql-connector-python psycopg2-binary privatebinapi
```
6. Run `timedatectl` on the `old instance` and set the timezone on the temporary instance to match it:
```bash
timedatectl set-timezone <timezone>
```
7. Check the salt minion ID on the `old instance` in `/etc/salt/minion_id` and update it on the `temporary insstance`.

## Data Migration

1. Check that the are no batches running by logging into the front-end -> Admin -> Status
2. On the `old instance`, `stopdw` and start dumping the Postgres data (you can continue up to `step 7` in while this is running):
```bash
stopdw
sudo su - postgres
pg_dumpall --clean --if-exists > full_backup.sql
```
3. Sync the changes. Run the below on the `temporary instance`:
```bash
rsync -avPHz <source_ip>:/opt/* /opt/
rsync -avPHz <source_ip>:/home/smoothie/Scripts/* /home/smoothie/Scripts/
```
4. Only if `/etc/profile.d/ibp.sh` exists on the `old instance`, copy the following (run on `temporary instance`):
```bash
rsync -avPHz <source_ip>:/home/smoothie/bi_cube* /home/smoothie/
rsync -avPHz <source_ip>:/etc/profile.d/ibp* /etc/profile.d/

chown smoothie:smoothie /etc/profile.d/ibp*
chown smoothie:smoothie /home/smoothie/bi_cube*
chown root:smoothie /home/smoothie/{bi_cube_fetch_logs_connections.sh,bi_cube_fetch_logs_queries.sh,bi_cube_whitelist_ips.sh}
rm -r /opt/bi_cube_ip_whitelist/{bin,lib}
```
5. On the `temporary instance` run the following as `smoothie`:
```bash
/opt/smoothie11/mambo/UpdateSchedule.sh
```
6. Copy the new app config back:
```bash
cp /opt/smoothie11_old/jetty/webapps/ROOT.war /opt/smoothie11/jetty/webapps/ROOT.war
cp /opt/smoothie11_old/mambo/lib/MamboCommand.jar /opt/smoothie11/mambo/lib/MamboCommand.jar
cp /opt/smoothie11_old/mambo/lib/Smoothie.jar /opt/smoothie11/mambo/lib/Smoothie.jar
```
6. Once the dump is done on the `old instance`, copy it over (run the below from the `temporary instance`):
   ```bash
   rsync -avPHz <source_ip>:/var/lib/postgresql/full_backup.sql /var/lib/postgresql/
   ```
7. Import the data on the `temporary instance`:
```bash
sudo su - postgres
psql -U postgres -f full_backup.sql
```
8. Analyze Postgres DB's:
```bash
psql -U postgres -p 27095 -l -t | cut -d'|' -f1 | grep -v template | while read db; do
  echo "Analyzing database: $db"
  psql -U postgres -p 27095 -d "$db" -c "ANALYZE;"
done
```
9. Reindex Postgres DB's:
```bash
psql -U postgres -p 27095 -l -t | cut -d'|' -f1 | grep -v template | while read db; do
  echo "Reindexing database: $db"
  psql -U postgres -p 27095 -d "$db" -c "REINDEX DATABASE $db;"
done
```
10. Vacuum Postgres DB's:
```bash
psql -U postgres -p 27095 -l -t | cut -d'|' -f1 | grep -v template | while read db; do
  echo "Vacuum analyze database: $db"
  psql -U postgres -p 27095 -d "$db" -c "VACUUM ANALYZE;"
done
```


## Final steps
1. Switch off both `temporary instance` and `old instance`.
2. Detach the old volume and prepared volume, then attach the newly prepared volume to the old instance.
3. Power on the old instance that now has the newly prepared volume.
4. Pre-seed the SSH connection from lastion/bastion as the SSH fingerprint would have changed.
5. From bastion/lastion run (as smoothie):
```bash
sudo /home/smoothie/update_known_hosts.sh <instanceName>
```
6. SSH to the instance and update the hostname in `/home/smoothie/.bashrc` and on the system:
```bash
sudo hostnamectl set-hostname <hostname>
```
7. SSH to `deploy` and recycle the key:
```bash
salt-key -d <minion-id>
salt-key -a <minion-id>
```
8. Run the New Relic state against the new server:
```
salt -t30 <minion-id> state.apply ibp.setup           
```
9. Log in to the front-end to ensure it is working as expected.
10. Update the AWS tags on the new volume to match the old tags.
