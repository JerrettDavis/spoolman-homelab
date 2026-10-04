$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\compose.private.fragment.yml'
$text = Get-Content -Raw -LiteralPath $path

$required = @(
    'ghcr.io/donkie/spoolman:0.27.0@sha256:',
    'postgres:16-alpine@sha256:',
    'SPOOLMAN_DB_PASSWORD_FILE: /run/secrets/spoolman_db_password',
    'POSTGRES_PASSWORD_FILE: /run/secrets/spoolman_admin_password',
    'file: /home/jd/.docker-secrets/spoolman/spoolman_db_password',
    'file: /home/jd/.docker-secrets/spoolman/spoolman_admin_password',
    'init-spoolman-db.sh:/docker-entrypoint-initdb.d/10-spoolman-db.sh:ro',
    'spoolman-db-data:/var/lib/postgresql/data',
    'spoolman-data:/home/app/.local/share/spoolman',
    'internal: true',
    'SPOOLMAN_ALLOWED_HOSTS: spoolman.jerrettdavis.com'
)
foreach ($value in $required) {
    if (-not $text.Contains($value)) { throw "MISSING_CONTRACT: $value" }
}
if ($text -match '(?m)^\s*ports\s*:') { throw 'HOST_PORT_IS_FORBIDDEN' }
if ($text -cmatch '(?m)^\s*SPOOLMAN_DB_PASSWORD\s*:') { throw 'PLAIN_PASSWORD_IS_FORBIDDEN' }
if ($text -match '(?i)image:\s*\S+:latest') { throw 'LATEST_IMAGE_IS_FORBIDDEN' }
'PASS_PRIVATE_COMPOSE_CONTRACT'
