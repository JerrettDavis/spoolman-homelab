#!/bin/sh
set -eu

STACK_DIR=/stack/compose/1/v43
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
BACKUP_FILE="$COMPOSE_FILE.pre-spoolman-ha-host-20261003"

docker run --rm -v portainer_data:/stack alpine:3.22 sh -c '
  set -eu
  file=/stack/compose/1/v43/docker-compose.yml
  backup="$file.pre-spoolman-ha-host-20261003"
  cp "$file" "$backup"
  if ! grep -q "SPOOLMAN_ALLOWED_HOSTS: spoolman.jerrettdavis.com,spoolman-ha.jerrettdavis.com" "$file"; then
    sed -i "s/SPOOLMAN_ALLOWED_HOSTS: spoolman.jerrettdavis.com/SPOOLMAN_ALLOWED_HOSTS: spoolman.jerrettdavis.com,spoolman-ha.jerrettdavis.com/" "$file"
  fi
  grep -n SPOOLMAN_ALLOWED_HOSTS "$file"
'

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/stack \
  -w "$STACK_DIR" \
  docker:cli compose -p web-and-proxy --env-file stack.env up -d --no-deps spoolman

docker inspect web-and-proxy-spoolman-1 \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep '^SPOOLMAN_ALLOWED_HOSTS='
