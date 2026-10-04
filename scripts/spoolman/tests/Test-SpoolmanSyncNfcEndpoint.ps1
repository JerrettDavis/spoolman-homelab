$ErrorActionPreference = 'Stop'

$deploy = Get-Content -Raw (Join-Path $PSScriptRoot '..\publish-spoolmansync-nfc-endpoint.sh')

$required = @(
    'spools.jerrettdavis.com',
    'http://10.0.0.160:3000/',
    'certResolver: cloudflare',
    'spoolmansync-private',
    '10.0.0.0/24',
    '10.0.107.0/24',
    '100.64.0.0/10',
    'rules.yaml.pre-spoolmansync-nfc',
    'router-portainer:',
    'router-adguard:',
    'service-portainer:',
    'service-adguard:'
)

foreach ($value in $required) {
    if (-not $deploy.Contains($value)) {
        throw "MISSING_SPOOLMANSYNC_NFC_CONTRACT: $value"
    }
}

if ($deploy -match '0\.0\.0\.0:3000|3000:3000') {
    throw 'SPOOLMANSYNC_MUST_NOT_BE_REPUBLISHED_BY_DOCKER'
}

if ($deploy -notmatch 'if "router-spoolmansync:" in text:') {
    throw 'DEPLOYMENT_MUST_BE_IDEMPOTENT'
}

$pythonEntrypoints = ([regex]::Matches($deploy, '--entrypoint python')).Count
if ($pythonEntrypoints -ne 2) {
    throw "ALL_PYTHON_HELPERS_MUST_OVERRIDE_IMAGE_ENTRYPOINT: found $pythonEntrypoints"
}

if ($deploy.Contains('chmod --reference')) {
    throw 'BUSYBOX_CHMOD_DOES_NOT_SUPPORT_REFERENCE'
}
if (-not $deploy.Contains('mode=\$(stat -c %a /traefik/rules.yaml)')) {
    throw 'DEPLOYMENT_MUST_PRESERVE_RULES_FILE_MODE_PORTABLY'
}

'PASS_SPOOLMANSYNC_NFC_ENDPOINT_CONTRACT'
