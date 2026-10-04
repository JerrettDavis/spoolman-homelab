#!/usr/bin/env bash
set -Eeuo pipefail

APP="web-and-proxy-spoolman-1"
DB="web-and-proxy-spoolman-db-1"
HOST_HEADER="spoolman.jerrettdavis.com"

wait_healthy() {
  local container="$1" attempts="$2"
  for _ in $(seq 1 "$attempts"); do
    [[ "$(docker inspect "$container" --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null || true)" == healthy ]] && return 0
    sleep 5
  done
  return 1
}

api() {
  local method="$1" path="$2" body="${3:-}"
  docker exec -e METHOD="$method" -e API_PATH="$path" -e API_BODY="$body" -e API_HOST="$HOST_HEADER" "$APP" python -c '
import json, os, urllib.request
body = os.environ["API_BODY"].encode() if os.environ["API_BODY"] else None
request = urllib.request.Request(
    "http://127.0.0.1:8000/api/v1" + os.environ["API_PATH"],
    data=body,
    method=os.environ["METHOD"],
    headers={"Host": os.environ["API_HOST"], "Content-Type": "application/json"},
)
with urllib.request.urlopen(request, timeout=10) as response:
    payload = response.read().decode()
    if payload:
        parsed = json.loads(payload)
        print(parsed.get("id", response.status) if isinstance(parsed, dict) else response.status)
    else:
        print(response.status)
'
}

wait_healthy "$DB" 12
wait_healthy "$APP" 24

role_flags="$(docker exec "$DB" sh -euc 'PGPASSWORD=$(cat /run/secrets/spoolman_db_password) psql -h 127.0.0.1 -U spoolman -d spoolman -Atqc "select rolsuper,rolcreatedb,rolcreaterole,rolbypassrls from pg_roles where rolname=current_user"')"
[[ "$role_flags" == 'f|f|f|f' ]]
if docker run --rm --network web-and-proxy_spoolman-private \
  -e PGPASSWORD='deliberately-wrong-password' \
  postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea \
  psql -h spoolman-db -U spoolman -d spoolman -Atqc 'select 1' >/dev/null 2>&1; then
  echo 'Wrong database password was accepted.' >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
crud_id="$(api POST /vendor "{\"name\":\"Codex CRUD ${stamp}\"}")"
[[ "$(api GET "/vendor/${crud_id}")" == "$crud_id" ]]
[[ "$(api PATCH "/vendor/${crud_id}" '{"comment":"updated"}')" == "$crud_id" ]]

persist_id="$(api POST /vendor "{\"name\":\"Codex Persistence ${stamp}\"}")"
docker restart "$APP" >/dev/null
wait_healthy "$APP" 36
[[ "$(api GET "/vendor/${persist_id}")" == "$persist_id" ]]

docker restart "$DB" >/dev/null
wait_healthy "$DB" 24
docker restart "$APP" >/dev/null
wait_healthy "$APP" 36
[[ "$(api GET "/vendor/${persist_id}")" == "$persist_id" ]]

api DELETE "/vendor/${crud_id}" >/dev/null
api DELETE "/vendor/${persist_id}" >/dev/null

echo "PASS_PRIVATE_SPOOLMAN role_flags=${role_flags} crud_id=${crud_id} persistence_id=${persist_id}"
