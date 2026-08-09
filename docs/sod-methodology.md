# ⚠️ Segregation of Duties Methodology

How the conflict matrix was designed, why it is stored as data rather than code, what the detection engine does, and what version 1.0 cannot do.

---

## What Segregation of Duties Actually Means

Segregation of Duties is not about limiting how much access a person has.

It is about making sure no single person can complete a sensitive process end to end without a second party involved.

```text
One person creates the charge
One person submits it to the payer
                |
                v
        Two sets of eyes

One person does both
                |
                v
        No independent check exists
```

The individual permissions are not the problem. Charge entry is a legitimate job function. Claims submission is a legitimate job function.

The **combination** is the control failure.

---

## Why Access Reviews Miss This

A standard access review presents one group at a time.

```text
Review campaign: ENT-Charge-Entry
        Carl Ndiaye - approve or revoke?
                |
                v
        Reviewer sees: a charge entry specialist
                        with charge entry access
                |
                v
        Correct. Approve.


Review campaign: ENT-Claims-Submission
        Carl Ndiaye - approve or revoke?
                |
                v
        Reviewer sees: a revenue cycle employee
                        with claims access
                |
                v
        Plausible. Approve.
```

Both decisions are defensible in isolation.

Neither reviewer sees the other group.

The conflict survives the review process intact, and the review produces an audit artifact stating that the access was examined and approved.

> An access review that examines entitlements individually cannot detect a conflict that only exists in combination.

---

## Design Principle: The Matrix Is Data

The conflict matrix lives in `policy/sod-matrix.json`, not inside the PowerShell.

### Why this matters

```text
Matrix hardcoded in PowerShell
                |
                v
    Every policy change is a code change
                |
                v
    Requires someone who can read PowerShell
                |
                v
    Compliance waits on engineering


Matrix stored as JSON
                |
                v
    Policy changes are data changes
                |
                v
    Compliance analyst edits a file
                |
                v
    Detection engine is untouched
```

In a real organization, the people who define SoD policy are compliance and internal audit staff. The people who write PowerShell are not.

Coupling those two roles is a process failure disguised as a technical decision.

### Rule structure

Each rule carries everything needed to act on a finding:

```json
{
  "id": "SOD-001",
  "name": "Charge Entry + Claims Submission",
  "groupA": "ENT-Charge-Entry",
  "groupB": "ENT-Claims-Submission",
  "severity": "Critical",
  "riskStatement": "A single identity can both originate a patient charge and submit it to a payer, with no independent review between creation and billing.",
  "controlMapping": ["SOX-ITGC-Access", "HIPAA-164.312(a)(1)", "FCA-Billing-Integrity"],
  "remediation": "Revoke the non-primary entitlement. If cross-coverage is operationally required, provision time-bound access via access package with mandatory expiration."
}
```

### Why each field exists

| Field            | Purpose                                                              |
| ---------------- | -------------------------------------------------------------------- |
| `severity`       | Lets findings be triaged rather than treated as a flat list          |
| `riskStatement`  | Explains the business risk to a reviewer who is not technical        |
| `controlMapping` | Connects the finding to an audit framework an assessor will ask about |
| `remediation`    | Tells the recipient what to do, not just that something is wrong     |

A finding that says "conflict detected" creates work. A finding that says what the risk is, which control it maps to, and how to fix it creates a decision.

---

## The Five Rules

| ID      | Conflict                                   | Severity    | Control Mapping                                        |
| ------- | ------------------------------------------ | ----------- | ------------------------------------------------------ |
| SOD-001 | Charge Entry + Claims Submission           | 🔴 Critical | SOX-ITGC-Access, HIPAA-164.312(a)(1), FCA-Billing      |
| SOD-002 | Clinical Documentation + Medical Coding    | 🟠 High     | FCA-Billing-Integrity, CMS-Coding-Compliance           |
| SOD-003 | Charge Entry + Payment Posting             | 🔴 Critical | SOX-ITGC-Access, COSO-Control-Activities               |
| SOD-004 | Systems Administration + Full PHI Access   | 🟠 High     | HIPAA-164.502(b), HIPAA-164.312(a)(1), NIST-AC-6       |
| SOD-005 | Internal Audit + Operational Transaction   | 🟡 Medium   | IIA-Standard-1100, SOX-ITGC-Access                     |

### Why these five

