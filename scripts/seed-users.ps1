<#
.SYNOPSIS
    Seeds a healthcare-model organization into Microsoft Entra ID for identity
    governance demonstration and testing.

.DESCRIPTION
    Provisions ~34 users across Clinical, Revenue Cycle, Health Information
    Management (HIM), Information Technology, Compliance, Finance, and HR,
    with the attributes required for attribute-driven RBAC:

        department        - drives dynamic group membership
        jobTitle          - drives role-level entitlement scoping
        officeLocation    - drives site-based Conditional Access scoping
        employeeType      - drives Employee/Contractor/Intern policy separation
        employeeId        - stable HR-system correlation key
        usageLocation     - REQUIRED before any license can be assigned
        manager           - drives manager-attested access reviews and JML moves

    The script is idempotent: re-running it skips users that already exist.

.NOTES
    Passwords are randomly generated, never written to disk or console, and
    flagged for change at first sign-in.

    Prerequisites:
      Connect-MgGraph -Scopes 'User.ReadWrite.All','Directory.ReadWrite.All'

.EXAMPLE
    .\seed-users.ps1 -TenantDomain 'Kadestekoubegzigmail.onmicrosoft.com'
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantDomain,

    [Parameter()]
    [string]$CompanyName = 'Northlake Regional Health',

    [Parameter()]
    [string]$UsageLocation = 'US'
)

$ErrorActionPreference = 'Stop'

#region Preflight ------------------------------------------------------------

Write-Host "`n=== PREFLIGHT ===" -ForegroundColor Cyan

$context = Get-MgContext
if (-not $context) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph first."
}

$requiredScopes = @('User.ReadWrite.All', 'Directory.ReadWrite.All')
$missingScopes  = $requiredScopes | Where-Object { $_ -notin $context.Scopes }

if ($missingScopes) {
    throw "Missing required Graph scopes: $($missingScopes -join ', ')"
}

Write-Host "  Connected as : $($context.Account)"
Write-Host "  Tenant       : $($context.TenantId)"
Write-Host "  Domain       : $TenantDomain"
Write-Host "  Scopes OK    : $($requiredScopes -join ', ')" -ForegroundColor Green

#endregion

#region Password generation --------------------------------------------------

function New-CompliantPassword {
    [CmdletBinding()]
    param([int]$Length = 24)

    $upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower  = 'abcdefghijkmnopqrstuvwxyz'
    $digit  = '23456789'
    $symbol = '!@#$%^&*-_=+'
    $all    = $upper + $lower + $digit + $symbol

    $chars = @(
        $upper[(Get-Random -Maximum $upper.Length)]
        $lower[(Get-Random -Maximum $lower.Length)]
        $digit[(Get-Random -Maximum $digit.Length)]
        $symbol[(Get-Random -Maximum $symbol.Length)]
    )

    $chars += 1..($Length - 4) | ForEach-Object {
        $all[(Get-Random -Maximum $all.Length)]
    }

    -join ($chars | Sort-Object { Get-Random })
}

#endregion

#region Org definition -------------------------------------------------------

