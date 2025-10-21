#!/bin/bash

psql -U postgres -d postgres <<EOF
DROP TABLESPACE IF EXISTS nvme_temp;
CREATE TABLESPACE nvme_temp LOCATION '/mnt/nvme/pg_temp';
GRANT ALL PRIVILEGES ON TABLESPACE nvme_temp TO PUBLIC;
ALTER SYSTEM SET temp_tablespaces = 'nvme_temp';
SELECT pg_reload_conf();
EOF
