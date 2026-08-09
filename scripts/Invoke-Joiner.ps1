<#
.SYNOPSIS
    Provisions a new identity in Microsoft Entra ID via attribute-driven access.

.DESCRIPTION
    A correct joiner process sets ATTRIBUTES and lets dynamic membership rules
    grant access. This script assigns no groups directly.

    Consequence, and the point of the demonstration: a new hire receives
    baseline role-appropriate access automatically, and NO entitlement-group
    access. Every sensitive capability (charge entry, coding, PHI) must be
    requested explicitly through an access package with approval and expiry.

    That is least privilege by construction rather than by policy: there is no
    step in this process where over-provisioning is possible, because the
    process cannot grant an entitlement at all.

    Contrast with Invoke-Mover.ps1, where assigned entitlements survive a role
    change because attributes do not govern them.

.PARAMETER UsageLocation
    ISO 3166-2 country code. REQUIRED before any license can be assigned.
    Omitting it is the most common cause of failed license provisioning.

.EXAMPLE
    .\Invoke-Joiner.ps1 -FirstName 'Renee' -LastName 'Okafor' `
        -Department 'Revenue Cycle' -JobTitle 'Claims Submission Specialist' `
        -OfficeLocation 'Atlanta' -EmployeeType 'Employee' -EmployeeId 'E3008' `
        -ManagerUpn 'latoya.simms@contoso.onmicrosoft.com' `
        -TenantDomain 'contoso.onmicrosoft.com'
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$FirstName,
    [Parameter(Mandatory)][string]$LastName,
    [Parameter(Mandatory)][string]$Department,
    [Parameter(Mandatory)][string]$JobTitle,
    [Parameter(Mandatory)][string]$TenantDomain,

    [Parameter()][string]$OfficeLocation = 'Atlanta',
    [Parameter()][ValidateSet('Employee','Contractor','Intern')][string]$EmployeeType = 'Employee',
    [Parameter()][string]$EmployeeId,
    [Parameter()][string]$ManagerUpn,
    [Parameter()][string]$CompanyName = 'Northlake Regional Health',
    [Parameter()][string]$UsageLocation = 'US',
    [Parameter()][int]$WaitSeconds = 300,
    [Parameter()][switch]$SkipWait,
    [Parameter()][string]$OutputPath = '..\evidence'
)

$ErrorActionPreference = 'Stop'
$eventStart = Get-Date

function New-CompliantPassword {
    param([int]$Length = 24)
    $u='ABCDEFGHJKLMNPQRSTUVWXYZ'; $l='abcdefghijkmnopqrstuvwxyz'
    $d='23456789'; $s='!@#$%^&*-_=+'; $all=$u+$l+$d+$s
    $c = @($u[(Get-Random -Max $u.Length)], $l[(Get-Random -Max $l.Length)],
           $d[(Get-Random -Max $d.Length)], $s[(Get-Random -Max $s.Length)])
    $c += 1..($Length-4) | ForEach-Object { $all[(Get-Random -Max $all.Length)] }
    -join ($c | Sort-Object { Get-Random })
}

#region Preflight ------------------------------------------------------------

Write-Host "`n=== JOINER EVENT ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph. Run Connect-MgGraph first." }

$alias = "$FirstName.$LastName".ToLower()
$upn   = "$alias@$TenantDomain"
$name  = "$FirstName $LastName"

if (Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue) {
    throw "Identity already exists: $upn"
}

$manager = $null
if ($ManagerUpn) {
    $manager = Get-MgUser -Filter "userPrincipalName eq '$ManagerUpn'" -ErrorAction SilentlyContinue
    if (-not $manager) { throw "Manager not found: $ManagerUpn" }
}

Write-Host "  Operator   : $($context.Account)"
Write-Host "  New hire   : $name ($upn)"
Write-Host "  Event time : $($eventStart.ToString('yyyy-MM-dd HH:mm:ss'))"

Write-Host "`n--- IDENTITY ATTRIBUTES ---" -ForegroundColor Cyan
Write-Host "  Department      : $Department"
Write-Host "  Job title       : $JobTitle"
Write-Host "  Office location : $OfficeLocation"
Write-Host "  Employee type   : $EmployeeType"
Write-Host "  Employee ID     : $EmployeeId"
Write-Host "  Usage location  : $UsageLocation"
Write-Host "  Manager         : $(if ($manager) { $manager.DisplayName } else { '(none)' })"

#endregion

#region Provision ------------------------------------------------------------

Write-Host "`n--- 1. CREATE IDENTITY ---" -ForegroundColor Cyan
Write-Host "  No group is assigned by this script. Access derives from attributes." -ForegroundColor DarkGray

if (-not $PSCmdlet.ShouldProcess($upn, 'Create identity')) { return }

$user = New-MgUser -ErrorAction Stop -BodyParameter @{
    accountEnabled    = $true
    displayName       = $name
    givenName         = $FirstName
    surname           = $LastName
    userPrincipalName = $upn
    mailNickname      = $alias -replace '\.', ''
    jobTitle          = $JobTitle
    department        = $Department
    officeLocation    = $OfficeLocation
    employeeId        = $EmployeeId
    employeeType      = $EmployeeType
    companyName       = $CompanyName
    usageLocation     = $UsageLocation
    passwordProfile   = @{
        password                      = New-CompliantPassword
        forceChangePasswordNextSignIn = $true
    }
}
Write-Host "  Identity created. Object ID: $($user.Id)" -ForegroundColor Green

