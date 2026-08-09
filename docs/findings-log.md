# 🐛 Development Findings Log

Every defect found while building this toolkit, with the evidence that proves it.

Most portfolio projects show a working result. This log shows what broke first.

> **Why this document exists:** an identity governance tool that fails quietly is worse than no tool at all. Several of these findings are defects in the toolkit itself, not in Entra ID.

---

## Summary

| #  | Finding                                         | Type                | Severity    |
| -- | ----------------------------------------------- | ------------------- | ----------- |
| 1  | Role assignment silently failed                 | Provisioning gap    | 🟠 High     |
| 2  | Global Admin had read-only billing access       | Authorization plane | 🟡 Info     |
| 3  | License assignment blocked by missing attribute | Provisioning gap    | 🟠 High     |
| 4  | Graph and dynamic-rule attribute names differ   | Platform behavior   | 🟠 High     |
| 5  | Scanner reported clean against zero identities  | **Tool defect**     | 🔴 Critical |
| 6  | Badly scoped rule caused a false negative       | **Policy defect**   | 🟠 High     |
| 7  | Every group had no owner                        | Governance gap      | 🟠 High     |
| 8  | Terminated account retained group membership    | **Design defect**   | 🔴 Critical |

Findings 5, 6, and 8 are defects in this project's own design.

---

## 🔎 Finding #1 — A Role Assignment That Never Applied

**Date:** 2026-08-07
**Type:** Provisioning gap

### Symptom

A cloud administrator account was created with the Global Administrator role selected during the creation wizard.

The account existed.

The role did not.

```text
Roles and administrators -> Global Administrator
        |
        v
Only the original account listed
        |
        v
The new admin account was missing
```

### Root cause

The role selection in the user creation wizard did not commit.

No error was displayed.

### Fix

Assigned the role explicitly through **Roles and administrators -> Add assignments**.

Verified the assignment path showed `Direct`, scope `Directory`.

### Why it matters

```text
Account provisioned  OK
Access provisioned   FAILED
```

This is one of the most common findings in a real access review.

At two users it was visible by eye.

At two thousand users it would require tooling.

> The account existing is not proof that the access exists.

---

## 🔎 Finding #2 — Global Administrator With Read-Only Billing

**Date:** 2026-08-07
**Type:** Authorization plane separation

### Symptom

The Global Administrator account opened the billing page and saw:

```text
Your read permissions limit the changes you can make on this page.
```

### Root cause

Entra ID **directory roles** and Azure **billing account roles** are separate authorization planes.

```text
Directory plane          Billing plane
---------------          ---------------
Global Administrator     Billing account owner
        |                        |
        v                        v
Full directory control   Full commerce control

These do not overlap.
```

The subscription owner held billing rights.

The Global Administrator did not.

### Related observation

The subscription owner was a consumer Microsoft Account.

When that account attempted to sign in to the admin center it received:

```text
Error 530035
Login is not supported for consumer users without business presence.
```

So the account that **owned** billing could not authenticate into the portal that **displayed** billing.

### Why it matters

> "Administrator" in one system means nothing in another.

Least privilege must be evaluated per authorization plane, not per job title.

---

## 🔎 Finding #3 — License Assignment Blocked by a Missing Attribute

**Date:** 2026-08-07
**Type:** Provisioning gap

### Symptom

```text
Your assignment was unsuccessful
License assignment cannot be done for user with invalid usage location.
```

### Root cause

Entra ID requires `usageLocation` (an ISO 3166-2 country code) before any license can attach.

It is a legal and compliance field. Microsoft must know which country's service availability rules apply.

Users created through the portal do not receive one by default.

### Fix

```powershell
Update-MgUser -UserId <id> -UsageLocation "US"
```

The seeding script was then updated to set `usageLocation` at creation time for every identity.

### Why it matters

Everything looked correct:

```text
License available   OK
Admin had rights    OK
User was valid      OK
Provisioning        FAILED
```

The failure was a single missing attribute.

> This is the most common real-world cause of "the ticket says provisioned, but the user has no access."

---

## 🔎 Finding #4 — Graph and Dynamic Rule Attribute Names Are Not the Same Namespace

**Date:** 2026-08-07
**Type:** Platform behavior

### Symptom

Two dynamic group creations failed:

```text
Unsupported property 'employeeType'
Status: 400 (BadRequest)
ErrorCode: DynamicGroupQueryParseError

Unsupported property 'officeLocation'
Status: 400 (BadRequest)
ErrorCode: DynamicGroupQueryParseError
```

### Root cause

Microsoft Graph property names and Entra dynamic membership rule property names are **different namespaces**.

| Graph property   | Dynamic rule property        | Usable? |
| ---------------- | ---------------------------- | ------- |
| `department`     | `department`                 | Yes     |
| `jobTitle`       | `jobTitle`                   | Yes     |
| `officeLocation` | `physicalDeliveryOfficeName` | Yes     |
| `employeeType`   | *(not supported at all)*     | No      |

