#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STACK_VOLUME="portainer_data"
STACK_RELATIVE="compose/1/v43"
WORK_DIR="/home/jd/.spoolman-ha-publish"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
SPOOLMAN_IMAGE="ghcr.io/donkie/spoolman:0.27.0@sha256:7aba565eff774c6dda212d4204de8fa30bf68d513127ef875cc7ef3197a4664e"

cleanup() {
  rm -f "${WORK_DIR}/stack.env" "${WORK_DIR}/docker-compose.yml" "${WORK_DIR}/candidate.yml"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"
docker run --rm -v "${STACK_VOLUME}:/stack:ro" -v "${WORK_DIR}:/work" alpine:3.22 sh -euc \
  "cp '/stack/${STACK_RELATIVE}/docker-compose.yml' /work/docker-compose.yml; cp '/stack/${STACK_RELATIVE}/stack.env' /work/stack.env; chown '${HOST_UID}:${HOST_GID}' /work/*; chmod 600 /work/*"

docker run --rm --entrypoint python -v "${WORK_DIR}:/work" "$SPOOLMAN_IMAGE" -c '
from pathlib import Path
p = Path("/work/docker-compose.yml")
text = p.read_text()

traefik_start = text.index("\n  traefik:\n")
traefik_end = text.index("\n  whoami:\n", traefik_start)
traefik = text[traefik_start:traefik_end]
traefik = traefik.replace("    command:\n      - --entrypoints.spoolman-ha.address=:8444\n", "")
traefik = traefik.replace("    command:\n      - --entrypoints.spoolmanha.address=:8444\n", "")
if "10.0.0.120:8444:8444" not in traefik:
    traefik = traefik.replace("    ports:\n", "    ports:\n      - \"10.0.0.120:8444:8444\"\n", 1)
text = text[:traefik_start] + traefik + text[traefik_end:]

spool_start = text.index("\n  spoolman:\n")
spool_end = text.index("\nnetworks:\n", spool_start)
spool = text[spool_start:spool_end]
spool = spool.replace("traefik.http.routers.spoolman-ha.entrypoints: spoolman-ha", "traefik.http.routers.spoolman-ha.entrypoints: spoolmanha")
if "traefik.http.routers.spoolman-ha.rule" not in spool:
    labels = """      traefik.http.routers.spoolman-ha.rule: "Host(`spoolman-ha.jerrettdavis.com`)"
      traefik.http.routers.spoolman-ha.entrypoints: spoolmanha
      traefik.http.routers.spoolman-ha.tls.certresolver: cloudflare
      traefik.http.routers.spoolman-ha.middlewares: spoolman-ha-allow@docker,spoolman-ha-host@docker
      traefik.http.routers.spoolman-ha.service: spoolman
      traefik.http.middlewares.spoolman-ha-allow.ipwhitelist.sourcerange: "10.0.107.46/32,10.0.0.160/32"
      traefik.http.middlewares.spoolman-ha-host.headers.customrequestheaders.Host: spoolman.jerrettdavis.com
"""
    anchor = "      traefik.http.middlewares.spoolman-authentik.forwardauth.authResponseHeaders:"
    pos = spool.index(anchor)
    end = spool.index("\n", pos) + 1
    spool = spool[:end] + labels + spool[end:]
text = text[:spool_start] + spool + text[spool_end:]
Path("/work/candidate.yml").write_text(text)
'

docker compose --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" config --quiet
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
docker run --rm --user 0 -v traefik:/traefik --entrypoint python "$SPOOLMAN_IMAGE" -c '
from pathlib import Path
p = Path("/traefik/traefik.yaml")
text = p.read_text()
if "\n  spoolmanha:\n" not in text:
    backup = p.with_name("traefik.yaml.pre-spoolman-ha")
    if not backup.exists():
        backup.write_text(text)
    anchor = "\nproviders:\n"
    stanza = "\n  spoolmanha:\n    address: :8444\n"
    text = text.replace(anchor, stanza + anchor, 1)
    p.write_text(text)
'
docker run --rm -v "${STACK_VOLUME}:/stack" -v "${WORK_DIR}:/work:ro" alpine:3.22 sh -euc \
  "mode=\$(stat -c %a '/stack/${STACK_RELATIVE}/docker-compose.yml'); cp '/stack/${STACK_RELATIVE}/docker-compose.yml' '/stack/${STACK_RELATIVE}/docker-compose.yml.pre-spoolman-ha.${stamp}'; cp /work/candidate.yml '/stack/${STACK_RELATIVE}/docker-compose.yml.new'; chmod \"\$mode\" '/stack/${STACK_RELATIVE}/docker-compose.yml.new'; mv -f '/stack/${STACK_RELATIVE}/docker-compose.yml.new' '/stack/${STACK_RELATIVE}/docker-compose.yml'"

docker compose -p web-and-proxy --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" up -d --no-deps traefik spoolman
echo "SPOOLMAN_HA_ROUTER_DEPLOYED backup=docker-compose.yml.pre-spoolman-ha.${stamp}"
