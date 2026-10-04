$ErrorActionPreference = 'Stop'
$fragment = Get-Content -Raw (Join-Path $PSScriptRoot '..\compose.private.fragment.yml')
$deploy = Get-Content -Raw (Join-Path $PSScriptRoot '..\publish-home-assistant-endpoint.sh')

$required = @(
    '10.0.0.120:8444:8444',
    'spoolmanha:\n    address: :8444',
    'Host(`spoolman-ha.jerrettdavis.com`)',
    'traefik.http.routers.spoolman-ha.entrypoints: spoolmanha',
    'traefik.http.routers.spoolman-ha.middlewares: spoolman-ha-allow@docker,spoolman-ha-host@docker',
    'traefik.http.middlewares.spoolman-ha-allow.ipwhitelist.sourcerange: "10.0.107.46/32,10.0.0.160/32"',
    'traefik.http.middlewares.spoolman-ha-host.headers.customrequestheaders.Host: spoolman.jerrettdavis.com'
)
foreach ($value in $required) {
    if (-not ($fragment.Contains($value) -or $deploy.Contains($value))) {
        throw "MISSING_ENCLAVE_CONTRACT: $value"
    }
}
if (-not $deploy.Contains('text.index("\n  whoami:\n", traefik_start)')) {
    throw 'TRAEFIK_SERVICE_BOUNDARY_MUST_TARGET_NEXT_SERVICE'
}

if ($fragment -match 'spoolman-ha.*authentik') {
    throw 'MACHINE_ENDPOINT_MUST_NOT_REQUIRE_INTERACTIVE_AUTHENTIK'
}
if ($deploy -match '0\.0\.0\.0:8444|"8444:8444"') {
    throw 'ENCLAVE_LISTENER_MUST_BIND_ONLY_TO_LAN_ADDRESS'
}

'PASS_ENCLAVE_ROUTING_CONTRACT'