$org = @(
    # --- Leadership -------------------------------------------------------
    @{ First='Marcus';   Last='Webb';       Title='Chief Medical Officer';             Dept='Clinical';                      Site='Atlanta';  Type='Employee';   Id='E1001'; Mgr=$null }
    @{ First='Diane';    Last='Foster';     Title='VP Revenue Cycle';                  Dept='Revenue Cycle';                 Site='Atlanta';  Type='Employee';   Id='E1002'; Mgr=$null }
    @{ First='Priya';    Last='Raman';      Title='Director of HIM';                   Dept='Health Information Management'; Site='Atlanta';  Type='Employee';   Id='E1003'; Mgr=$null }
    @{ First='Alan';     Last='Kirsch';     Title='Chief Compliance Officer';          Dept='Compliance';                    Site='Atlanta';  Type='Employee';   Id='E1004'; Mgr=$null }
    @{ First='Nadia';    Last='Haddad';     Title='Identity Engineer';                 Dept='Information Technology';        Site='Atlanta';  Type='Employee';   Id='E1005'; Mgr=$null }

    # --- Clinical ---------------------------------------------------------
    @{ First='Sofia';    Last='Marchetti';  Title='Attending Physician';               Dept='Clinical';                      Site='Atlanta';  Type='Employee';   Id='E2001'; Mgr='marcus.webb' }
    @{ First='James';    Last='Okonkwo';    Title='Attending Physician';               Dept='Clinical';                      Site='Marietta'; Type='Employee';   Id='E2002'; Mgr='marcus.webb' }
    @{ First='Nina';     Last='Kowalski';   Title='Attending Physician';               Dept='Clinical';                      Site='Atlanta';  Type='Employee';   Id='E2003'; Mgr='marcus.webb' }
    @{ First='Rachel';   Last='Byrne';      Title='Nurse Practitioner';                Dept='Clinical';                      Site='Atlanta';  Type='Employee';   Id='E2004'; Mgr='marcus.webb' }
    @{ First='Devon';    Last='Price';      Title='Registered Nurse';                  Dept='Clinical';                      Site='Marietta'; Type='Employee';   Id='E2005'; Mgr='rachel.byrne' }
    @{ First='Amara';    Last='Diallo';     Title='Registered Nurse';                  Dept='Clinical';                      Site='Atlanta';  Type='Employee';   Id='E2006'; Mgr='rachel.byrne' }
    @{ First='Owen';     Last='Brady';      Title='Resident Physician';                Dept='Clinical';                      Site='Atlanta';  Type='Intern';     Id='E2007'; Mgr='sofia.marchetti' }
    @{ First='Tomas';    Last='Herrera';    Title='Clinical Assistant';                Dept='Clinical';                      Site='Marietta'; Type='Contractor'; Id='C2008'; Mgr='rachel.byrne' }

    # --- Revenue Cycle ----------------------------------------------------
    @{ First='Latoya';   Last='Simms';      Title='Billing Manager';                   Dept='Revenue Cycle';                 Site='Atlanta';  Type='Employee';   Id='E3001'; Mgr='diane.foster' }
    @{ First='Carl';     Last='Ndiaye';     Title='Charge Entry Specialist';           Dept='Revenue Cycle';                 Site='Marietta'; Type='Employee';   Id='E3002'; Mgr='latoya.simms' }
    @{ First='Bethany';  Last='Cruz';       Title='Claims Submission Specialist';      Dept='Revenue Cycle';                 Site='Atlanta';  Type='Employee';   Id='E3003'; Mgr='latoya.simms' }
    @{ First='Ivan';     Last='Petrov';     Title='Payment Posting Specialist';        Dept='Revenue Cycle';                 Site='Atlanta';  Type='Employee';   Id='E3004'; Mgr='latoya.simms' }
    @{ First='Grace';    Last='Lindqvist';  Title='Medical Coder';                     Dept='Revenue Cycle';                 Site='Marietta'; Type='Employee';   Id='E3005'; Mgr='latoya.simms' }
    @{ First='Hassan';   Last='Amiri';      Title='Medical Coder';                     Dept='Revenue Cycle';                 Site='Atlanta';  Type='Employee';   Id='E3006'; Mgr='latoya.simms' }
    @{ First='Terrence'; Last='Wu';         Title='Denials Analyst';                   Dept='Revenue Cycle';                 Site='Marietta'; Type='Contractor'; Id='C3007'; Mgr='latoya.simms' }

    # --- Health Information Management ------------------------------------
    @{ First='Yolanda';  Last='Bright';     Title='HIM Technician';                    Dept='Health Information Management'; Site='Atlanta';  Type='Employee';   Id='E4001'; Mgr='priya.raman' }
    @{ First='Kai';      Last='Tanaka';     Title='HIM Technician';                    Dept='Health Information Management'; Site='Marietta'; Type='Employee';   Id='E4002'; Mgr='priya.raman' }
    @{ First='Peter';    Last='Novak';      Title='Release of Information Specialist'; Dept='Health Information Management'; Site='Atlanta';  Type='Employee';   Id='E4003'; Mgr='priya.raman' }
    @{ First='Sandra';   Last='Elu';        Title='Record Amendment Specialist';       Dept='Health Information Management'; Site='Marietta'; Type='Employee';   Id='E4004'; Mgr='priya.raman' }
    @{ First='Monica';   Last='Reyes';      Title='Privacy Analyst';                   Dept='Health Information Management'; Site='Atlanta';  Type='Employee';   Id='E4005'; Mgr='priya.raman' }

    # --- Information Technology -------------------------------------------
    @{ First='Blake';    Last='Ferris';     Title='Systems Administrator';             Dept='Information Technology';        Site='Atlanta';  Type='Employee';   Id='E5001'; Mgr='nadia.haddad' }
    @{ First='Corey';    Last='Dunn';       Title='Service Desk Analyst';              Dept='Information Technology';        Site='Marietta'; Type='Contractor'; Id='C5002'; Mgr='nadia.haddad' }
    @{ First='Elena';    Last='Vasquez';    Title='Service Desk Analyst';              Dept='Information Technology';        Site='Atlanta';  Type='Employee';   Id='E5003'; Mgr='nadia.haddad' }

    # --- Compliance & Internal Audit --------------------------------------
    @{ First='Gerald';   Last='Mbeki';      Title='Internal Auditor';                  Dept='Compliance';                    Site='Atlanta';  Type='Employee';   Id='E6001'; Mgr='alan.kirsch' }
    @{ First='Hana';     Last='Suzuki';     Title='Compliance Analyst';                Dept='Compliance';                    Site='Atlanta';  Type='Employee';   Id='E6002'; Mgr='alan.kirsch' }
    @{ First='Victor';   Last='Salaz';      Title='Privacy Officer';                   Dept='Compliance';                    Site='Marietta'; Type='Employee';   Id='E6003'; Mgr='alan.kirsch' }

    # --- Finance & HR -----------------------------------------------------
    @{ First='Ruth';     Last='Kellerman';  Title='Payroll Specialist';                Dept='Finance';                       Site='Atlanta';  Type='Employee';   Id='E7001'; Mgr='diane.foster' }
    @{ First='Omar';     Last='Sadiq';      Title='Accounts Payable Clerk';            Dept='Finance';                       Site='Atlanta';  Type='Employee';   Id='E7002'; Mgr='diane.foster' }
    @{ First='Julia';    Last='Frost';      Title='HR Generalist';                     Dept='Human Resources';               Site='Atlanta';  Type='Employee';   Id='E8001'; Mgr='alan.kirsch' }
)

