#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TRAEFIK_VOLUME="traefik"
WORK_DIR="/home/jd/.spoolmansync-nfc-publish"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PYTHON_IMAGE="ghcr.io/donkie/spoolman:0.27.0@sha256:7aba565eff774c6dda212d4204de8fa30bf68d513127ef875cc7ef3197a4664e"

cleanup() {
  rm -f "${WORK_DIR}/rules.yaml" "${WORK_DIR}/candidate.yaml"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"

docker run --rm \
  -v "${TRAEFIK_VOLUME}:/traefik:ro" \
  -v "${WORK_DIR}:/work" \
  alpine:3.22 sh -euc \
  "cp /traefik/rules.yaml /work/rules.yaml; chown '${HOST_UID}:${HOST_GID}' /work/rules.yaml; chmod 600 /work/rules.yaml"

docker run --rm --entrypoint python -v "${WORK_DIR}:/work" "$PYTHON_IMAGE" -c '
from pathlib import Path

source = Path("/work/rules.yaml")
target = Path("/work/candidate.yaml")
text = source.read_text()

for required in (
    "router-portainer:",
    "router-adguard:",
    "service-portainer:",
    "service-adguard:",
):
    if required not in text:
        raise SystemExit(f"Refusing to modify unexpected rules.yaml: missing {required}")

if "router-spoolmansync:" in text:
    target.write_text(text)
    raise SystemExit(0)

router = """    router-spoolmansync:
      entryPoints:
        - websecure
      rule: Host(`spools.jerrettdavis.com`)
      middlewares:
        - spoolmansync-private
      service: service-spoolmansync
      tls:
        certResolver: cloudflare
"""
middleware = """  middlewares:
    spoolmansync-private:
      ipWhiteList:
        sourceRange:
          - 10.0.0.0/24
          - 10.0.107.0/24
          - 100.64.0.0/10
"""
service = """    service-spoolmansync:
      loadBalancer:
        servers:
          - url: \"http://10.0.0.160:3000/\"
"""

services_anchor = "  services:\n"
if services_anchor not in text:
    raise SystemExit("Refusing to modify unexpected rules.yaml: missing services section")
text = text.replace(services_anchor, router + middleware + services_anchor, 1)
text = text.rstrip() + "\n" + service
target.write_text(text)
'

docker run --rm \
  --entrypoint python \
  -v "${WORK_DIR}:/work:ro" \
  "$PYTHON_IMAGE" -c '
from pathlib import Path
text = Path("/work/candidate.yaml").read_text()
for required in (
    "router-portainer:", "router-adguard:", "service-portainer:",
    "service-adguard:", "router-spoolmansync:", "service-spoolmansync:",
    "spoolmansync-private:", "certResolver: cloudflare",
    "http://10.0.0.160:3000/", "10.0.0.0/24", "10.0.107.0/24",
    "100.64.0.0/10",
):
    if required not in text:
        raise SystemExit(f"Candidate validation failed: missing {required}")
'

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
docker run --rm --user 0 \
  -v "${TRAEFIK_VOLUME}:/traefik" \
  -v "${WORK_DIR}:/work:ro" \
  alpine:3.22 sh -euc \
  "mode=\$(stat -c %a /traefik/rules.yaml); cp /traefik/rules.yaml '/traefik/rules.yaml.pre-spoolmansync-nfc.${stamp}'; cp /work/candidate.yaml /traefik/rules.yaml.new; chmod \"\$mode\" /traefik/rules.yaml.new; mv -f /traefik/rules.yaml.new /traefik/rules.yaml"

echo "SPOOLMANSYNC_NFC_ROUTER_DEPLOYED backup=rules.yaml.pre-spoolmansync-nfc.${stamp}"
