<#
.SYNOPSIS
    Detects dormant, never-used, and unattested identities in Microsoft Entra ID.

.DESCRIPTION
    Four detection categories, each mapping to a distinct governance failure:

      NeverSignedIn   Account provisioned but never authenticated. Common after
                      bulk migration or when onboarding completes for a person
                      who never starts.

      Stale           Authenticated at least once, then dormant beyond the
                      threshold. The classic orphaned account: the human left,
                      the deprovisioning step never ran.

      NoManager       No manager assigned. Manager-attested access reviews
                      silently skip these identities, so their access is never
                      challenged by anyone.

      OwnerlessGroup  Group with no owner. Nobody is accountable for attesting
                      its membership during a recertification campaign.

    signInActivity requires AuditLog.Read.All and must be requested explicitly.
    Graph returns null both when a user has never signed in AND when the
    property was not properly requested. This script distinguishes the two by
    checking whether ANY user in the tenant returned sign-in data.

.PARAMETER StaleDays
    Days of inactivity before an account is considered stale. Default 90.

.EXAMPLE
    .\Get-OrphanedStaleAccounts.ps1

.EXAMPLE
    .\Get-OrphanedStaleAccounts.ps1 -StaleDays 30 -Format All
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$StaleDays = 90,

    [Parameter()]
    [string]$OutputPath = '..\evidence',

    [Parameter()]
    [ValidateSet('Console','Csv','Json','All')]
    [string]$Format = 'Console'
)

$ErrorActionPreference = 'Stop'
$scanStart = Get-Date

#region Preflight ------------------------------------------------------------

Write-Host "`n=== ORPHANED & STALE ACCOUNT SCAN ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph. Run Connect-MgGraph first." }

if ('AuditLog.Read.All' -notin $context.Scopes) {
    Write-Warning "AuditLog.Read.All not granted. Sign-in activity will be unavailable."
}

$threshold = (Get-Date).AddDays(-$StaleDays)

Write-Host "  Tenant          : $($context.TenantId)"
Write-Host "  Operator        : $($context.Account)"
Write-Host "  Stale threshold : $StaleDays days (before $($threshold.ToString('yyyy-MM-dd')))"
Write-Host "  Scan started    : $($scanStart.ToString('yyyy-MM-dd HH:mm:ss'))"

#endregion

#region Retrieve users -------------------------------------------------------

Write-Host "`n--- Retrieving identities ---" -ForegroundColor Cyan

# signInActivity must be named explicitly in -Property. It is not returned by
# default and is silently omitted rather than erroring if left out.
$users = Get-MgUser -All -Property @(
    'id','displayName','userPrincipalName','accountEnabled','createdDateTime'
    'department','jobTitle','employeeId','employeeType','signInActivity'
)

Write-Host "  Identities retrieved: $($users.Count)"

# Distinguish "nobody has signed in" from "the property did not come back".
$anySignInData = $users | Where-Object { $_.SignInActivity }
if (-not $anySignInData) {
    Write-Warning "  No sign-in activity returned for ANY identity."
    Write-Warning "  This is expected in a new tenant where no user has authenticated."
    Write-Warning "  It is ALSO what a failed property request looks like - verify AuditLog.Read.All."
}
else {
    Write-Host "  Identities with sign-in history: $($anySignInData.Count)" -ForegroundColor Green
}

#endregion

#region Classify -------------------------------------------------------------

Write-Host "`n--- Classifying identities ---" -ForegroundColor Cyan

$findings = @()
$i = 0