#endregion

#region Pass 1 - Create users ------------------------------------------------

Write-Host "`n=== PASS 1: CREATE USERS ===" -ForegroundColor Cyan
Write-Host "  Target: $($org.Count) users`n"

$created = 0
$skipped = 0
$failed  = @()

foreach ($person in $org) {

    $alias = "$($person.First).$($person.Last)".ToLower()
    $upn   = "$alias@$TenantDomain"
    $name  = "$($person.First) $($person.Last)"

    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]   $name - already exists" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($upn, 'Create Entra ID user')) { continue }

    try {
        $null = New-MgUser -BodyParameter @{
            accountEnabled    = $true
            displayName       = $name
            givenName         = $person.First
            surname           = $person.Last
            userPrincipalName = $upn
            mailNickname      = $alias -replace '\.', ''
            jobTitle          = $person.Title
            department        = $person.Dept
            officeLocation    = $person.Site
            employeeId        = $person.Id
            employeeType      = $person.Type
            companyName       = $CompanyName
            usageLocation     = $UsageLocation
            passwordProfile   = @{
                password                      = New-CompliantPassword
                forceChangePasswordNextSignIn = $true
            }
        }

        Write-Host ("  [CREATE] {0,-20} {1,-38} {2}" -f $name, $person.Title, $person.Dept) -ForegroundColor Green
        $created++
    }
    catch {
        Write-Host "  [FAIL]   $name - $($_.Exception.Message)" -ForegroundColor Red
        $failed += [pscustomobject]@{ User = $name; Upn = $upn; Error = $_.Exception.Message }
    }
}

#endregion

#region Pass 2 - Manager relationships ---------------------------------------

Write-Host "`n=== PASS 2: MANAGER RELATIONSHIPS ===" -ForegroundColor Cyan

Start-Sleep -Seconds 5

$linked     = 0
$mgrSkipped = 0
$mgrFailed  = @()

foreach ($person in ($org | Where-Object { $_.Mgr })) {

    $alias      = "$($person.First).$($person.Last)".ToLower()
    $upn        = "$alias@$TenantDomain"
    $managerUpn = "$($person.Mgr)@$TenantDomain"
    $name       = "$($person.First) $($person.Last)"

    try {
        $user    = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
        $manager = Get-MgUser -Filter "userPrincipalName eq '$managerUpn'" -ErrorAction Stop

        if (-not $user -or -not $manager) {
            Write-Host "  [SKIP]   $name - user or manager not found" -ForegroundColor DarkGray
            $mgrSkipped++
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($upn, "Set manager to $managerUpn")) { continue }

        Set-MgUserManagerByRef -UserId $user.Id -BodyParameter @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)"
        }

        Write-Host ("  [LINK]   {0,-20} -> {1}" -f $name, $manager.DisplayName) -ForegroundColor Green
        $linked++
    }
    catch {
        Write-Host "  [FAIL]   $name - $($_.Exception.Message)" -ForegroundColor Red
        $mgrFailed += [pscustomobject]@{ User = $name; Manager = $managerUpn; Error = $_.Exception.Message }
    }
}

#endregion

#region Summary --------------------------------------------------------------

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Users created        : $created"
Write-Host "  Users skipped        : $skipped"
Write-Host "  Manager links set    : $linked"
Write-Host "  Manager links skipped: $mgrSkipped"

if ($failed) {
    Write-Host "`n  USER CREATION FAILURES:" -ForegroundColor Red
    $failed | Format-Table -AutoSize
}

if ($mgrFailed) {
    Write-Host "`n  MANAGER LINK FAILURES:" -ForegroundColor Red
    $mgrFailed | Format-Table -AutoSize
}

Write-Host "`n=== DEPARTMENT DISTRIBUTION ===" -ForegroundColor Cyan
Get-MgUser -All -Property DisplayName, Department, JobTitle, OfficeLocation, EmployeeType |
    Where-Object { $_.Department } |
    Group-Object Department |
    Sort-Object Name |
    Select-Object @{n='Department';e={$_.Name}}, @{n='Users';e={$_.Count}} |
    Format-Table -AutoSize

Write-Host "=== EMPLOYEE TYPE DISTRIBUTION ===" -ForegroundColor Cyan
Get-MgUser -All -Property DisplayName, EmployeeType |
    Where-Object { $_.EmployeeType } |
    Group-Object EmployeeType |
    Sort-Object Name |
    Select-Object @{n='EmployeeType';e={$_.Name}}, @{n='Users';e={$_.Count}} |
    Format-Table -AutoSize

Write-Host "Seed complete.`n" -ForegroundColor Green

#endregion