Each maps to a documented fraud or compliance risk in healthcare revenue cycle operations.

**SOD-001** is the primary control failure in healthcare billing fraud. Create the charge, bill the payer, no independent review in between.

**SOD-002** is upcoding. A clinician who documents the encounter and assigns its billing code can inflate reimbursement with no second party to detect the discrepancy.

**SOD-003** is cash misappropriation. Create a charge, then post the payment or write-off against it. There is no reconciliation break.

**SOD-004** is HIPAA minimum necessary. Infrastructure administration does not require clinical record content. Standing PHI access for sysadmins is access without a business justification.

**SOD-005** is audit independence. Internal audit personnel with write access to systems within their audit scope cannot render an independent opinion on those systems.

---

## Detection Engine Design

### Transitive membership, not direct

```powershell
Get-MgUserTransitiveMemberOf
```

Direct membership queries miss nested groups.

```text
User
  |
  +-- RBAC-Clinical-Staff
              |
              +-- (nested) ENT-Medical-Coding

Direct query result:  RBAC-Clinical-Staff
Transitive result:    RBAC-Clinical-Staff, ENT-Medical-Coding
```

Nesting is how access accumulates without appearing on anyone's report. A detection engine that only reads direct membership will report clean on a directory full of inherited entitlements.

### Deduplication on the normalized group pair

Two rules can describe the same group combination in opposite order.

SOD-003 pairs `ENT-Charge-Entry` with `ENT-Payment-Posting`.
SOD-005 pairs `ENT-Payment-Posting` with `ENT-Charge-Entry`.

Without deduplication, one user with both entitlements produces two findings for one condition.

```text
Naive:
  SOD-F002  Ivan Petrov  SOD-003
  SOD-F003  Ivan Petrov  SOD-005
        |
        v
  Finding count inflated. Same condition counted twice.

Deduplicated:
  SOD-F002  Ivan Petrov  SOD-003, SOD-005
        |
        v
  One condition, one finding, both rules named.
```

The group pair is sorted alphabetically before comparison, so order does not matter.

The matched rules are still listed, which makes the policy overlap visible instead of hiding it. Two rules describing the same condition is itself worth knowing about.

### Severity escalation on overlap

When two rules match the same pair and disagree on severity, the higher severity wins.

SOD-003 is Critical. SOD-005 is Medium. The merged finding reports Critical.

A conflict is as serious as the most serious rule that describes it.

### Exit codes

```text
0 = no violations
1 = violations found
```

This is what makes the scanner schedulable. A CI job, scheduled task, or monitoring system can act on the result without parsing output.

---

## The Tuning Cycle

Rule design is iterative. This is the part most detection projects skip.

### Initial run: 3 findings

```text
SOD-001  Critical  Charge Entry + Claims Submission       matches: 1
SOD-002  High      Clinical Documentation + Coding        matches: 1
SOD-003  Critical  Charge Entry + Payment Posting         matches: 1
SOD-004  High      Systems Administration + PHI Access    matches: 0
SOD-005  Medium    Internal Audit + Operational Access    matches: 1
```

SOD-004 matched nothing, while a systems administrator with standing PHI access was present in the directory.

### Diagnosis

SOD-004 paired `ENT-PHI-Full-Access` against `RBAC-Site-Marietta`.

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

### The deeper cause

The rule could not be written correctly because the directory had no IT group.

Original dynamic groups:

```text
RBAC-Clinical-Staff
RBAC-Clinical-Prescribers
RBAC-RevCycle-Staff
RBAC-HIM-Staff
RBAC-Contractors-All
RBAC-Site-Marietta
```

Nothing represented Information Technology as a role.

The site group was the closest available proxy, and it was wrong.

### Remediation

Created the missing group:

```text
RBAC-IT-Staff
(user.accountEnabled -eq true) -and (user.department -eq "Information Technology")
```

Changed one line in the matrix:

```text
"groupB": "RBAC-Site-Marietta"    becomes    "groupB": "RBAC-IT-Staff"
```

### Result: 4 findings

```text
SOD-004  High  Systems Administration + Full PHI Access   matches: 1
```

### The lesson

> SoD rule quality is capped by group model quality.
>
> You cannot express a control that your directory cannot represent.

This is why most of the effort in a real SoD program goes into refining the entitlement model and tuning rules, not into writing detection code. The code is the easy part.

