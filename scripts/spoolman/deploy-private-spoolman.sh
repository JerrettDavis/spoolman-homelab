#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STACK_VOLUME="portainer_data"
STACK_RELATIVE="compose/1/v43"
STACK_FILE="docker-compose.yml"
SECRET_DIR="/home/jd/.docker-secrets/spoolman"
SECRET_FILE="${SECRET_DIR}/spoolman_db_password"
ADMIN_SECRET_FILE="${SECRET_DIR}/spoolman_admin_password"
WORK_DIR="/home/jd/.spoolman-deploy"
FRAGMENT="${1:-/home/jd/spoolman-deploy/compose.private.fragment.yml}"
INIT_SCRIPT="$(dirname "$FRAGMENT")/init-spoolman-db.sh"
SPOOLMAN_IMAGE="ghcr.io/donkie/spoolman:0.27.0@sha256:7aba565eff774c6dda212d4204de8fa30bf68d513127ef875cc7ef3197a4664e"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

cleanup() {
  rm -f "${WORK_DIR}/stack.env" "${WORK_DIR}/docker-compose.yml" "${WORK_DIR}/candidate.yml"
}
trap cleanup EXIT

test -r "$FRAGMENT"
test -r "$INIT_SCRIPT"
chmod 755 "$INIT_SCRIPT"
mkdir -p "$SECRET_DIR" "$WORK_DIR"
chmod 700 "$SECRET_DIR" "$WORK_DIR"

for secret_file in "$SECRET_FILE" "$ADMIN_SECRET_FILE"; do
  if [[ ! -s "$secret_file" ]]; then
    secret_tmp="${secret_file}.tmp.$$"
    openssl rand -base64 48 | tr -d '\r\n' > "$secret_tmp"
    # Non-Swarm Compose implements file-backed secrets as bind mounts and
    # preserves the source mode. The enclosing 0700 directory protects host
    # access; 0644 lets the distinct unprivileged container UIDs read mounts.
    chmod 644 "$secret_tmp"
    mv -f "$secret_tmp" "$secret_file"
  fi
done
chmod 644 "$SECRET_FILE" "$ADMIN_SECRET_FILE"

# Copy the authoritative files into a private transient work area without
# printing their contents. The Compose environment file is removed on exit.
docker run --rm \
  -v "${STACK_VOLUME}:/stack:ro" \
  -v "${WORK_DIR}:/work" \
  alpine:3.22 sh -euc \
  "cp '/stack/${STACK_RELATIVE}/${STACK_FILE}' /work/docker-compose.yml; cp '/stack/${STACK_RELATIVE}/stack.env' /work/stack.env; chown '${HOST_UID}:${HOST_GID}' /work/*; chmod 600 /work/*"

existing_count="$(grep -cE '^  spoolman(-db)?:' "${WORK_DIR}/docker-compose.yml" || true)"
if [[ "$existing_count" == 2 ]]; then
  cp "${WORK_DIR}/docker-compose.yml" "${WORK_DIR}/candidate.yml"
  resume=true
elif [[ "$existing_count" == 0 ]]; then
  resume=false
  # Merge the small, reviewed fragment into the full live file. PyYAML is not
  # required; exact top-level markers are asserted before the atomic write.
  docker run --rm --entrypoint python \
    -v "${WORK_DIR}:/work" \
    -v "$(dirname "$FRAGMENT"):/fragment:ro" \
    "$SPOOLMAN_IMAGE" -c '
from pathlib import Path
base = Path("/work/docker-compose.yml").read_text()
fragment = Path("/fragment/compose.private.fragment.yml").read_text()
services, rest = fragment.split("\nnetworks:\n", 1)
networks, rest = rest.split("\nvolumes:\n", 1)
volumes, secrets = rest.split("\nsecrets:\n", 1)
assert base.count("\nnetworks:\n") == 1
assert base.count("\nvolumes:\n") == 1
service_body = services.removeprefix("services:\n")
network_body = networks
volume_body = volumes
secret_body = secrets
candidate = base.replace("\nnetworks:\n", "\n" + service_body + "\nnetworks:\n" + network_body, 1)
candidate = candidate.replace("\nvolumes:\n", "\nsecrets:\n" + secret_body + "\nvolumes:\n" + volume_body, 1)
Path("/work/candidate.yml").write_text(candidate)
'
else
  echo "Partial Spoolman service definition detected (${existing_count}/2); refusing to continue." >&2
  exit 2
fi

docker compose --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" config --quiet

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ "$resume" == false ]]; then
  docker run --rm \
    -v "${STACK_VOLUME}:/stack" \
    -v "${WORK_DIR}:/work:ro" \
    alpine:3.22 sh -euc \
    "mode=\$(stat -c %a '/stack/${STACK_RELATIVE}/${STACK_FILE}'); cp '/stack/${STACK_RELATIVE}/${STACK_FILE}' '/stack/${STACK_RELATIVE}/${STACK_FILE}.pre-spoolman.${stamp}'; cp /work/candidate.yml '/stack/${STACK_RELATIVE}/${STACK_FILE}.new'; chmod \"\$mode\" '/stack/${STACK_RELATIVE}/${STACK_FILE}.new'; mv -f '/stack/${STACK_RELATIVE}/${STACK_FILE}.new' '/stack/${STACK_RELATIVE}/${STACK_FILE}'"
fi

docker compose -p web-and-proxy \
  --env-file "${WORK_DIR}/stack.env" \
  -f "${WORK_DIR}/candidate.yml" \
  up -d --no-deps spoolman-db

db_container="$(docker compose -p web-and-proxy --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" ps -q spoolman-db)"
test -n "$db_container"
for _ in $(seq 1 36); do
  [[ "$(docker inspect "$db_container" --format '{{.State.Health.Status}}' 2>/dev/null || true)" == healthy ]] && break
  sleep 5
done
[[ "$(docker inspect "$db_container" --format '{{.State.Health.Status}}')" == healthy ]]

docker compose -p web-and-proxy \
  --env-file "${WORK_DIR}/stack.env" \
  -f "${WORK_DIR}/candidate.yml" \
  up -d --no-deps spoolman

app_container="$(docker compose -p web-and-proxy --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" ps -q spoolman)"
test -n "$app_container"
for _ in $(seq 1 48); do
  [[ "$(docker inspect "$app_container" --format '{{.State.Health.Status}}' 2>/dev/null || true)" == healthy ]] && break
  sleep 5
done
[[ "$(docker inspect "$app_container" --format '{{.State.Health.Status}}')" == healthy ]]

if [[ "$resume" == true ]]; then
  echo 'PRIVATE_SPOOLMAN_DEPLOYED resumed_existing_definition=true'
else
  echo "PRIVATE_SPOOLMAN_DEPLOYED stack_backup=${STACK_FILE}.pre-spoolman.${stamp}"
fi
