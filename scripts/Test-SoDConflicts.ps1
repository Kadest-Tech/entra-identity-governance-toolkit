<#
.SYNOPSIS
    Detects segregation-of-duties violations across Microsoft Entra ID group memberships.

.DESCRIPTION
    Evaluates a JSON-defined conflict matrix against live transitive group
    membership. The matrix is data, not code: compliance staff can add or retune
    rules without touching PowerShell.

    Uses TRANSITIVE membership rather than direct. Nested group membership is a
    primary way toxic access accumulates unnoticed.

    Findings are deduplicated on the normalized (alphabetically sorted) group
    pair, so overlapping matrix rules report one finding per user per condition
    while still naming every rule that matched. This makes policy redundancy
    visible instead of inflating counts.

.PARAMETER MatrixPath
    Path to the SoD conflict matrix JSON.

.PARAMETER OutputPath
    Directory for CSV and JSON evidence output.

.PARAMETER Format
    Console, Csv, Json, or All.

.OUTPUTS
    Exit code 0 = no violations. Exit code 1 = violations found.

.EXAMPLE
    .\Test-SoDConflicts.ps1

.EXAMPLE
    .\Test-SoDConflicts.ps1 -Format All -OutputPath ..\evidence
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$MatrixPath = '..\policy\sod-matrix.json',

    [Parameter()]
    [string]$OutputPath = '..\evidence',

    [Parameter()]
    [ValidateSet('Console','Csv','Json','All')]
    [string]$Format = 'Console'
)

$ErrorActionPreference = 'Stop'
$scanStart = Get-Date

#region Preflight ------------------------------------------------------------

Write-Host "`n=== SEGREGATION OF DUTIES SCAN ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph. Run Connect-MgGraph first." }

if (-not (Test-Path $MatrixPath)) { throw "Conflict matrix not found at: $MatrixPath" }

$matrix = Get-Content $MatrixPath -Raw | ConvertFrom-Json

Write-Host "  Tenant       : $($context.TenantId)"
Write-Host "  Operator     : $($context.Account)"
Write-Host "  Policy       : $($matrix.policyName)"
Write-Host "  Version      : $($matrix.version)"
Write-Host "  Rules        : $($matrix.conflicts.Count)"
Write-Host "  Scan started : $($scanStart.ToString('yyyy-MM-dd HH:mm:ss'))"

#endregion

#region Build membership map -------------------------------------------------

Write-Host "`n--- Building membership map ---" -ForegroundColor Cyan

$users = Get-MgUser -All -Property 'id','displayName','userPrincipalName','department','jobTitle','employeeId'
Write-Host "  Users in scope: $($users.Count)"

$membership = @{}
$i = 0

foreach ($u in $users) {
    $i++
    Write-Progress -Activity 'Resolving transitive group membership' `
                   -Status "$i of $($users.Count) - $($u.DisplayName)" `
                   -PercentComplete ($i / $users.Count * 100)

    try {
        $groups = Get-MgUserTransitiveMemberOf -UserId $u.Id -All -ErrorAction Stop |
                  ForEach-Object { $_.AdditionalProperties.displayName } |
                  Where-Object { $_ }

        $membership[$u.Id] = [pscustomobject]@{
            User   = $u
            Groups = @($groups)
        }
    }
    catch {
        Write-Warning "  Could not resolve membership for $($u.DisplayName): $($_.Exception.Message)"
        $membership[$u.Id] = [pscustomobject]@{ User = $u; Groups = @() }
    }
}

Write-Progress -Activity 'Resolving transitive group membership' -Completed
Write-Host "  Membership resolved for $($membership.Count) identities" -ForegroundColor Green

#endregion

#region Evaluate matrix ------------------------------------------------------

Write-Host "`n--- Evaluating conflict matrix ---" -ForegroundColor Cyan

# Keyed by "userId|normalizedGroupPair" so overlapping rules collapse to one
# finding while still recording every rule that matched.
$findings = @{}

