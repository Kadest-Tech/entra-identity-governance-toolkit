# 🔐 Conditional Access Baseline

Identity governance decides **what** access a person should have.

Conditional Access decides **how** that access may be used.

This document covers the three enforced policies in the lab tenant, the reasoning behind each one, the break-glass account that protects against lockout, and an honest account of the period when the tenant had no authentication controls at all.

---

## Policy Summary

| Policy   | Purpose                          | State       | Excludes    |
| -------- | -------------------------------- | ----------- | ----------- |
| **CA01** | Require MFA for all users        | ✅ Enabled  | Break-glass |
| **CA02** | Block legacy authentication      | ✅ Enabled  | Break-glass |
| **CA03** | Require MFA for privileged roles | ✅ Enabled  | Break-glass |

All three are **enabled**, not report-only.

---

## 🧯 Prerequisite: The Break-Glass Account

Before any Conditional Access policy was created, an emergency access account was provisioned.

```text
breakglass@<tenant>.onmicrosoft.com
Role:     Global Administrator
Excluded: All three Conditional Access policies
Password: Randomly generated, 32 characters, not stored in the repository
```

### Why this comes first

A Conditional Access misconfiguration can lock every administrator out of a tenant permanently.

```text
Policy requires MFA for all users
              |
              v
Admin has no MFA method registered
              |
              v
Admin cannot satisfy the policy
              |
              v
Nobody can sign in
              |
              v
Nobody can fix the policy
```

There is no self-service recovery from that state. It requires a Microsoft support case.

> Create the escape hatch before you build the door.

### Known deviation

The break-glass account was created with `department = Information Technology`, which places it inside the `RBAC-IT-Staff` dynamic group.

A production break-glass account should sit outside all dynamic groups so that no attribute-driven rule can grant or revoke its access unexpectedly.

This was accepted as a lab compromise rather than introducing a separate attribute scheme for one account. It is recorded here rather than left undocumented.

---

## CA01 — Require MFA for All Users

| Setting          | Value                              |
| ---------------- | ---------------------------------- |
| Users included   | All users                          |
| Users excluded   | Break Glass Emergency Access       |
| Target resources | All resources (formerly All cloud apps) |
| Grant control    | Require multifactor authentication |
| State            | Enabled                            |

### The problem it solves

A password alone is a single factor. Credential theft through phishing, reuse, or breach dumps is the most common initial access vector in identity attacks.

Requiring a second factor means a stolen password is not sufficient by itself.

### Why the administrator is not excluded

When creating this policy, the Entra portal displays a warning and offers two options:

```text
[ ] Exclude current user from this policy
[X] I understand that my account will be impacted. Proceed anyway.
```

The second option was chosen deliberately.

```text
A policy that requires MFA for all users
          but exempts a Global Administrator
                        |
                        v
        Protects everyone except the account
        with the most access in the tenant
```

An auditor writes that up as a finding. The break-glass account exists so that exempting a working administrator is unnecessary.

### Operational impact

Every user must register an MFA method before signing in. In this lab that was one account. In production this requires a registration campaign before enforcement, or users are locked out on day one.

---

## CA02 — Block Legacy Authentication

| Setting          | Value                                                  |
| ---------------- | ------------------------------------------------------ |
| Users included   | All users                                              |
| Users excluded   | Break Glass Emergency Access                           |
| Target resources | All resources                                          |
| Condition        | Client apps: Exchange ActiveSync clients, Other clients |
| Grant control    | Block access                                           |
| State            | Enabled                                                |

### Why CA01 alone is not enough

Legacy authentication protocols cannot perform modern authentication.

That means they **cannot present an MFA prompt**.

```text
POP  |  IMAP  |  SMTP AUTH  |  older Office clients
                    |
                    v
        No support for modern auth
                    |
                    v
        No MFA challenge is possible
```

The bypass:

```text
Attacker obtains a valid password
              |
              v
Authenticates over a legacy protocol
              |
              v
MFA is never requested
              |
              v
CA01 is bypassed entirely
```

