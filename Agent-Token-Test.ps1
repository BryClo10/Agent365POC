#Requires -Version 7.0
<#
47cents agent token test.
Requests one blueprint token, then two agent tokens for Policy-Digest-Agent:
Microsoft Graph and Azure Resource Manager.
Never prints, stores or returns token values or the secret.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$BlueprintAppId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$AgentIdentityAppId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{2,63}$')]
    [string]$RunId,

    [securestring]$BlueprintSecret,

    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'
$TokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$Targets = [ordered]@{
    'Agent-Token-Graph' = 'https://graph.microsoft.com/.default'
    'Agent-Token-ARM'   = 'https://management.azure.com/.default'
}

function New-ResultRow {
    param([string]$Step, [string]$Outcome)
    [ordered]@{
        RunId           = $RunId
        Step            = $Step
        RequestUtc      = ''
        Outcome         = $Outcome
        ErrorCodes      = ''
        RequestId       = ''
        ClientRequestId = ''
        Detail          = ''
    }
}

function Invoke-EntraTokenRequest {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][hashtable]$Body
    )

    $row = New-ResultRow -Step $Step -Outcome ''
    $row.ClientRequestId = [guid]::NewGuid().Guid
    $row.RequestUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $token = $null

    try {
        $responseHeaders = $null
        $response = Invoke-RestMethod -Method Post -Uri $TokenEndpoint `
            -Body $Body -ContentType 'application/x-www-form-urlencoded' `
            -Headers @{ 'client-request-id' = $row.ClientRequestId; 'return-client-request-id' = 'true' } `
            -ResponseHeadersVariable responseHeaders

        $requestIdKey = $responseHeaders.Keys | Where-Object { $_ -ieq 'x-ms-request-id' } | Select-Object -First 1
        if ($requestIdKey) {
            $row.RequestId = [string]($responseHeaders[$requestIdKey] | Select-Object -First 1)
        }

        if ([string]::IsNullOrWhiteSpace($response.access_token)) {
            $row.Outcome = 'FAILED - no access token in response'
        }
        else {
            $row.Outcome = 'TOKEN ISSUED'
            $row.Detail = "expires_in=$($response.expires_in)"
            $token = $response.access_token
        }
    }
    catch {
        $failure = $_
        $row.Outcome = 'DENIED OR FAILED'
        $message = $failure.ErrorDetails.Message
        if ($message) {
            try {
                $parsed = $message | ConvertFrom-Json
                $row.ErrorCodes = ($parsed.error_codes -join ',')
                if ($parsed.trace_id) { $row.RequestId = $parsed.trace_id }
                if ($parsed.correlation_id) { $row.ClientRequestId = $parsed.correlation_id }
                $row.Detail = (($parsed.error_description -split "`r?`n")[0])
            }
            catch {
                $row.Detail = 'Unparsed error response; inspect the matching sign-in event.'
            }
        }
        else {
            $row.Detail = $failure.Exception.Message
        }
    }

    [pscustomobject]@{ Summary = [pscustomobject]$row; Token = $token }
}

$results = [System.Collections.Generic.List[object]]::new()
$plainSecret = $null
$blueprintToken = $null

try {
    if (-not $BlueprintSecret) {
        $BlueprintSecret = Read-Host 'Blueprint client secret Value (input hidden)' -AsSecureString
    }
    $plainSecret = ConvertFrom-SecureString -SecureString $BlueprintSecret -AsPlainText

    $first = Invoke-EntraTokenRequest -Step 'Blueprint-Token' -Body @{
        client_id     = $BlueprintAppId
        client_secret = $plainSecret
        scope         = 'api://AzureADTokenExchange/.default'
        grant_type    = 'client_credentials'
        fmi_path      = $AgentIdentityAppId
    }
    $plainSecret = $null
    $results.Add($first.Summary)
    $blueprintToken = $first.Token
    $first = $null

    foreach ($step in $Targets.Keys) {
        if (-not $blueprintToken) {
            $results.Add([pscustomobject](New-ResultRow -Step $step -Outcome 'NOT RUN - blueprint token failed'))
            continue
        }

        $second = Invoke-EntraTokenRequest -Step $step -Body @{
            client_id             = $AgentIdentityAppId
            scope                 = $Targets[$step]
            grant_type            = 'client_credentials'
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $blueprintToken
        }
        $results.Add($second.Summary)
        $second = $null
    }
}
finally {
    $plainSecret = $null
    $blueprintToken = $null
    $first = $null
    $second = $null
}

$results | Format-Table Step, RequestUtc, Outcome, ErrorCodes, RequestId -AutoSize
$results | Format-List Step, ClientRequestId, Detail

if ($CsvPath) {
    $results | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "Sanitized results written to $CsvPath"
}
