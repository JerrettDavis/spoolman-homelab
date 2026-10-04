#!/usr/bin/env bash
set -Eeuo pipefail

DB="web-and-proxy-spoolman-db-1"
DATA_VOLUME="web-and-proxy_spoolman-data"
UTILITY_IMAGE="alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8"
tmp="$(mktemp -d /tmp/spoolman-backup.XXXXXX)"

cleanup() {
  case "$tmp" in
    /tmp/spoolman-backup.*) rm -rf -- "$tmp" ;;
    *) echo "Refusing unsafe cleanup target: $tmp" >&2 ;;
  esac
}
trap cleanup EXIT

docker exec "$DB" sh -euc '
  PGPASSWORD=$(cat /run/secrets/spoolman_db_password)
  export PGPASSWORD
  pg_dump -h 127.0.0.1 -U spoolman -d spoolman --format=custom --no-owner --no-acl
' > "$tmp/spoolman.dump"

docker run --rm \
  -v "${DATA_VOLUME}:/source:ro" \
  -v "$tmp:/backup" \
  "$UTILITY_IMAGE" tar -czf /backup/spoolman-data.tar.gz -C /source .

cat > "$tmp/manifest.txt" <<EOF
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
database=spoolman
database_role=spoolman
data_volume=${DATA_VOLUME}
EOF

(
  cd "$tmp"
  sha256sum spoolman.dump spoolman-data.tar.gz manifest.txt > SHA256SUMS
  tar -czf - spoolman.dump spoolman-data.tar.gz manifest.txt SHA256SUMS
)