Blocking legacy authentication closes that path. Without CA02, CA01 is a control with a documented workaround.

### Operational impact

Any application or device still using basic authentication will stop working immediately. In production this requires a sign-in log review to identify affected clients before enforcement.

---

## CA03 — Require MFA for Privileged Roles

| Setting          | Value                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| Users included   | Directory roles: Global Admin, Privileged Role Admin, User Admin, Security Admin   |
| Users excluded   | Break Glass Emergency Access                                                       |
| Target resources | All resources                                                                      |
| Grant control    | Require multifactor authentication                                                 |
| Session control  | Sign-in frequency: every time                                                       |
| State            | Enabled                                                                            |

### Why this overlaps CA01

CA01 already covers every user, including administrators. The overlap is deliberate.

```text
If CA01 is ever narrowed, disabled, or misconfigured
                    |
                    v
    Privileged accounts remain protected by CA03
```

Defense in depth applied to policy design, not just to infrastructure. The accounts with the most access are covered by two independent controls rather than one.

### The control CA01 does not have

```text
Sign-in frequency: every time
```

By default, a satisfied MFA claim persists for the lifetime of the session token. An administrator who authenticated this morning may still hold a valid session this evening, including from a device that has since been compromised.

Forcing reauthentication on every sign-in limits how long a stolen token remains useful for privileged operations.

### Operational impact

Administrators reauthenticate frequently. This is friction by design, and it applies only to accounts holding the four targeted roles.

---

## 📉 The Security Defaults Gap

This section documents a period during which the tenant had no authentication controls.

### Why Security Defaults was disabled

Entra ID **Security Defaults** and **Conditional Access** are mutually exclusive. A tenant can run one or the other, never both.

```text
Security Defaults              Conditional Access
-----------------              ------------------
Single on/off switch           Scoped policies
No exclusions                  Break-glass exclusions
No conditions                  Client app, location, risk
No documentation               Documented rationale per policy
```

The project required Conditional Access. Security Defaults had to be turned off first.

### The timeline

```text
2026-08-08 ~19:30
    Security Defaults disabled
    Reason: required before Conditional Access policies can be created
    Tenant state: NO authentication controls enforced
              |
              |   Gap period: approximately 1 hour 50 minutes
              |   35 identities with no MFA requirement
              |   No legacy authentication block
              |
              v
2026-08-08 ~21:20
    CA01, CA02, CA03 created in report-only mode
    Break-glass account provisioned and excluded
    Administrator MFA method registered
              |
              v
2026-08-08 ~21:25
    All three policies switched to Enabled
    Tenant state: authentication controls enforced
    Gap closed
```

### Was the gap necessary?

Partly.

Disabling Security Defaults was unavoidable, since the two systems cannot coexist. But the gap was longer than it needed to be.

A tighter sequence would have been:

```text
1. Register administrator MFA method       (while Security Defaults is still on)
2. Create break-glass account              (while Security Defaults is still on)
3. Disable Security Defaults
4. Create and enable all three policies    (immediately)
```

Steps 1 and 2 were performed after step 3 rather than before. That ordering extended the exposure window without benefit.

### Why it is documented rather than omitted

The tenant is a lab with 34 synthetic identities and no real data, so the actual risk was negligible.

The pattern is not.

```text
A control is disabled to enable a migration
                    |
                    v
        The replacement takes longer than planned
                    |
                    v
        The gap is never recorded
                    |
                    v
        Nobody knows the exposure window existed
```

That is a real change-management failure, and it is invisible unless someone writes it down.

> An undocumented control gap is indistinguishable from no gap at all.

---

## ⚠️ A Misleading Signal Worth Knowing

During enforcement testing, an MFA prompt appeared while all three policies were still in report-only mode.

That prompt was **not** produced by these policies.

Microsoft enforces mandatory MFA for Azure portal sign-ins independently of tenant configuration. A second phase extends that enforcement to Azure CLI, Azure PowerShell, IaC tools, and MSAL-based clients.