**Evidence:** `sod-findings-20260808-194650.csv` (3 findings) and `sod-findings-20260808-195416.csv` (4 findings).

---

## 🚫 Known Limitation: The v1.0 Schema Cannot Express Role Conditions

This is the most important section in this document.

### What was missed

Five conflicts were deliberately planted. Four were detected.

The fifth was **Gerald Mbeki**, an Internal Auditor holding `ENT-Payment-Posting`.

### Why it was missed

SOD-005 was written as a group pair:

```text
groupA: ENT-Payment-Posting
groupB: ENT-Charge-Entry
```

That describes **Ivan Petrov's** conflict, not Gerald's.

Gerald holds Payment-Posting alone. He does not hold Charge-Entry. The rule does not match him.

### What the rule was supposed to say

```text
Role     = Internal Auditor
   AND
Access   = any operational transaction entitlement
```

That is a **role plus access** condition, not a **group plus group** condition.

The v1.0 JSON schema has exactly two slots: `groupA` and `groupB`. Both must be groups. There is no field for an attribute condition, a job title, or a wildcard entitlement class.

**The schema cannot express the rule.**

### Why it was not quietly fixed

Two workarounds were available:

```text
Option A: Create an RBAC-Compliance group and pair it against
          ENT-Payment-Posting
                |
                v
          Catches Gerald. Also catches any future compliance
          staff member holding that one specific entitlement.
          Misses them if they hold a different one.

Option B: Extend the schema to support attribute conditions
                |
                v
          Correct. Requires redesigning the rule format
          and the evaluation engine.
```

Option A would have produced a green result while leaving the underlying limitation in place. The rule would appear to work and would fail silently on the next similar case.

Option B is correct but out of scope for v1.0.

The gap was documented instead.

> A detection rate of 4 out of 5 with a diagnosed cause is more credible than 5 out of 5 achieved by writing a rule around one specific test case.

### Proposed v1.1 schema

```json
{
  "id": "SOD-005",
  "name": "Internal Audit + Operational Transaction Access",
  "conditionA": {
    "type": "attribute",
    "property": "department",
    "operator": "equals",
    "value": "Compliance"
  },
  "conditionB": {
    "type": "groupPattern",
    "pattern": "ENT-*"
  },
  "severity": "Medium"
}
```

That would express: anyone in Compliance holding any entitlement group.

It requires:

```text
A condition type discriminator (attribute vs. group vs. pattern)
An operator vocabulary (equals, startsWith, matches, in)
Wildcard matching against group names
Evaluation logic that resolves both condition types
```

Deferred to v1.1. Recorded here so the gap is a known limitation rather than an undiscovered one.

---

## What Detection Cannot Do

Detection finds conflicts. It does not resolve them.

```text
Scanner reports: Carl Ndiaye holds two conflicting entitlements
                        |
                        v
        Which one should be removed?
                        |
                        v
        Depends on his current job function,
        whether the coverage arrangement is still active,
        who authorized it, and what breaks if it is revoked.
                        |
                        v
        That is a business decision, not a script decision.
```

This is why `Invoke-Mover.ps1` flags orphaned entitlements rather than removing them. A script that auto-revokes will eventually revoke something operationally necessary, and the resulting outage will end the program.

The correct output of a detection engine is a **decision-ready finding**, not an action.

---

## Running the Scanner

```powershell
# Console output only
.\Test-SoDConflicts.ps1

# With CSV and JSON evidence export
.\Test-SoDConflicts.ps1 -Format All

# Against a different matrix
.\Test-SoDConflicts.ps1 -MatrixPath '..\policy\sod-matrix-v2.json' -Format All
```

### Output

```text
Console  Grouped by severity, with risk statement and remediation per finding
CSV      One row per finding, suitable for import into a GRC platform
JSON     Full scan metadata plus findings, suitable for pipeline consumption
```

Every export is timestamped. The evidence directory in this repository contains the actual output from every run performed during development, including the failed ones.

---

## Summary

```text
Policy stored as data, not code
Transitive membership, not direct
Deduplicated on normalized group pairs
Severity escalates on rule overlap
Findings carry risk, control mapping, and remediation
Exit codes support scheduling
Detection reports; humans decide
Known limitations documented, not hidden
```

The engine took a few hours to write.

The rule tuning, the group model correction, and the honest accounting of what the schema cannot express took longer, and matter more.
