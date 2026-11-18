# db-manager

Interactive terminal tool to dump a PostgreSQL + Citus database and restore it into another cluster,
keeping the sharding layout (reference and distributed tables, shard counts). Dumps can stay on the
local machine or go to S3.

## Install

```sh
brew tap sap1enza/db-manager https://github.com/sap1enza/db-manager
brew trust sap1enza/db-manager   # recent Homebrew refuses third-party taps until trusted
brew install db-manager
```

Installs `postgresql@17` (for `psql`, `pg_dump`, `pg_restore`) and `awscli`.

## Use

```sh
db-manager
```

The first run asks for settings and saves them to `~/.config/db-manager/config` (mode 600):

| Setting | Example |
| --- | --- |
| Source DB URL | `postgres://citus:...@source-host:5432/citus?sslmode=require` |
| Target DB URL | `postgres://citus:...@target-host:5432/citus?sslmode=require` |
| Local dumps folder | `~/db-manager-dumps` |
| S3 bucket | `my-backups` |
| S3 folder | `citus-dumps` (blank = bucket root) |
| AWS key, secret, region of the bucket | blank key = default AWS CLI credentials |

Then pick from the menu:

1. Create dump on local machine
2. Create dump and upload to S3
3. Restore dump from S3
4. Restore dump from local machine
5. List dumps on S3
6. Settings

Restoring **drops every table in `public` on the target** and asks you to type the target host first.

Environment variables override saved settings. Optional: `JOBS` (parallel jobs, default 8),
`MAINTENANCE_MEM` (index builds, default 512MB).

Scripted use: `db-manager dump`, `WORK_DIR=~/db-manager-dumps/<name> db-manager restore`.

## What a dump contains

Each dump is a folder named by UTC timestamp, uploaded to S3 as one `<name>.tar`:
the `pg_dump` directory-format dump of `public`, the restore list, the `create_*_table` calls that
recreate the sharding, and source snapshots (layout, extensions) used to verify the restore.

Use port 5432, not PgBouncer (6432).

Limits:
- Only the `public` schema is copied. Functions, procedures and aggregates in `public` are left out.
- Tables named like `<name>_<6+ digits>` (e.g. date-suffixed partitions) are taken for leaked Citus shards and stop the dump.

## Test

`test/e2e.sh` runs the full menu against a local Citus (`brew install citus`, `citus` in
`shared_preload_libraries`) with a fake `aws` that stores objects in a temp folder.
