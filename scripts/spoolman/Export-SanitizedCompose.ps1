[CmdletBinding()]
param(
    [switch]$FromPipeline,
    [Parameter(ValueFromPipeline)]
    [AllowEmptyString()]
    [string]$InputLine
)

begin {
    $ErrorActionPreference = 'Stop'
    $lines = [System.Collections.Generic.List[string]]::new()
}

process {
    if (-not $FromPipeline) {
        throw 'This script accepts Compose YAML only through the pipeline.'
    }
    foreach ($line in ($InputLine -split "`r?`n")) {
        $lines.Add($line)
    }
}

end {
    $sensitiveName = '(?i)(password|passwd|secret|token|api[_-]?key|private[_-]?key|credential|basicauth\.users)'

    foreach ($line in $lines) {
        $output = $line

        # Mapping-form environment values. Preserve ${NAME} references because
        # they describe wiring rather than containing a secret.
        $mappingMatch = [regex]::Match($line, '^(?<indent>\s*)(?<name>[^:#]+):\s*(?<value>.+?)\s*$')
        if ($mappingMatch.Success -and
            ($mappingMatch.Groups['name'].Value -match $sensitiveName -or
             $mappingMatch.Groups['value'].Value -match '://[^/@\s:]+:[^/@\s]+@') -and
            $mappingMatch.Groups['value'].Value -notmatch '^\$\{[A-Za-z_][A-Za-z0-9_]*(?::[-?][^}]*)?\}$' -and
            $mappingMatch.Groups['name'].Value.Trim() -ne 'file') {
            $output = '{0}{1}: REDACTED-BY-EXPORT' -f $mappingMatch.Groups['indent'].Value, $mappingMatch.Groups['name'].Value.TrimEnd()
        }

        # List-form environment values such as - PASSWORD=value.
        $listMatch = [regex]::Match($line, '^(?<prefix>\s*-\s*)(?<quote>["'']?)(?<name>[^=\s"'']+)=(?<value>.*?)(?<endquote>["'']?)\s*$')
        if ($listMatch.Success -and
            ($listMatch.Groups['name'].Value -match $sensitiveName -or
             $listMatch.Groups['value'].Value -match '://[^/@\s:]+:[^/@\s]+@') -and
            $listMatch.Groups['value'].Value -notmatch '^\$\{[A-Za-z_][A-Za-z0-9_]*(?::[-?][^}]*)?\}$') {
            $quote = $listMatch.Groups['quote'].Value
            $output = '{0}{1}{2}=REDACTED-BY-EXPORT{1}' -f $listMatch.Groups['prefix'].Value, $quote, $listMatch.Groups['name'].Value
        }

        # Authentication material can occur in Traefik label values.
        if ($line -match $sensitiveName -and $line -match '(?i)basicauth\.users=') {
            $output = $line -replace '(?i)(basicauth\.users=).*$', '$1REDACTED-BY-EXPORT'
        }

        $output
    }
}
