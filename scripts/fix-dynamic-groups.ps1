<#
.SYNOPSIS
    Remediates two dynamic membership groups that failed on unsupported properties.

.DESCRIPTION
    Microsoft Graph property names and Entra dynamic-membership rule property
    names are NOT the same namespace. Two failures resulted:

      officeLocation  -> not valid in rule syntax. The rule engine uses the
                         legacy directory name 'physicalDeliveryOfficeName'.

      employeeType    -> not a supported dynamic-rule property at all. The
                         documented workaround is to mirror the value into one
                         of the extensionAttribute1-15 slots via Graph and
                         write the rule against that.

    This script mirrors employeeType into extensionAttribute1 for every user,
    then creates the two missing groups with corrected rules.

.NOTES
    Prerequisites:
      Connect-MgGraph -Scopes 'User.ReadWrite.All','Group.ReadWrite.All','Directory.ReadWrite.All'
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

#region Preflight ------------------------------------------------------------

Write-Host "`n=== PREFLIGHT ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph. Run Connect-MgGraph first." }

Write-Host "  Connected as : $($context.Account)"
Write-Host "  Tenant       : $($context.TenantId)`n"

Write-Host "=== CURRENT GROUP STATE ===" -ForegroundColor Cyan

$expected = @(
    'RBAC-Clinical-Staff'
    'RBAC-Clinical-Prescribers'
    'RBAC-RevCycle-Staff'
    'RBAC-HIM-Staff'
    'RBAC-Contractors-All'
    'RBAC-Site-Marietta'
)

foreach ($name in $expected) {
    $g = Get-MgGroup -Filter "displayName eq '$name'" -ErrorAction SilentlyContinue
    if ($g) {
        $count = (Get-MgGroupMember -GroupId $g.Id -All -ErrorAction SilentlyContinue).Count
        Write-Host ("  [EXISTS]  {0,-28} members: {1}" -f $name, $count) -ForegroundColor Green
    }
    else {
        Write-Host ("  [MISSING] {0}" -f $name) -ForegroundColor Yellow
    }
}

#endregion

#region Mirror employeeType into extensionAttribute1 -------------------------

Write-Host "`n=== MIRROR employeeType -> extensionAttribute1 ===" -ForegroundColor Cyan

$users = Get-MgUser -All -Property 'id','displayName','employeeType','onPremisesExtensionAttributes' |
         Where-Object { $_.EmployeeType }

Write-Host "  Users with employeeType set: $($users.Count)`n"

$mirrored = 0
$mirrorFailed = @()

foreach ($u in $users) {

    if (-not $PSCmdlet.ShouldProcess($u.DisplayName, "Set extensionAttribute1 = $($u.EmployeeType)")) { continue }

    try {
        Update-MgUser -UserId $u.Id -ErrorAction Stop -BodyParameter @{
            onPremisesExtensionAttributes = @{
                extensionAttribute1 = $u.EmployeeType
            }
        }
        Write-Host ("  [SET]    {0,-22} extensionAttribute1 = {1}" -f $u.DisplayName, $u.EmployeeType) -ForegroundColor Green
        $mirrored++
    }
    catch {
        Write-Host ("  [FAIL]   {0} - {1}" -f $u.DisplayName, $_.Exception.Message) -ForegroundColor Red
        $mirrorFailed += $u.DisplayName
    }
}

Write-Host "`n  Mirrored: $mirrored / $($users.Count)"

#endregion

#region Create corrected groups ----------------------------------------------

Write-Host "`n=== CREATE CORRECTED GROUPS ===" -ForegroundColor Cyan

$groups = @(
    @{
        Name        = 'RBAC-Contractors-All'
        Description = 'Dynamic. All non-employee workers. Conditional Access targeting.'
        Rule        = '(user.extensionAttribute1 -eq "Contractor")'
        Note        = 'employeeType unsupported in rule syntax; mirrored to extensionAttribute1.'
    }
    @{
        Name        = 'RBAC-Site-Marietta'
        Description = 'Dynamic. Marietta campus staff. Location-scoped policy targeting.'
        Rule        = '(user.physicalDeliveryOfficeName -eq "Marietta")'
        Note        = 'officeLocation in Graph maps to physicalDeliveryOfficeName in rule syntax.'
    }
)

$created = 0
$failed  = @()

foreach ($group in $groups) {

    $existing = Get-MgGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]   $($group.Name) - already exists" -ForegroundColor DarkGray
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($group.Name, 'Create dynamic security group')) { continue }

    try {
        # -ErrorAction Stop is REQUIRED here. Graph SDK cmdlets can emit
        # non-terminating errors that bypass $ErrorActionPreference, which
        # silently inflates success counters.
        $null = New-MgGroup -ErrorAction Stop -BodyParameter @{
            displayName                   = $group.Name
            description                   = $group.Description
            mailEnabled                   = $false
            mailNickname                  = ($group.Name -replace '[^a-zA-Z0-9]', '')
            securityEnabled               = $true
            groupTypes                    = @('DynamicMembership')
            membershipRule                = $group.Rule
            membershipRuleProcessingState = 'On'
        }

        Write-Host "  [CREATE] $($group.Name)" -ForegroundColor Green
        Write-Host "           Rule: $($group.Rule)" -ForegroundColor DarkGray
        Write-Host "           Note: $($group.Note)" -ForegroundColor DarkGray
        $created++
    }
    catch {
        Write-Host "  [FAIL]   $($group.Name)" -ForegroundColor Red
        Write-Host "           $($_.Exception.Message)" -ForegroundColor Red
        $failed += $group.Name
    }
}

#endregion

#region Wait and report ------------------------------------------------------

if (-not $WhatIfPreference) {

    Write-Host "`n=== WAITING FOR MEMBERSHIP EVALUATION (3 min) ===" -ForegroundColor Cyan
    Write-Host "  Attribute writes plus new rules both need reprocessing.`n" -ForegroundColor DarkGray

    1..180 | ForEach-Object {
        Write-Progress -Activity 'Waiting for dynamic membership evaluation' `
                       -Status "$_ of 180 seconds" -PercentComplete ($_ / 180 * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity 'Waiting for dynamic membership evaluation' -Completed

    Write-Host "=== FINAL MEMBERSHIP COUNTS ===" -ForegroundColor Cyan

    $expectedCounts = @{
        'RBAC-Clinical-Staff'       = 9
        'RBAC-Clinical-Prescribers' = 5
        'RBAC-RevCycle-Staff'       = 8
        'RBAC-HIM-Staff'            = 6
        'RBAC-Contractors-All'      = 3
        'RBAC-Site-Marietta'        = 10
    }

    $report = foreach ($name in $expected) {
        $g = Get-MgGroup -Filter "displayName eq '$name'" -ErrorAction SilentlyContinue
        if (-not $g) {
            [pscustomobject]@{ Group = $name; Members = 'MISSING'; Expected = $expectedCounts[$name]; Match = 'NO' }
            continue
        }
        $count = (Get-MgGroupMember -GroupId $g.Id -All -ErrorAction SilentlyContinue).Count
        [pscustomobject]@{
            Group    = $name
            Members  = $count
            Expected = $expectedCounts[$name]
            Match    = if ($count -eq $expectedCounts[$name]) { 'YES' } else { 'NO' }
        }
    }

    $report |