# employeeType is NOT queryable in dynamic membership rules. Mirror it into
# extensionAttribute1, which is. See docs/dynamic-groups.md.
Write-Host "`n--- 2. MIRROR employeeType -> extensionAttribute1 ---" -ForegroundColor Cyan
Update-MgUser -UserId $user.Id -ErrorAction Stop -BodyParameter @{
    onPremisesExtensionAttributes = @{ extensionAttribute1 = $EmployeeType }
}
Write-Host "  extensionAttribute1 = $EmployeeType" -ForegroundColor Green

Write-Host "`n--- 3. LINK MANAGER ---" -ForegroundColor Cyan
if ($manager) {
    Start-Sleep -Seconds 5
    Set-MgUserManagerByRef -UserId $user.Id -ErrorAction Stop -BodyParameter @{
        '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)"
    }
    Write-Host "  Manager set: $($manager.DisplayName)" -ForegroundColor Green
    Write-Host "  Identity is now in scope for manager-attested access reviews." -ForegroundColor DarkGray
} else {
    Write-Host "  No manager supplied." -ForegroundColor Yellow
    Write-Host "  WARNING: manager-attested reviews will skip this identity." -ForegroundColor Yellow
}

#endregion

#region Wait -----------------------------------------------------------------

if (-not $SkipWait) {
    Write-Host "`n--- 4. WAITING FOR DYNAMIC MEMBERSHIP EVALUATION ---" -ForegroundColor Cyan
    1..$WaitSeconds | ForEach-Object {
        Write-Progress -Activity 'Waiting for dynamic membership evaluation' `
                       -Status "$_ of $WaitSeconds seconds" -PercentComplete ($_ / $WaitSeconds * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity 'Waiting for dynamic membership evaluation' -Completed
}

#endregion

#region Report ---------------------------------------------------------------

$raw = Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction SilentlyContinue
$granted = foreach ($o in $raw) {
    $n = $o.AdditionalProperties.displayName
    if (-not $n) { continue }
    $t = $o.AdditionalProperties.groupTypes
    [pscustomobject]@{
        Group = $n
        Kind  = if ($t -and ($t -contains 'DynamicMembership')) { 'Dynamic' } else { 'Assigned' }
    }
}
$granted = @($granted | Sort-Object Group)

Write-Host "`n=== ACCESS GRANTED ===" -ForegroundColor Cyan
if ($granted.Count) { $granted | Format-Table -AutoSize }
else { Write-Host "  (none yet - dynamic evaluation may still be pending)`n" -ForegroundColor Yellow }

$ent = $granted | Where-Object { $_.Group -like 'ENT-*' }

Write-Host "--- LEAST PRIVILEGE VERIFICATION ---" -ForegroundColor Cyan
if ($ent.Count -eq 0) {
    Write-Host "  PASS: no entitlement-group access granted at provisioning." -ForegroundColor Green
    Write-Host "  Sensitive capabilities require an explicit access package request" -ForegroundColor DarkGray
    Write-Host "  with manager approval and mandatory expiry." -ForegroundColor DarkGray
} else {
    Write-Host "  FAIL: entitlement access granted at provisioning:" -ForegroundColor Red
    $ent | ForEach-Object { Write-Host "    ! $($_.Group)" -ForegroundColor Red }
    Write-Host "  A joiner process should never grant entitlements directly." -ForegroundColor Red
}

Write-Host "`n--- SUMMARY ---" -ForegroundColor Cyan
Write-Host "  Groups granted     : $($granted.Count)"
Write-Host "  Dynamic (baseline) : $(@($granted | Where-Object Kind -eq 'Dynamic').Count)"
Write-Host "  Assigned (entitle) : $(@($granted | Where-Object Kind -eq 'Assigned').Count)"

#endregion

#region Evidence -------------------------------------------------------------

if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null }
$stamp = $eventStart.ToString('yyyyMMdd-HHmmss')
$json  = Join-Path $OutputPath "joiner-event-$stamp.json"

[pscustomobject]@{
    eventMetadata = [pscustomobject]@{
        eventType   = 'Joiner'
        operator    = $context.Account
        tenantId    = $context.TenantId
        subjectUpn  = $upn
        subjectName = $name
        eventUtc    = $eventStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    attributesSet = [pscustomobject]@{
        department = $Department; jobTitle = $JobTitle
        officeLocation = $OfficeLocation; employeeType = $EmployeeType
        employeeId = $EmployeeId; usageLocation = $UsageLocation
        manager = if ($manager) { $manager.UserPrincipalName } else { $null }
    }
    accessGranted            = $granted
    entitlementGroupsGranted = @($ent)
    leastPrivilegePass       = ($ent.Count -eq 0)
} | ConvertTo-Json -Depth 6 | Out-File $json -Encoding utf8

Write-Host "`n  Evidence : $json" -ForegroundColor Green
Write-Host ""

#endregion