Graph modernized the property names.

The rule engine still uses legacy directory attribute names, and `employeeType` is not queryable in rules under any name.

### Fix

`officeLocation` was rewritten as `physicalDeliveryOfficeName`.

`employeeType` was mirrored into `extensionAttribute1` via Graph, then referenced in the rule:

```text
(user.extensionAttribute1 -eq "Contractor")
```

### Secondary defect found during the fix

The creation script reported **6 groups created** when only **4** existed.

Root cause: the script relied on `$ErrorActionPreference = 'Stop'` instead of `-ErrorAction Stop` on the cmdlet itself.

The Graph SDK emitted a non-terminating error that bypassed the try/catch, so the success counter incremented on a failed operation.

**Fix:** `-ErrorAction Stop` applied directly to every `New-MgGroup` call.

> A success counter that counts failures is worse than no counter.

---

## 🚨 Finding #5 — The Scanner Reported Clean After Checking Nobody

**Date:** 2026-08-08
**Type:** 🔴 **Defect in this toolkit**
**Evidence:** `evidence/sod-findings-20260808-191440.csv` *(0 bytes)*

### Symptom

```text
=== FINDINGS ===
  No segregation-of-duties violations detected.

  Identities scanned : 0
  Rules evaluated    : 5
  Findings           : 0
  Duration           : 0.4 seconds
```

Green text. Zero findings. Exit code 0.

A clean bill of health.

### Root cause

The Microsoft Graph token had expired mid-session.

```text
DeviceCodeCredential authentication failed
```

`Get-MgUser` returned nothing. The membership map was empty. Every rule evaluated against zero identities and matched nothing.

The scan **succeeded structurally while examining nothing.**

### Why this is the most serious finding in the project

```text
An obvious error gets investigated.

A false green light does not.
```

A scheduled compliance scan reporting "clean" because it never ran is invisible. Nobody opens a ticket for a passing control.

The 0.4-second duration was the only signal, and only to someone who knew a real scan takes about 5 seconds.

### Fix

A guard clause that aborts rather than reporting a false clean:

```powershell
if ($membership.Count -eq 0) {
    throw "Membership map is empty. Scan aborted to prevent a false clean result. Verify Graph authentication with Get-MgContext."
}
```

### Evidence

The zero-byte CSV from that run is retained deliberately.

```text
sod-findings-20260808-191440.csv   0 bytes
sod-findings-20260808-194650.csv   2,080 bytes
```

The first file is proof the defect existed. The second is proof it was fixed.

### Lesson

> A compliance control must distinguish "I checked and found nothing" from "I checked nothing."

---

## 🎯 Finding #6 — A Badly Scoped Rule Produced a False Negative

**Date:** 2026-08-08
**Type:** 🟠 **Defect in this project's policy design**
**Evidence:** `sod-findings-20260808-194650.csv` (3 findings) then `sod-findings-20260808-195416.csv` (4 findings)

### Symptom

Rule SOD-004 was written to catch systems administrators holding standing PHI access.

```text
SOD-004  High  Systems Administration + Full PHI Access   matches: 0
```

Zero matches, while a systems administrator with standing PHI access was sitting in the directory.

### Root cause

The rule paired `ENT-PHI-Full-Access` against `RBAC-Site-Marietta`.

A **site** group, not a **role** group.

```text
Blake Ferris
Systems Administrator
Office: Atlanta
        |
        v
Not in RBAC-Site-Marietta
        |
        v
Rule never matches
```

But the deeper cause was the group model itself.

**There was no IT group to reference.**

The original dynamic groups covered Clinical, Clinical-Prescribers, Revenue Cycle, HIM, Contractors, and Marietta.

Nothing for Information Technology.

The rule could not be written correctly because the directory could not express the risk.

### Fix

Created a new dynamic group:

```text
RBAC-IT-Staff
(user.accountEnabled -eq true) -and (user.department -eq "Information Technology")
```

Changed one line in `sod-matrix.json`:

```text
"groupB": "RBAC-Site-Marietta"    becomes    "groupB": "RBAC-IT-Staff"
```

Detection went from **3 findings to 4**.

### Lesson

> SoD rule quality is capped by group model quality.
>
> You cannot express a control your directory cannot represent.

This is why most of the effort in a real SoD program goes into tuning rules, not writing detection code.

---

## 👤 Finding #7 — Every Group in the Tenant Had No Owner

**Date:** 2026-08-08
**Type:** Governance gap
**Evidence:** `ownerless-groups-20260808-200441.csv` (1,878 bytes) then `ownerless-groups-20260808-200731.csv` *(0 bytes)*

### Symptom

```text
Groups scanned   : 13
Ownerless groups : 13
```