```text
MFA prompt observed
        |
        v
Assumption: "my policy is working"
        |
        v
Reality: platform-level enforcement, unrelated to the policy
        |
        v
Policies were still report-only and enforcing nothing
```

The policy state was only confirmed by querying it directly:

```powershell
Get-MgIdentityConditionalAccessPolicy | Select-Object DisplayName, State
```

> Observing the expected behavior is not proof that your control produced it.

---

## 🔧 What I Would Do Next in Production

The three policies here are a baseline, not a finished program. What follows is what the next iteration would require.

### 1. Run in report-only long enough to see the blast radius

Report-only mode logs what a policy **would** do without enforcing it. In this lab the policies went to enabled within minutes because the tenant had one active user.

In production, a policy targeting all users needs at least a full business cycle in report-only. The sign-in logs then show:

```text
Which users would have been blocked
Which applications would have broken
Which legacy clients are still in use
Which service accounts have no MFA path
```

Enforcing before reading that data is how a Monday morning outage happens.

### 2. Identify service accounts and workload identities first

CA01 targets all users. Service accounts are users.

```text
Service account with a password and no MFA method
                    |
                    v
        CA01 blocks it on first sign-in
                    |
                    v
        Whatever it automated stops working
```

Production sequence: inventory non-human identities, migrate them to managed identities or workload identity federation, and exclude what remains until migration completes.

### 3. Add location and risk conditions

The current policies apply everywhere, always. Refinements worth adding:

| Addition                          | Purpose                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| Named locations                   | Different requirements for corporate network vs. unknown origin |
| Sign-in risk conditions           | Step-up authentication when Identity Protection flags a session |
| Device compliance requirement     | Restrict access to managed devices for sensitive applications   |
| Impossible travel / anomaly rules | Block sessions that cannot be geographically legitimate         |

Risk-based conditions require Entra ID P2 and Identity Protection, both available in this tenant but not implemented here.

### 4. Replace the standing PHI access finding with PIM

SoD finding SOD-004 identified a systems administrator holding standing `ENT-PHI-Full-Access`.

The Conditional Access answer to that finding is Privileged Identity Management:

```text
Standing membership in ENT-PHI-Full-Access
                    |
                    v
Eligible membership, activated on request
                    |
                    v
Time-bound, justification required, alerts on activation
```

That converts a permanent entitlement into an auditable event. Not implemented here, but it is the correct remediation for that finding.

### 5. Monitor break-glass usage

A break-glass account should never sign in during normal operations. Any authentication by that account is either an emergency or a compromise.

Production requirements:

```text
Alert on any break-glass sign-in
Route the alert to security operations, not to a shared mailbox
Review the account quarterly: still needed, still excluded, password rotated
Store the credential in a physically controlled location
```

An unmonitored break-glass account is a permanently privileged, MFA-exempt identity that nobody is watching.

### 6. Version the policies as code

These policies were created through the portal. Portal-created policies have no change history, no review process, and no rollback.

```text
Export policies to JSON
Store in source control
Review changes through pull request
Deploy through pipeline
```

That gives Conditional Access the same change control as the SoD matrix in this repository, which is already stored as data rather than embedded in code.

---

## Verification

Current policy state can be confirmed at any time:

```powershell
Get-MgIdentityConditionalAccessPolicy |
    Select-Object DisplayName, State |
    Format-Table -AutoSize
```

Expected output:

```text
DisplayName                            State
-----------                            -----
CA01 - Require MFA for all users       enabled
CA02 - Block legacy authentication     enabled
CA03 - Require MFA for privileged roles enabled
```

---

## Summary

Three policies. One break-glass account. One documented gap period of approximately 1 hour 50 minutes.

The policies are a baseline appropriate to a lab, not a production Conditional Access program.

What is transferable is the reasoning:

```text
Build the recovery path before the control
Do not exempt the accounts that need the control most
Understand why a second policy exists to close the first policy's bypass
Verify enforcement by querying state, not by observing behavior
Record the gap
```
