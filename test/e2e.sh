#!/usr/bin/env bash
# End-to-end run against a local Citus (brew install citus; citus in shared_preload_libraries)
# with a fake `aws` that stores S3 objects in a temp folder.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
mkdir "$TMP/bin" "$TMP/s3"
cp test/aws "$TMP/bin/aws"
export PATH="$TMP/bin:$PATH" FAKE_S3="$TMP/s3" DB_MANAGER_CONFIG="$TMP/config"
SRC=cfdump_e2e_src TGT=cfdump_e2e_tgt

for db in $SRC $TGT; do
  dropdb --if-exists $db; createdb $db 2> /dev/null
  psql -q -d $db -v ON_ERROR_STOP=1 -c "CREATE EXTENSION citus; CREATE EXTENSION hll; CREATE EXTENSION hstore;
    SELECT citus_set_coordinator_host('localhost', 5432); SELECT citus_set_node_property('localhost', 5432, 'shouldhaveshards', true);"  > /dev/null
done
psql -q -d $SRC -v ON_ERROR_STOP=1 -c "
  CREATE TYPE plan AS ENUM ('free', 'pro');
  CREATE TABLE accounts (id bigint PRIMARY KEY, meta hstore, plan plan DEFAULT 'free');
  CREATE TABLE websites (id bigint, account_id bigint REFERENCES accounts(id), PRIMARY KEY (account_id, id));
  SELECT create_reference_table('accounts');
  SELECT create_distributed_table('websites', 'account_id', shard_count => 4);
  INSERT INTO accounts SELECT g, 'k=>v' FROM generate_series(1, 100) g;
  INSERT INTO websites SELECT g, g % 100 + 1 FROM generate_series(1, 5000) g;" > /dev/null
psql -q -d $TGT -c "CREATE TABLE old_junk (id int);"

# settings, dump + upload, quit
printf '%s\n' "postgres://$USER@127.0.0.1:5432/$SRC" "postgres://$USER@127.0.0.1:5432/$TGT" "$TMP/a" \
  bucket citus AKIATEST secret us-east-1 2 7 | ./db-manager > "$TMP/a.log" 2>&1
# restore from S3 into a fresh dumps folder, restore the same dump again from local, quit
printf '%s\n' 3 1 127.0.0.1 4 1 127.0.0.1 7 | DUMPS_DIR="$TMP/b" ./db-manager > "$TMP/b.log" 2>&1

[ "$(stat -f %Lp "$TMP/config")" = 600 ] || { echo "config not 600"; exit 1; }
[ "$(grep -c 'sharding layout matches source' "$TMP/b.log")" = 2 ] || { cat "$TMP/b.log"; echo "restore check failed"; exit 1; }
[ "$(psql -d $TGT -Atc "SELECT shard_count FROM citus_tables WHERE table_name = 'websites'::regclass")" = 4 ]
[ -z "$(psql -d $TGT -Atc "SELECT to_regclass('old_junk')")" ]
[ "$(psql -d $TGT -Atc "SELECT count(*) FROM websites")" = 5000 ]
[ -f "$TMP/s3/bucket/citus/$(ls "$TMP/a").tar" ] || { echo "upload not at bucket/citus"; exit 1; }
dropdb $SRC; dropdb $TGT; rm -rf "$TMP"
echo "e2e OK"
