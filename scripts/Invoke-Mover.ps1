<#
.SYNOPSIS
    Processes a mover (internal transfer) event in Microsoft Entra ID by
    updating identity attributes only, then reports the resulting access delta.

.DESCRIPTION
    A correctly designed mover process changes ATTRIBUTES, not group
    memberships. Attribute-driven dynamic groups then reconcile access
    automatically. This script never adds or removes a single group.

    The report separates dynamic from assigned groups because they behave
    differently, and that difference is the central risk in mover events:

      Dynamic groups  reconcile automatically. Access follows the person's new
                      role. This is correct behavior.

      Assigned groups do NOT reconcile. Entitlements granted by hand persist
                      through every transfer for the rest of the person's
                      tenure. This is how privilege accumulates and how
                      segregation-of-duties conflicts appear without anyone
                      granting them.

    Retained assigned groups are flagged as orphaned-entitlement risk. They are
    NOT auto-removed: the correct owner for that decision is the receiving
    manager, not a script.

.PARAMETER UserPrincipalName
    The identity being transferred.

.PARAMETER WaitSeconds
    Seconds to wait for dynamic membership reevaluation. Default 300.

.EXAMPLE
    .\Invoke-Mover.ps1 -UserPrincipalName 'grace.lindqvist@contoso.onmicrosoft.com' `
        -NewDepartment 'Clinical' -NewJobTitle 'Nurse Practitioner'
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [Parameter()][string]$NewDepartment,
    [Parameter()][string]$NewJobTitle,
    [Parameter()][string]$NewOfficeLocation,
    [Parameter()][string]$NewManagerUpn,

    [Parameter()][int]$WaitSeconds = 300,
    [Parameter()][switch]$SkipWait,

    [Parameter()][string]$OutputPath = '..\evidence'
)

$ErrorActionPreference = 'Stop'
$eventStart = Get-Date

#region Helper ---------------------------------------------------------------

function Get-MembershipSnapshot {
    param([string]$UserId)

    $raw = Get-MgUserMemberOf -UserId $UserId -All -ErrorAction SilentlyContinue

    $snapshot = foreach ($obj in $raw) {
        $name = $obj.AdditionalProperties.displayName
        if (-not $name) { continue }

        $types = $obj.AdditionalProperties.groupTypes
        $isDynamic = $types -and ($types -contains 'DynamicMembership')

        [pscustomobject]@{
            Name = $name
            Kind = if ($isDynamic) { 'Dynamic' } else { 'Assigned' }
        }
    }

    return @($snapshot | Sort-Object Name)
}

#endregion

#region Preflight ------------------------------------------------------------

Write-Host "`n=== MOVER EVENT ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph. Run Connect-MgGraph first." }

$user = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" `
        -Property 'id','displayName','userPrincipalName','department','jobTitle','officeLocation','employeeId','employeeType' `
        -ErrorAction SilentlyContinue

if (-not $user) { throw "Identity not found: $UserPrincipalName" }

$manager = $null
try { $manager = (Get-MgUserManager -UserId $user.Id -ErrorAction Stop).AdditionalProperties.displayName } catch {}

Write-Host "  Operator   : $($context.Account)"
Write-Host "  Subject    : $($user.DisplayName) ($($user.UserPrincipalName))"
Write-Host "  Event time : $($eventStart.ToString('yyyy-MM-dd HH:mm:ss'))"

Write-Host "`n--- CURRENT STATE ---" -ForegroundColor Cyan
Write-Host "  Department      : $($user.Department)"
Write-Host "  Job title       : $($user.JobTitle)"
Write-Host "  Office location : $($user.OfficeLocation)"
Write-Host "  Employee type   : $($user.EmployeeType)"
Write-Host "  Manager         : $(if ($manager) { $manager } else { '(none)' })"

$before = Get-MembershipSnapshot -UserId $user.Id

Write-Host "`n--- MEMBERSHIP BEFORE ---" -ForegroundColor Cyan
if ($before.Count -eq 0) {
    Write-Host "  (no group memberships)" -ForegroundColor DarkGray
} else {
    $before | Format-Table -AutoSize
}

#endregion

#region Apply attribute changes ----------------------------------------------

$changes = @{}
if ($NewDepartment)     { $changes['department']     = $NewDepartment }
if ($NewJobTitle)       { $changes['jobTitle']       = $NewJobTitle }
if ($NewOfficeLocation) { $changes['officeLocation'] = $NewOfficeLocation }

if ($changes.Count -eq 0 -and -not $NewManagerUpn) {
    throw "No changes specified. Supply at least one of -NewDepartment, -NewJobTitle, -NewOfficeLocation, -NewManagerUpn."
}

Write-Host "`n--- APPLYING ATTRIBUTE CHANGES ---" -ForegroundColor Cyan
Write-Host "  No group membership is modified by this script." -ForegroundColor DarkGray

foreach ($k in $changes.Keys) {
    Write-Host ("  {0,-16} : {1}  ->  {2}" -f $k, $user.$k, $changes[$k]) -ForegroundColor Yellow
}

if ($changes.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Update attributes")) {
        Update-MgUser -UserId $user.Id -BodyParameter $changes -ErrorAction Stop
        Write-Host "  Attributes updated." -ForegroundColor Green
    }
}

