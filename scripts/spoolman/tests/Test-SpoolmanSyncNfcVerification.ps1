$ErrorActionPreference = 'Stop'

$verify = Get-Content -Raw (Join-Path $PSScriptRoot '..\Verify-SpoolmanSyncNfcEndpoint.ps1')

$required = @(
    'spools.jerrettdavis.com',
    '10.0.0.120',
    'Resolve-DnsName',
    'https://cloudflare-dns.com/dns-query',
    'PUBLIC_DNS_MUST_BE_NXDOMAIN',
    'https://spools.jerrettdavis.com/',
    'https://spools.jerrettdavis.com/scan',
    'PASS_SPOOLMANSYNC_NFC_ENDPOINT'
)

foreach ($value in $required) {
    if (-not $verify.Contains($value)) {
        throw "MISSING_NFC_VERIFICATION_CONTRACT: $value"
    }
}

if ($verify -match '(?i)--insecure|\s-k(?:\s|$)') {
    throw 'TLS_VERIFICATION_MUST_NOT_BE_DISABLED'
}

'PASS_SPOOLMANSYNC_NFC_VERIFICATION_CONTRACT'
