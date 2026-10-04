#!/usr/bin/env bash
set -Eeuo pipefail

ARCHIVE="${1:?usage: verify-spoolman-backup.sh ARCHIVE.tar.gz}"
POSTGRES_IMAGE="postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea"
UTILITY_IMAGE="alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8"
name="spoolman-restore-$(date -u +%Y%m%d%H%M%S)-$$"
tmp="$(mktemp -d /tmp/spoolman-restore.XXXXXX)"
password_file="${tmp}/password"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "${name}-data" >/dev/null 2>&1 || true
  case "$tmp" in
    /tmp/spoolman-restore.*) rm -rf -- "$tmp" ;;
    *) echo "Refusing unsafe cleanup target: $tmp" >&2 ;;
  esac
}
trap cleanup EXIT

tar -xzf "$ARCHIVE" -C "$tmp"
(cd "$tmp" && sha256sum -c SHA256SUMS >/dev/null)
tar -tzf "$tmp/spoolman-data.tar.gz" >/dev/null
openssl rand -base64 48 | tr -d '\r\n' > "$password_file"
chmod 644 "$password_file"

docker volume create "${name}-data" >/dev/null
docker run -d --name "$name" \
  -e POSTGRES_DB=spoolman \
  -e POSTGRES_USER=restore_admin \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/restore_password \
  -v "$password_file:/run/secrets/restore_password:ro" \
  -v "${name}-data:/var/lib/postgresql/data" \
  "$POSTGRES_IMAGE" >/dev/null

for _ in $(seq 1 36); do
  docker exec "$name" pg_isready -U restore_admin -d spoolman >/dev/null 2>&1 && break
  sleep 5
done
docker exec "$name" pg_isready -U restore_admin -d spoolman >/dev/null

docker cp "$tmp/spoolman.dump" "$name:/tmp/spoolman.dump"
docker exec "$name" sh -euc '
  PGPASSWORD=$(cat /run/secrets/restore_password)
  export PGPASSWORD
  pg_restore -h 127.0.0.1 -U restore_admin -d spoolman --exit-on-error --no-owner --no-acl /tmp/spoolman.dump
  psql -h 127.0.0.1 -U restore_admin -d spoolman -Atqc \
    "select count(*) from information_schema.tables where table_schema='\''public'\''" | grep -Eq "^[1-9][0-9]*$"
'

echo 'PASS_SPOOLMAN_BACKUP_RESTORE'
