<#
.SYNOPSIS
    Creates attribute-driven dynamic security groups in Microsoft Entra ID.

.DESCRIPTION
    Membership is computed from user attributes, never assigned by hand. When a
    user's department, jobTitle, officeLocation, or employeeType changes, Entra
    recalculates membership automatically. This is the mechanism that makes
    attribute-driven RBAC and automated mover (JML) processing possible.

    Deliberately excluded: entitlements that create segregation-of-duties
    conflicts (medical coding, charge entry, claims submission). Those are
    provisioned as ASSIGNED groups so that toxic combinations arise the way they
    do in production - from manual exception grants layered over clean baseline
    access.

.NOTES
    Requires Entra ID P1 or higher. Dynamic membership evaluation is
    asynchronous; allow several minutes for initial population.

    Prerequisites:
      Connect-MgGraph -Scopes 'Group.ReadWrite.All','Directory.ReadWrite.All'

.EXAMPLE
    .\create-dynamic-groups.ps1

.EXAMPLE
    .\create-dynamic-groups.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

#region Preflight ------------------------------------------------------------

Write-Host "`n=== PREFLIGHT ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph first."
}

$requiredScopes = @('Group.ReadWrite.All', 'Directory.ReadWrite.All')
$missingScopes  = $requiredScopes | Where-Object { $_ -notin $context.Scopes }
if ($missingScopes) {
    throw "Missing required Graph scopes: $($missingScopes -join ', ')"
}

# Dynamic membership is a premium feature - verify the SKU before proceeding.
$premiumSku = Get-MgSubscribedSku |
    Where-Object { $_.SkuPartNumber -in @('AAD_PREMIUM', 'AAD_PREMIUM_P2') }

if (-not $premiumSku) {
    throw "No Entra ID P1/P2 SKU found in this tenant. Dynamic groups require a premium license."
}

Write-Host "  Connected as : $($context.Account)"
Write-Host "  Tenant       : $($context.TenantId)"
Write-Host "  Premium SKU  : $($premiumSku.SkuPartNumber -join ', ')" -ForegroundColor Green

#endregion

#region Group definitions ----------------------------------------------------

$groups = @(
    @{
        Name        = 'RBAC-Clinical-Staff'
        Description = 'Dynamic. All Clinical department staff. Baseline EHR read access.'
        Rule        = '(user.department -eq "Clinical")'
        Rationale   = 'Department-scoped baseline. Broadest clinical grant.'
    }
    @{
        Name        = 'RBAC-Clinical-Prescribers'
        Description = 'Dynamic. Licensed prescribers only. Medication ordering rights.'
        Rule        = '(user.department -eq "Clinical") -and ((user.jobTitle -eq "Attending Physician") -or (user.jobTitle -eq "Resident Physician") -or (user.jobTitle -eq "Nurse Practitioner"))'
        Rationale   = 'HIPAA minimum necessary: prescribing is narrower than clinical access.'
    }
    @{
        Name        = 'RBAC-RevCycle-Staff'
        Description = 'Dynamic. Revenue Cycle department. Baseline billing system access.'
        Rule        = '(user.department -eq "Revenue Cycle")'
        Rationale   = 'Department-scoped baseline. Sensitive sub-functions granted separately.'
    }
    @{
        Name        = 'RBAC-HIM-Staff'
        Description = 'Dynamic. Health Information Management. Chart and record access.'
        Rule        = '(user.department -eq "Health Information Management")'
        Rationale   = 'Department-scoped baseline for record custodianship.'
    }
    @{
        Name        = 'RBAC-Contractors-All'
        Description = 'Dynamic. All non-employee workers. Conditional Access targeting.'
        Rule        = '(user.accountEnabled -eq true) -and (user.extensionAttribute1 -eq "Contractor")'
        Rationale   = 'Worker-type segmentation for stricter access controls.'
    }
    @{
        Name        = 'RBAC-Site-Marietta'
        Description = 'Dynamic. Marietta campus staff. Location-scoped policy targeting.'
        Rule        = '(user.accountEnabled -eq true) -and (user.physicalDeliveryOfficeName -eq "Marietta")'
        Rationale   = 'Site segmentation for location-aware Conditional Access.'
    }
)

#endregion

#region Create groups --------------------------------------------------------

Write-Host "`n=== CREATE DYNAMIC GROUPS ===" -ForegroundColor Cyan
Write-Host "  Target: $($groups.Count) groups`n"

$created = 0
$skipped = 0
$failed  = @()

foreach ($group in $groups) {

    $existing = Get-MgGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]   $($group.Name) - already exists" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($group.Name, 'Create dynamic security group')) { continue }

    try {
        $null = New-MgGroup -BodyParameter @{
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
        $created++
    }
    catch {
        Write-Host "  [FAIL]   $($group.Name) - $($_.Exception.Message)" -ForegroundColor Red
        $failed += [pscustomobject]@{ Group = $group.Name; Error = $_.Exception.Message }
    }
}

#endregion

#region Wait for evaluation --------------------------------------------------

if ($created -gt 0 -and -not $WhatIfPreference) {
    Write-Host "`n=== WAITING FOR MEMBERSHIP EVALUATION ===" -ForegroundColor Cyan
    Write-Host "  Dynamic membership is processed asynchronously." -ForegroundColor DarkGray
    Write-Host "  Waiting 90 seconds before reporting counts...`n" -ForegroundColor DarkGray

    1..90 | ForEach-Object {
        Write-Progress -Activity 'Waiting for dynamic membership evaluation' `
                       -Status "$_ of 90 seconds" -PercentComplete ($_ / 90 * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity 'Waiting for dynamic membership evaluation' -Completed
}

#endregion

#region Report ---------------------------------------------------------------

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Groups created : $created"
Write-Host "  Groups skipped : $skipped"

if ($failed) {
    Write-Host "`n  FAILURES:" -ForegroundColor Red
    $failed | Format-Table -AutoSize
}

if (-not $WhatIfPreference) {

    Write-Host "`n=== MEMBERSHIP COUNTS ===" -ForegroundColor Cyan

    $report = foreach ($group in $groups) {
        $g = Get-MgGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
        if (-not $g) { continue }

        $memberCount = (Get-MgGroupMember -GroupId $g.Id -All -ErrorAction SilentlyContinue).Count

        [pscustomobject]@{
            Group   = $group.Name
            Members = $memberCount
            State   = $g.MembershipRuleProcessingState
        }
    }

    $report | Format-Table -AutoSize

    Write-Host "  Expected: Clinical-Staff 9, Prescribers 5, RevCycle 8," -ForegroundColor DarkGray
    Write-Host "            HIM 6, Contractors 3, Marietta 10" -ForegroundColor DarkGray
    Write-Host "  Counts of 0 usually mean evaluation has not finished yet." -ForegroundColor DarkGray
}

Write-Host "`nDynamic group provisioning complete.`n" -ForegroundColor Green

#endregion