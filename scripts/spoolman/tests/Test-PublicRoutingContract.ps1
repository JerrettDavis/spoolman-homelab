$ErrorActionPreference = 'Stop'
$spoolman = Get-Content -Raw (Join-Path $PSScriptRoot '..\compose.private.fragment.yml')
$publisher = Get-Content -Raw (Join-Path $PSScriptRoot '..\publish-spoolman.sh')

$requiredSpoolman = @(
    'traefik.http.routers.spoolman.rule: "Host(`spoolman.jerrettdavis.com`)"',
    'traefik.http.routers.spoolman.middlewares: spoolman-authentik@docker',
    'forwardauth.address: "http://authentik-server-1:9000/outpost.goauthentik.io/auth/traefik"',
    'traefik.http.services.spoolman.loadbalancer.server.port: "8000"'
)
foreach ($value in $requiredSpoolman) {
    if (-not ($spoolman.Contains($value) -or $publisher.Contains($value))) {
        throw "MISSING_PUBLIC_CONTRACT: $value"
    }
}
if ($spoolman -match '(?m)^\s*ports\s*:') { throw 'PUBLIC_PHASE_MUST_NOT_PUBLISH_APP_PORT' }

if (-not $publisher.Contains('docker compose -p web-and-proxy')) {
    throw 'PUBLISHER_MUST_TARGET_THE_PRODUCTION_COMPOSE_PROJECT'
}

'PASS_PUBLIC_ROUTING_CONTRACT'