Every group. Including all six entitlement groups holding SoD conflicts.

### Root cause

The entire group model was built by script.

`New-MgGroup` does not assign an owner, and nothing in the build process ever did.

### Why it matters

Access review campaigns route to different reviewers depending on scope:

```text
Access package review   ->   the user's manager
Group-scoped review     ->   the group's owner
```

With no owners, a review targeting `ENT-Charge-Entry` has **no natural reviewer**.

It falls to a fallback administrator who has no basis for judging whether the membership is appropriate.

```text
Six groups holding every SoD conflict in the tenant
                    |
                    v
        No accountable reviewer
```

### Fix

Owners assigned by **business accountability**, not convenience:

| Group type            | Owner                 | Rationale                              |
| --------------------- | --------------------- | -------------------------------------- |
| Billing entitlements  | Billing Manager       | Owns revenue cycle operations          |
| PHI and record access | Director of HIM       | Designated record custodian            |
| Clinical RBAC         | Chief Medical Officer | Owns clinical staffing                 |
| IT RBAC               | Identity Engineer     | Owns infrastructure access             |
| Contractor group      | HR Generalist         | Owns non-employee worker relationships |

Ownerless groups went from **13 to 0**.

### Lesson

> Automation can build a technically correct environment while omitting the governance layer entirely.
>
> Nothing failed. Nothing errored. The gap only appeared when a tool went looking for it.

---

## 🚪 Finding #8 — A Terminated Account Kept Its Group Access

**Date:** 2026-08-08
**Type:** 🔴 **Defect in this project's design**
**Evidence:** `evidence/leaver-event-20260808-202348.json`

### Symptom

A contractor was terminated through the leaver script:

```text
Account enabled   : False
Groups before     : 3
Groups remaining  : 3
```

The account was correctly disabled. Sessions were revoked.

The contractor remained a member of all three access groups.

### Root cause

None of the dynamic membership rules tested account state.

```text
Rule:  (user.department -eq "Revenue Cycle")

Disabled contractor still has:
       department = "Revenue Cycle"
                    |
                    v
       Rule still matches
                    |
                    v
       Membership persists indefinitely
```

The script's own documentation compounded the error. It claimed dynamic groups "drop automatically once the account is disabled."

That claim was false. The comment was corrected.

### Impact

An access review scoped to those groups would list a terminated contractor as a current member.

Membership reports would overstate active headcount.

Any downstream system consuming group membership would still grant access.

### Fix

Every dynamic rule was rewritten to test account state:

```text
Before:
(user.department -eq "Revenue Cycle")

After:
(user.accountEnabled -eq true) -and (user.department -eq "Revenue Cycle")
```

After reevaluation, the terminated account dropped from all three groups.

### Secondary defect found during the fix

The session revocation step failed:

```text
FAILED: The term 'Revoke-MgUserSignInSession' is not recognized
```

The cmdlet lives in `Microsoft.Graph.Users.Actions`, which was not among the modules installed.

The script's error handling worked correctly. It logged `SessionRevocationFailed` and continued rather than aborting mid-termination. But the revocation did not occur until the module was installed and the command re-run.

### Lesson

> Disabling an account is not the same as removing its access.
>
> If a revocation process depends on group membership dropping rather than on token revocation, there is a window, and the window does not close on its own.

---

## 🔑 Bonus Finding — Device Code Authentication Stopped Working Mid-Build

**Date:** 2026-08-08
**Type:** Platform security control

### Symptom

Authentication that had worked the previous day began failing:

```text
Error Code: 530035
Your sign-in was successful but you don't have permission to access this resource.
App name: Microsoft Graph Command Line Tools
```

### Root cause

As of **July 1, 2026**, all new Microsoft Entra tenants block device code flow as part of Security Defaults.

The control exists because device code flow has been actively abused in phishing campaigns. Attackers trick a victim into entering a code on their own device and harvest the resulting token.

This tenant was created 2026-08-07, five weeks after the cutoff.

The enforcement rollout is progressive, which is why the same command worked one day and failed the next.

### Fix

Migrated from device code flow to interactive authentication.

**Security Defaults was not disabled to work around the block.**

It was later disabled for a different and planned reason. Security Defaults and Conditional Access are mutually exclusive, and the project required Conditional Access policies.

That transition is documented separately in `conditional-access-baseline.md`, including the gap period.

### Lesson

```text
A security control blocks the workflow
              |
              v
Change the workflow
              |
              v
Not the control
```

---

## What This Log Demonstrates

Eight defects. Three of them in this project's own design.

```text
A scanner that reported clean while checking nobody
A rule that could not match the risk it described
A termination that left access in place
```

None of these produced an error message.

All three were found by building the tooling, running it against a live tenant, and reading the output carefully enough to notice when a green result did not make sense.

> The most dangerous failures in identity governance are the quiet ones.
