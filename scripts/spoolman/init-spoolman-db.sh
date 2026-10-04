#!/usr/bin/env bash
set -Eeuo pipefail

app_password="$(cat /run/secrets/spoolman_db_password)"
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 --set=app_password="$app_password" <<'SQL'
CREATE ROLE spoolman LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD :'app_password';
CREATE DATABASE spoolman OWNER spoolman;
REVOKE ALL ON DATABASE spoolman FROM PUBLIC;
GRANT CONNECT ON DATABASE spoolman TO spoolman;
SQL
