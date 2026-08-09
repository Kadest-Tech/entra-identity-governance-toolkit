<#
.SYNOPSIS
    Processes a leaver (termination) event in Microsoft Entra ID.

.DESCRIPTION
    Executes the containment sequence in the correct order:

      1. Disable the account          - stops new authentication
      2. Revoke all refresh tokens    - kills EXISTING sessions
      3. Remove assigned entitlements - dynamic groups drop only if their rule tests accountEnabled
      4. Clear manager                - removes from manager's review scope
      5. Capture evidence             - proof of deprovisioning for audit

    Step 2 is the one most termination runbooks omit. Disabling an account does
    NOT terminate active sessions: an issued refresh token remains valid until
    it expires, which can leave a terminated user authenticated for hours.
    Revoke-MgUserSignInSession invalidates them immediately.

    Attributes are preserved rather than wiped. Audit investigations need to
    know what the person's role WAS at termination.

.EXAMPLE
    .\Invoke-Leaver.ps1 -UserPrincipalName 'terrence.wu@contoso.onmicrosoft.com' -Reason 'Contract ended'
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$UserPrincipalName,
    [Parameter()][string]$Reason = 'Not specified',
    [Parameter()][string]$OutputPath = '..\evidence'
)

$ErrorActionPreference = 'Stop'
$eventStart = Get-Date

Write-Host "`n=== LEAVER EVENT ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph. Run Connect-MgGraph first." }

$user = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" `
        -Property 'id','displayName','userPrincipalName','accountEnabled','department','jobTitle','employeeId','employeeType' `
        -ErrorAction SilentlyContinue
if (-not $user) { throw "Identity not found: $UserPrincipalName" }

Write-Host "  Operator : $($context.Account)"
Write-Host "  Subject  : $($user.DisplayName) ($($user.UserPrincipalName))"
Write-Host "  Role     : $($user.JobTitle), $($user.Department)"
Write-Host "  Reason   : $Reason"
Write-Host "  Event    : $($eventStart.ToString('yyyy-MM-dd HH:mm:ss'))"

# Snapshot BEFORE any change - this is the audit record.
$raw = Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction SilentlyContinue
$before = foreach ($o in $raw) {
    $n = $o.AdditionalProperties.displayName
    if (-not $n) { continue }
    $t = $o.AdditionalProperties.groupTypes
    [pscustomobject]@{
        Name = $n
        Kind = if ($t -and ($t -contains 'DynamicMembership')) { 'Dynamic' } else { 'Assigned' }
        Id   = $o.Id
    }
}
$before = @($before | Sort-Object Name)

Write-Host "`n--- ACCESS AT TERMINATION ---" -ForegroundColor Cyan
if ($before.Count) { $before | Select-Object Name, Kind | Format-Table -AutoSize }
else { Write-Host "  (no group memberships)" -ForegroundColor DarkGray }

$actions = @()

# --- 1. Disable ---
Write-Host "--- 1. DISABLE ACCOUNT ---" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Disable account')) {
    Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
    Write-Host "  Account disabled." -ForegroundColor Green
    $actions += 'AccountDisabled'
}

# --- 2. Revoke sessions ---
Write-Host "`n--- 2. REVOKE ACTIVE SESSIONS ---" -ForegroundColor Cyan
Write-Host "  Disabling alone does not end issued sessions." -ForegroundColor DarkGray
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Revoke all refresh tokens')) {
    try {
        Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop | Out-Null
        Write-Host "  All refresh tokens revoked." -ForegroundColor Green
        $actions += 'SessionsRevoked'
    }
    catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $actions += 'SessionRevocationFailed'
    }
}

# --- 3. Remove assigned entitlements ---
Write-Host "`n--- 3. REMOVE ASSIGNED ENTITLEMENTS ---" -ForegroundColor Cyan
Write-Host "  Dynamic groups drop only if their rule tests accountEnabled once the account is disabled." -ForegroundColor DarkGray

$assigned = $before | Where-Object { $_.Kind -eq 'Assigned' }
$removed  = @()

if (-not $assigned) { Write-Host "  No assigned entitlements to remove." -ForegroundColor DarkGray }
foreach ($g in $assigned) {
    if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, "Remove from $($g.Name)")) { continue }
    try {
        Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $user.Id -ErrorAction Stop
        Write-Host "  Removed: $($g.Name)" -ForegroundColor Green
        $removed += $g.Name
    }
    catch {
        Write-Host "  FAILED to remove $($g.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}
if ($removed) { $actions += 'AssignedEntitlementsRemoved' }

# --- 4. Clear manager ---
Write-Host "`n--- 4. CLEAR MANAGER REFERENCE ---" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Remove manager')) {
    try {
        Remove-MgUserManagerByRef -UserId $user.Id -ErrorAction Stop
        Write-Host "  Manager cleared - removed from manager review scope." -ForegroundColor Green
        $actions += 'ManagerCleared'
    }
    catch { Write-Host "  No manager assigned, or already cleared." -ForegroundColor DarkGray }
}

if ($WhatIfPreference) { Write-Host "`nWhatIf mode - no changes applied.`n" -ForegroundColor Yellow; return }

# --- 5. Verify ---
Start-Sleep -Seconds 5
$post = Get-MgUser -UserId $user.Id -Property 'accountEnabled'
$rawAfter = Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction SilentlyContinue
$after = @($rawAfter | ForEach-Object { $_.AdditionalProperties.displayName } | Where-Object { $_ })

Write-Host "`n=== POST-TERMINATION STATE ===" -ForegroundColor Cyan
Write-Host "  Account enabled   : $($post.AccountEnabled)" -ForegroundColor $(if ($post.AccountEnabled) { 'Red' } else { 'Green' })
Write-Host "  Groups before     : $($before.Count)"
Write-Host "  Groups remaining  : $($after.Count)"
if ($after.Count) {
    Write-Host "  Residual membership (dynamic groups may lag reevaluation):" -ForegroundColor Yellow
    $after | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
}
Write-Host "  Actions completed : $($actions -join ', ')"

# --- Evidence ---
if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null }
$stamp = $eventStart.ToString('yyyyMMdd-HHmmss')
$json  = Join-Path $OutputPath "leaver-event-$stamp.json"

[pscustomobject]@{
    eventMetadata = [pscustomobject]@{
        eventType   = 'Leaver'
        operator    = $context.Account
        tenantId    = $context.TenantId
        subjectUpn  = $user.UserPrincipalName
        subjectName = $user.DisplayName
        roleAtExit  = "$($user.JobTitle), $($user.Department)"
        employeeId  = $user.EmployeeId
        reason      = $Reason
        eventUtc    = $eventStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    accessAtTermination     = $before
    actionsCompleted        = $actions
    entitlementsRemoved     = $removed
    residualMembership      = $after
    accountEnabledAfter     = $post.AccountEnabled
} | ConvertTo-Json -Depth 6 | Out-File $json -Encoding utf8

Write-Host "`n  Evidence : $json" -ForegroundColor Green
Write-Host ""