$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\Export-SanitizedCompose.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw 'MISSING_SANITIZED_EXPORT_SCRIPT'
}

$sample = @'
services:
  app:
    image: example/app:1
    environment:
      SAFE_NAME: visible
      PASSWORD: literal-password
      TOKEN: ${TOKEN_FROM_ENV}
      - API_KEY=literal-key
      - "POSTGRES_PASSWORD=quoted-password"
      - TZ=America/Chicago
      DATABASE_URL: postgres://user:url-password@db:5432/app
    labels:
      - traefik.http.middlewares.demo.basicauth.users=user:hash
secrets:
  app_password:
    file: ./secrets/app_password
'@

$actual = ($sample | & $script -FromPipeline) -join "`n"

if ($actual -match 'literal-password|literal-key|quoted-password|url-password|user:hash') {
    throw 'SECRET_VALUE_WAS_NOT_REDACTED'
}
if ($actual -notmatch 'SAFE_NAME: visible') {
    throw 'NON_SECRET_MAPPING_CHANGED'
}
if ($actual -notmatch '- TZ=America/Chicago') {
    throw 'NON_SECRET_LIST_CHANGED'
}
if ($actual -notmatch 'TOKEN: \$\{TOKEN_FROM_ENV\}') {
    throw 'ENV_REFERENCE_WAS_REDACTED'
}
if ($actual -notmatch 'file: ./secrets/app_password') {
    throw 'SECRET_FILE_REFERENCE_CHANGED'
}
if ($actual -notmatch '- "POSTGRES_PASSWORD=REDACTED-BY-EXPORT"') {
    throw 'QUOTED_SECRET_LINE_BROKEN'
}

'PASS_SANITIZED_COMPOSE_EXPORT'
