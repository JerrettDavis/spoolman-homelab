[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hostname = 'spools.jerrettdavis.com'
$expectedAddress = '10.0.0.120'

$internalAddresses = @(
    Resolve-DnsName $hostname -Type A -DnsOnly |
        Where-Object IPAddress |
        ForEach-Object IPAddress
)
if ($internalAddresses.Count -ne 1 -or $internalAddresses[0] -ne $expectedAddress) {
    throw "INTERNAL_DNS_MISMATCH: expected $expectedAddress; got $($internalAddresses -join ',')"
}

$dohUri = "https://cloudflare-dns.com/dns-query?name=$hostname&type=A"
$publicDns = Invoke-RestMethod -Uri $dohUri -Headers @{ Accept = 'application/dns-json' }
if ($publicDns.Status -ne 3) {
    $answers = @($publicDns.Answer | ForEach-Object data) -join ','
    throw "PUBLIC_DNS_MUST_BE_NXDOMAIN: status=$($publicDns.Status) answers=$answers"
}

function Test-HttpsEndpoint {
    param([Parameter(Mandatory)][string]$Uri)

    $result = & curl.exe -sS -o NUL -w '%{http_code}|%{ssl_verify_result}|%{remote_ip}' `
        --connect-timeout 5 --max-time 10 $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "HTTPS_REQUEST_FAILED: $Uri curl_exit=$LASTEXITCODE"
    }
    $code, $tlsVerify, $remoteAddress = $result -split '\|', 3
    if ($code -ne '200') {
        throw "HTTPS_STATUS_MISMATCH: $Uri returned $code"
    }
    if ($tlsVerify -ne '0') {
        throw "TLS_VERIFICATION_FAILED: $Uri verify_result=$tlsVerify"
    }
    if ($remoteAddress -ne $expectedAddress) {
        throw "HTTPS_REMOTE_MISMATCH: $Uri expected=$expectedAddress actual=$remoteAddress"
    }
}

Test-HttpsEndpoint 'https://spools.jerrettdavis.com/'
Test-HttpsEndpoint 'https://spools.jerrettdavis.com/scan'

"PASS_SPOOLMANSYNC_NFC_ENDPOINT host=$hostname address=$expectedAddress public_dns=NXDOMAIN tls=verified"
