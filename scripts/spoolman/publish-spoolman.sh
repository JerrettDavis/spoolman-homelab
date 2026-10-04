#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STACK_VOLUME="portainer_data"
STACK_RELATIVE="compose/1/v43"
WORK_DIR="/home/jd/.spoolman-publish"
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
start = text.index("\n  spoolman:\n")
end = text.index("\nnetworks:\n", start)
service = text[start:end]
marker = "traefik.http.routers.spoolman.middlewares"
if marker not in service:
    labels = """    labels:
      traefik.enable: "true"
      traefik.docker.network: traefik
      traefik.http.routers.spoolman.rule: "Host(`spoolman.jerrettdavis.com`)"
      traefik.http.routers.spoolman.entrypoints: websecure
      traefik.http.routers.spoolman.tls.certresolver: cloudflare
      traefik.http.routers.spoolman.middlewares: spoolman-authentik@docker
      traefik.http.services.spoolman.loadbalancer.server.port: "8000"
      traefik.http.middlewares.spoolman-authentik.forwardauth.address: "http://authentik-server-1:9000/outpost.goauthentik.io/auth/traefik"
      traefik.http.middlewares.spoolman-authentik.forwardauth.trustForwardHeader: "true"
      traefik.http.middlewares.spoolman-authentik.forwardauth.authResponseHeaders: "X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid,X-authentik-jwt,X-authentik-meta-jwks,X-authentik-meta-outpost,X-authentik-meta-provider,X-authentik-meta-app,X-authentik-meta-version"
"""
    service = service.replace("    healthcheck:\n", labels + "    healthcheck:\n", 1)
    text = text[:start] + service + text[end:]
Path("/work/candidate.yml").write_text(text)
'

docker compose --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" config --quiet
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
docker run --rm -v "${STACK_VOLUME}:/stack" -v "${WORK_DIR}:/work:ro" alpine:3.22 sh -euc \
  "mode=\$(stat -c %a '/stack/${STACK_RELATIVE}/docker-compose.yml'); cp '/stack/${STACK_RELATIVE}/docker-compose.yml' '/stack/${STACK_RELATIVE}/docker-compose.yml.pre-spoolman-public.${stamp}'; cp /work/candidate.yml '/stack/${STACK_RELATIVE}/docker-compose.yml.new'; chmod \"\$mode\" '/stack/${STACK_RELATIVE}/docker-compose.yml.new'; mv -f '/stack/${STACK_RELATIVE}/docker-compose.yml.new' '/stack/${STACK_RELATIVE}/docker-compose.yml'"

docker compose -p web-and-proxy --env-file "${WORK_DIR}/stack.env" -f "${WORK_DIR}/candidate.yml" up -d --no-deps spoolman
echo "PUBLIC_SPOOLMAN_ROUTER_DEPLOYED backup=docker-compose.yml.pre-spoolman-public.${stamp}"