foreach ($u in $users) {

    $i++
    Write-Progress -Activity 'Classifying identities' `
                   -Status "$i of $($users.Count)" -PercentComplete ($i / $users.Count * 100)

    $lastSignIn = $null
    if ($u.SignInActivity) {
        $interactive    = $u.SignInActivity.LastSignInDateTime
        $nonInteractive = $u.SignInActivity.LastNonInteractiveSignInDateTime
        $candidates     = @($interactive, $nonInteractive) | Where-Object { $_ }
        if ($candidates) { $lastSignIn = ($candidates | Sort-Object -Descending)[0] }
    }

    # Manager is a navigation property, resolved per user.
    $managerName = $null
    try {
        $mgr = Get-MgUserManager -UserId $u.Id -ErrorAction Stop
        $managerName = $mgr.AdditionalProperties.displayName
    }
    catch { $managerName = $null }

    $ageDays = if ($u.CreatedDateTime) {
        [math]::Round(((Get-Date) - $u.CreatedDateTime).TotalDays, 0)
    } else { $null }

    $categories = @()

    if (-not $lastSignIn) { $categories += 'NeverSignedIn' }
    elseif ($lastSignIn -lt $threshold) { $categories += 'Stale' }

    if (-not $managerName) { $categories += 'NoManager' }

    if ($categories.Count -eq 0) { continue }

    $findings += [pscustomobject]@{
        Category        = ($categories -join '; ')
        DisplayName     = $u.DisplayName
        Upn             = $u.UserPrincipalName
        Enabled         = $u.AccountEnabled
        Department      = $u.Department
        JobTitle        = $u.JobTitle
        EmployeeType    = $u.EmployeeType
        Manager         = if ($managerName) { $managerName } else { '(none)' }
        LastSignIn      = if ($lastSignIn) { $lastSignIn.ToString('yyyy-MM-dd') } else { '(never)' }
        AccountAgeDays  = $ageDays
        DetectedUtc     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}

Write-Progress -Activity 'Classifying identities' -Completed

#endregion

#region Ownerless groups -----------------------------------------------------

Write-Host "`n--- Checking group ownership ---" -ForegroundColor Cyan

$groups = Get-MgGroup -All -Property 'id','displayName','description','groupTypes','createdDateTime'
$ownerless = @()

foreach ($g in $groups) {
    try {
        $owners = Get-MgGroupOwner -GroupId $g.Id -All -ErrorAction Stop
        if (-not $owners -or $owners.Count -eq 0) {
            $memberCount = (Get-MgGroupMember -GroupId $g.Id -All -ErrorAction SilentlyContinue).Count
            $ownerless += [pscustomobject]@{
                Category    = 'OwnerlessGroup'
                GroupName   = $g.DisplayName
                GroupType   = if ($g.GroupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' }
                Members     = $memberCount
                Description = $g.Description
                DetectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
    }
    catch {
        Write-Warning "  Could not resolve owners for $($g.DisplayName)"
    }
}

Write-Host "  Groups checked  : $($groups.Count)"
Write-Host "  Without an owner: $($ownerless.Count)" -ForegroundColor $(if ($ownerless.Count) { 'Yellow' } else { 'Green' })

#endregion

#region Report ---------------------------------------------------------------

$scanEnd  = Get-Date
$duration = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 1)

Write-Host "`n=== IDENTITY FINDINGS ===" -ForegroundColor Cyan

if ($findings.Count -eq 0) {
    Write-Host "  No dormant or unattested identities detected.`n" -ForegroundColor Green
}
else {
    $findings |
        Select-Object Category, DisplayName, Department, EmployeeType, Manager, LastSignIn, AccountAgeDays |
        Sort-Object Category, DisplayName |
        Format-Table -AutoSize

    Write-Host "--- BREAKDOWN BY CATEGORY ---" -ForegroundColor Cyan
    $findings | Group-Object Category |
        Sort-Object Count -Descending |
        Select-Object @{n='Category';e={$_.Name}}, @{n='Identities';e={$_.Count}} |
        Format-Table -AutoSize
}

if ($ownerless.Count -gt 0) {
    Write-Host "=== OWNERLESS GROUPS ===" -ForegroundColor Cyan
    $ownerless | Select-Object GroupName, GroupType, Members | Format-Table -AutoSize
    Write-Host "  Ownerless groups have no accountable party for membership attestation." -ForegroundColor DarkGray
    Write-Host "  Access review campaigns targeting these groups have no natural reviewer.`n" -ForegroundColor DarkGray
}

Write-Host "  Identities scanned : $($users.Count)"
Write-Host "  Identity findings  : $($findings.Count)"
Write-Host "  Groups scanned     : $($groups.Count)"
Write-Host "  Ownerless groups   : $($ownerless.Count)"
Write-Host "  Duration           : $duration seconds"

#endregion

#region Export ---------------------------------------------------------------

if ($Format -in @('Csv','Json','All')) {

    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $stamp = $scanStart.ToString('yyyyMMdd-HHmmss')

    if ($Format -in @('Csv','All')) {
        $findings  | Export-Csv (Join-Path $OutputPath "orphaned-identities-$stamp.csv") -NoTypeInformation -Encoding UTF8
        $ownerless | Export-Csv (Join-Path $OutputPath "ownerless-groups-$stamp.csv")    -NoTypeInformation -Encoding UTF8
        Write-Host "`n  CSV evidence  : $OutputPath\orphaned-identities-$stamp.csv" -ForegroundColor Green
        Write-Host "  CSV evidence  : $OutputPath\ownerless-groups-$stamp.csv" -ForegroundColor Green
    }

    if ($Format -in @('Json','All')) {
        $json = Join-Path $OutputPath "orphaned-stale-$stamp.json"
        [pscustomobject]@{
            scanMetadata = [pscustomobject]@{
                tenantId          = $context.TenantId
                operator          = $context.Account
                staleThresholdDays= $StaleDays
                scanStartedUtc    = $scanStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                scanCompletedUtc  = $scanEnd.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                durationSeconds   = $duration
                identitiesScanned = $users.Count
                groupsScanned     = $groups.Count
            }
            identityFindings = $findings
            ownerlessGroups  = $ownerless
        } | ConvertTo-Json -Depth 6 | Out-File $json -Encoding utf8
        Write-Host "  JSON evidence : $json" -ForegroundColor Green
    }
}

Write-Host ""

#endregion