foreach ($rule in $matrix.conflicts) {

    $hits = 0

    foreach ($entry in $membership.Values) {

        $hasA = $entry.Groups -contains $rule.groupA
        $hasB = $entry.Groups -contains $rule.groupB

        if (-not ($hasA -and $hasB)) { continue }

        $hits++

        $pairKey = (@($rule.groupA, $rule.groupB) | Sort-Object) -join '::'
        $findingKey = "$($entry.User.Id)|$pairKey"

        if ($findings.ContainsKey($findingKey)) {
            # Same user, same group pair, different rule. Record the overlap.
            $existing = $findings[$findingKey]
            $existing.MatchedRules += $rule.id
            if ($existing.Severity -ne 'Critical' -and $rule.severity -eq 'Critical') {
                $existing.Severity = 'Critical'
            }
            continue
        }

        $findings[$findingKey] = [pscustomobject]@{
            FindingId      = ''
            MatchedRules   = @($rule.id)
            RuleName       = $rule.name
            Severity       = $rule.severity
            User           = $entry.User.DisplayName
            Upn            = $entry.User.UserPrincipalName
            EmployeeId     = $entry.User.EmployeeId
            Department     = $entry.User.Department
            JobTitle       = $entry.User.JobTitle
            ConflictGroupA = $rule.groupA
            ConflictGroupB = $rule.groupB
            RiskStatement  = $rule.riskStatement
            ControlMapping = ($rule.controlMapping -join '; ')
            Remediation    = $rule.remediation
            DetectedUtc    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    }

    $color = if ($hits -gt 0) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0,-9} {1,-10} {2,-45} matches: {3}" -f $rule.id, $rule.severity, $rule.name, $hits) -ForegroundColor $color
}

# Stable, severity-ordered finding IDs
$severityRank = @{ 'Critical' = 1; 'High' = 2; 'Medium' = 3; 'Low' = 4 }
$results = $findings.Values |
    Sort-Object @{e={$severityRank[$_.Severity]}}, User

$n = 0
foreach ($f in $results) {
    $n++
    $f.FindingId    = 'SOD-F{0:D3}' -f $n
    $f.MatchedRules = ($f.MatchedRules | Sort-Object -Unique) -join ', '
}

#endregion

#region Report ---------------------------------------------------------------

$scanEnd  = Get-Date
$duration = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 1)

Write-Host "`n=== FINDINGS ===" -ForegroundColor Cyan

if ($results.Count -eq 0) {
    Write-Host "  No segregation-of-duties violations detected.`n" -ForegroundColor Green
}
else {
    foreach ($f in $results) {
        $sevColor = switch ($f.Severity) {
            'Critical' { 'Red' }
            'High'     { 'Yellow' }
            default    { 'Gray' }
        }

        Write-Host "`n  [$($f.FindingId)] $($f.Severity.ToUpper())" -ForegroundColor $sevColor
        Write-Host "    User        : $($f.User) ($($f.JobTitle), $($f.Department))"
        Write-Host "    Conflict    : $($f.ConflictGroupA)  +  $($f.ConflictGroupB)"
        Write-Host "    Rule(s)     : $($f.MatchedRules) - $($f.RuleName)"
        Write-Host "    Controls    : $($f.ControlMapping)" -ForegroundColor DarkGray
        Write-Host "    Remediation : $($f.Remediation)" -ForegroundColor DarkGray
    }

    Write-Host "`n--- SUMMARY BY SEVERITY ---" -ForegroundColor Cyan
    $results | Group-Object Severity |
        Sort-Object @{e={$severityRank[$_.Name]}} |
        Select-Object @{n='Severity';e={$_.Name}}, @{n='Findings';e={$_.Count}} |
        Format-Table -AutoSize
}

Write-Host "  Identities scanned : $($membership.Count)"
Write-Host "  Rules evaluated    : $($matrix.conflicts.Count)"
Write-Host "  Findings           : $($results.Count)"
Write-Host "  Duration           : $duration seconds"

#endregion

#region Evidence export ------------------------------------------------------

if ($Format -in @('Csv','Json','All')) {

    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $stamp = $scanStart.ToString('yyyyMMdd-HHmmss')

    if ($Format -in @('Csv','All')) {
        $csv = Join-Path $OutputPath "sod-findings-$stamp.csv"
        $results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
        Write-Host "`n  CSV evidence  : $csv" -ForegroundColor Green
    }

    if ($Format -in @('Json','All')) {
        $json = Join-Path $OutputPath "sod-findings-$stamp.json"
        [pscustomobject]@{
            scanMetadata = [pscustomobject]@{
                tenantId         = $context.TenantId
                operator         = $context.Account
                policyName       = $matrix.policyName
                policyVersion    = $matrix.version
                scanStartedUtc   = $scanStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                scanCompletedUtc = $scanEnd.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                durationSeconds  = $duration
                identitiesScanned= $membership.Count
                rulesEvaluated   = $matrix.conflicts.Count
                findingCount     = $results.Count
            }
            findings = $results
        } | ConvertTo-Json -Depth 6 | Out-File $json -Encoding utf8
        Write-Host "  JSON evidence : $json" -ForegroundColor Green
    }
}

Write-Host ""

#endregion

if ($results.Count -gt 0) { exit 1 } else { exit 0 }