if ($NewManagerUpn) {
    $newMgr = Get-MgUser -Filter "userPrincipalName eq '$NewManagerUpn'" -ErrorAction SilentlyContinue
    if (-not $newMgr) { throw "New manager not found: $NewManagerUpn" }

    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Set manager to $NewManagerUpn")) {
        Set-MgUserManagerByRef -UserId $user.Id -BodyParameter @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($newMgr.Id)"
        } -ErrorAction Stop
        Write-Host ("  {0,-16} : {1}  ->  {2}" -f 'manager', $manager, $newMgr.DisplayName) -ForegroundColor Green
    }
}

#endregion

#region Wait for reconciliation ----------------------------------------------

if (-not $SkipWait -and -not $WhatIfPreference) {
    Write-Host "`n--- WAITING FOR DYNAMIC MEMBERSHIP RECONCILIATION ---" -ForegroundColor Cyan
    Write-Host "  Entra reevaluates dynamic rules asynchronously." -ForegroundColor DarkGray

    1..$WaitSeconds | ForEach-Object {
        Write-Progress -Activity 'Waiting for dynamic membership reconciliation' `
                       -Status "$_ of $WaitSeconds seconds" -PercentComplete ($_ / $WaitSeconds * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity 'Waiting for dynamic membership reconciliation' -Completed
}

#endregion

#region Delta report ---------------------------------------------------------

if ($WhatIfPreference) { Write-Host "`nWhatIf mode - no changes applied.`n" -ForegroundColor Yellow; return }

$after = Get-MembershipSnapshot -UserId $user.Id

$beforeNames = $before.Name
$afterNames  = $after.Name

$gained   = $after  | Where-Object { $_.Name -notin $beforeNames }
$lost     = $before | Where-Object { $_.Name -notin $afterNames }
$retained = $after  | Where-Object { $_.Name -in $beforeNames }

Write-Host "`n=== ACCESS DELTA ===" -ForegroundColor Cyan

Write-Host "`n  GAINED" -ForegroundColor Green
if ($gained) { $gained | ForEach-Object { Write-Host ("    + {0,-30} [{1}]" -f $_.Name, $_.Kind) -ForegroundColor Green } }
else { Write-Host "    (none)" -ForegroundColor DarkGray }

Write-Host "`n  LOST" -ForegroundColor Yellow
if ($lost) { $lost | ForEach-Object { Write-Host ("    - {0,-30} [{1}]" -f $_.Name, $_.Kind) -ForegroundColor Yellow } }
else { Write-Host "    (none)" -ForegroundColor DarkGray }

Write-Host "`n  RETAINED" -ForegroundColor Gray
if ($retained) { $retained | ForEach-Object { Write-Host ("    = {0,-30} [{1}]" -f $_.Name, $_.Kind) -ForegroundColor Gray } }
else { Write-Host "    (none)" -ForegroundColor DarkGray }

# The finding: assigned entitlements survive the transfer.
$orphaned = $retained | Where-Object { $_.Kind -eq 'Assigned' }

if ($orphaned) {
    Write-Host "`n=== ORPHANED ENTITLEMENT RISK ===" -ForegroundColor Red
    Write-Host "  The following ASSIGNED entitlements survived the role change:" -ForegroundColor Red
    $orphaned | ForEach-Object { Write-Host "    ! $($_.Name)" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Assigned groups are not governed by attributes, so they persist" -ForegroundColor DarkGray
    Write-Host "  through every transfer. Each one must be re-justified against the" -ForegroundColor DarkGray
    Write-Host "  NEW role or revoked. This is the primary mechanism by which" -ForegroundColor DarkGray
    Write-Host "  privilege accumulates and SoD conflicts appear unrequested." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Not auto-revoked by design: the receiving manager owns that decision." -ForegroundColor DarkGray
    Write-Host "  Recommended next step: run Test-SoDConflicts.ps1" -ForegroundColor Yellow
}

Write-Host "`n--- SUMMARY ---" -ForegroundColor Cyan
Write-Host "  Groups before : $($before.Count)"
Write-Host "  Groups after  : $($after.Count)"
Write-Host "  Gained        : $(@($gained).Count)"
Write-Host "  Lost          : $(@($lost).Count)"
Write-Host "  Retained      : $(@($retained).Count)"
Write-Host "  Orphaned risk : $(@($orphaned).Count)" -ForegroundColor $(if ($orphaned) { 'Red' } else { 'Green' })

#endregion

#region Evidence -------------------------------------------------------------

if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null }

$stamp = $eventStart.ToString('yyyyMMdd-HHmmss')
$json  = Join-Path $OutputPath "mover-event-$stamp.json"

[pscustomobject]@{
    eventMetadata = [pscustomobject]@{
        eventType    = 'Mover'
        operator     = $context.Account
        tenantId     = $context.TenantId
        subjectUpn   = $user.UserPrincipalName
        subjectName  = $user.DisplayName
        eventUtc     = $eventStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        waitSeconds  = $WaitSeconds
    }
    attributeChanges = $changes
    membershipBefore = $before
    membershipAfter  = $after
    delta = [pscustomobject]@{
        gained   = @($gained)
        lost     = @($lost)
        retained = @($retained)
    }
    orphanedEntitlements = @($orphaned)
} | ConvertTo-Json -Depth 6 | Out-File $json -Encoding utf8

Write-Host "`n  Evidence : $json" -ForegroundColor Green
Write-Host ""

#endregion