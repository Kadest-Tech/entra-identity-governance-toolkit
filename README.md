\# 🛡️ Entra ID Identity Governance Toolkit



!\[Microsoft Entra ID](https://img.shields.io/badge/Microsoft%20Entra-ID-0078D4?logo=microsoft\\\&logoColor=white)

!\[PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell\\\&logoColor=white)

!\[Microsoft Graph](https://img.shields.io/badge/Microsoft-Graph-0078D4?logo=microsoft\\\&logoColor=white)

!\[IAM](https://img.shields.io/badge/Focus-IAM%20%26%20Identity%20Governance-success)

!\[Environment](https://img.shields.io/badge/Environment-Live%20Lab%20Tenant-orange)



> \*\*A hands-on Identity and Access Management (IAM) project built in a live Microsoft Entra ID tenant.\*\*



This project demonstrates:



\* 🔐 \*\*Role-Based Access Control (RBAC)\*\*

\* 👤 \*\*Joiner, Mover, and Leaver (JML) automation\*\*

\* ⚠️ \*\*Segregation of Duties (SoD) monitoring\*\*

\* 🎫 \*\*Entitlement management\*\*

\* 🛡️ \*\*Conditional Access\*\*

\* 📊 \*\*Access governance and audit evidence\*\*

\* ⚙️ \*\*PowerShell automation\*\*

\* 🌐 \*\*Microsoft Graph\*\*

\* ✅ \*\*Least-privilege access\*\*



The environment models the identity system of a fictional regional healthcare organization called \*\*Northlake Regional Health\*\*.



No real employees, patients, or Protected Health Information (PHI) are used.



\---



\## 🚀 30-Second Project Summary



I built an Entra ID identity governance lab that models how a healthcare organization could manage employee access.



The system uses employee information such as:



\* Department

\* Job title

\* Office location

\* Employee type



to automatically place employees into the correct \*\*RBAC groups\*\*.



Sensitive access is handled separately through assigned \*\*entitlement groups\*\*.



I then built PowerShell governance tools that scan the entire directory for dangerous access combinations.



\### Example



An employee might have:



\*\*Charge Entry Access\*\*



and also:



\*\*Claims Submission Access\*\*



Each permission may look acceptable when reviewed by itself.



Together, they create a serious \*\*Segregation of Duties conflict\*\*.



My scanner detects that combination automatically.



\---



\# 🎯 The Problem This Project Solves



Traditional access reviews often look at \*\*one group at a time\*\*.



That creates a visibility problem.



Imagine this:



```text

Employee

&#x20;  │

&#x20;  ├── ENT-Charge-Entry

&#x20;  │

&#x20;  └── ENT-Claims-Submission

```



A reviewer looking only at `ENT-Charge-Entry` may approve it.



Another reviewer looking only at `ENT-Claims-Submission` may also approve it.



Neither reviewer sees the full picture.



But together, those permissions create a dangerous combination.



In a healthcare billing environment, that could increase the risk of:



\* Fraud

\* Unauthorized billing

\* Improper payments

\* Excessive access

\* Compliance violations



\### My solution



Instead of checking only when someone requests access, the toolkit scans the \*\*entire directory continuously\*\*.



The rules are stored in a separate policy file:



```text

policy/sod-matrix.json

```



This means a compliance analyst can change the policy without rewriting the PowerShell detection engine.



\---



\# 🏥 Lab Environment



| Area                            | Configuration                                 |

| ------------------------------- | --------------------------------------------- |

| \*\*Organization\*\*                | Northlake Regional Health                     |

| \*\*Seeded Identities\*\*           | 34 synthetic users + 4 admin/service accounts |

| \*\*Departments\*\*                 | 7                                             |

| \*\*Sites\*\*                       | 2                                             |

| \*\*Tenant\*\*                      | Microsoft Entra ID P2                         |

| \*\*Dynamic RBAC Groups\*\*         | 7                                             |

| \*\*Assigned Entitlement Groups\*\* | 6                                             |

| \*\*Total Access Groups\*\*         | 13                                            |

| \*\*Access Packages\*\*             | 1 catalog, 1 package with approval workflow   |

| \*\*Conditional Access Policies\*\* | 3 enforced policies                           |

| \*\*PowerShell Scripts\*\*          | 7                                             |

| \*\*Evidence\*\*                    | 16+ timestamped CSV/JSON exports              |



\### Departments



\* 🩺 Clinical

\* 💵 Revenue Cycle

\* 📁 Health Information Management

\* 💻 Information Technology

\* ✅ Compliance

\* 📊 Finance

\* 👥 Human Resources



\---



\# 🏗️ Architecture



```mermaid

flowchart LR



&#x20;   A\["HR Attributes<br/>Department<br/>Job Title<br/>Location<br/>Employee Type"]



&#x20;   B\["Dynamic RBAC Groups<br/>RBAC-\*"]



&#x20;   C\["Baseline Access"]



&#x20;   D\["Access Package<br/>Request + Approval"]



&#x20;   E\["Assigned Entitlement Groups<br/>ENT-\*"]



&#x20;   F\["Sensitive Access"]



&#x20;   G\["Test-SoDConflicts.ps1"]



&#x20;   H\["sod-matrix.json<br/>Policy Rules"]



&#x20;   I\["SoD Findings"]



&#x20;   J\["CSV / JSON<br/>Audit Evidence"]



&#x20;   A --> B

&#x20;   B --> C



&#x20;   D --> E

&#x20;   E --> F



&#x20;   C --> G

&#x20;   F --> G

&#x20;   H --> G



&#x20;   G --> I

&#x20;   I --> J

```



\---



\# 🔑 The Most Important Design Choice



The project separates access into \*\*two types\*\*.



\## 1️⃣ Dynamic RBAC Groups



Dynamic groups provide normal job-based access.



For example:



```text

Department = Clinical

&#x20;       ↓

RBAC-Clinical-Staff

&#x20;       ↓

Clinical baseline access

```



Nobody manually places the employee into the group.



Entra ID calculates membership from employee attributes.



If the employee changes departments, the group membership changes automatically.



\### Result



> \*\*Change the employee's attributes, and their baseline access follows them.\*\*



\---



\## 2️⃣ Assigned Entitlement Groups



Sensitive permissions are different.



These use manually assigned `ENT-\*` groups.



Examples:



```text

ENT-Charge-Entry

ENT-Claims-Submission

ENT-Payment-Posting

ENT-Medical-Coding

ENT-Record-Amendment

ENT-PHI-Full-Access

```



These permissions may be granted because of:



\* Temporary coverage

\* Special projects

\* Month-end work

\* Business exceptions

\* Emergency access



The problem is that these permissions can remain after the employee's job changes.



That is where \*\*Segregation of Duties problems can appear\*\*.



\---



\# 🎫 Entitlement Management



If sensitive access is going to be granted by hand, the request itself needs governance.



Otherwise access gets handed out in a chat message and never comes back.



I built an \*\*access package\*\* in Entra Entitlement Management to model the correct path.



\## Catalog



```text

Northlake Revenue Cycle

```



The catalog contains three billing entitlements:



```text

ENT-Charge-Entry

ENT-Claims-Submission

ENT-Medical-Coding

```



An access package can only grant resources that exist inside its catalog.



That is a scoping control, not a technicality.



\---



\## Access Package



```text

Temporary Charge Entry Access

```



| Setting                    | Configuration                             |

| -------------------------- | ----------------------------------------- |

| \*\*Who can request\*\*        | Members of `RBAC-RevCycle-Staff`          |

| \*\*Approval required\*\*      | Yes                                       |

| \*\*Approver\*\*               | The requester's manager                   |

| \*\*Fallback approver\*\*      | Latoya Simms (Billing Manager)            |

| \*\*Decision window\*\*        | 7 days                                    |

| \*\*Justification required\*\* | Requester and approver                    |

| \*\*Assignment expires\*\*     | 90 days                                   |

| \*\*Extension allowed\*\*      | No                                        |

| \*\*Access review\*\*          | Quarterly, manager attests                |

| \*\*If reviewer ignores it\*\* | 🔴 \*\*Remove access\*\*                      |



\---



\## 🚨 The Most Important Setting



The last row matters more than it looks.



When an access review runs and the reviewer never responds, the system has two options:



```text

Option A: Keep the access

&#x20;         ↓

Silence becomes approval

&#x20;         ↓

Stale access lives forever





Option B: Remove the access

&#x20;         ↓

Silence becomes revocation

&#x20;         ↓

Access must be actively defended

```



I chose \*\*Option B\*\*.



> If nobody is willing to attest to the access, the access should not survive.



\---



\## What This Section Does Not Claim



The access package is \*\*configured\*\*, including the approval workflow and the quarterly review schedule.



The review has not completed a full cycle in this lab.



I am documenting the control design, not claiming a completed recertification campaign.



\---



\## Why This Matters to the SoD Findings



Every SoD conflict in this project came from access granted \*\*outside\*\* this process.



```text

Correct path:

Request → Manager approval → 90-day expiry → Quarterly review



Actual path that created the conflicts:

Someone added the user to the group

```



The access package shows what governed access looks like.



The scanner shows what happens when governance is skipped.



\---



\# 👤 Joiner, Mover, Leaver Testing



I tested three major identity lifecycle events against the live tenant.



Each test created timestamped evidence.



| Event         | Result                                                             | Why It Matters                                                                                                            |

| ------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |

| 🟢 \*\*Joiner\*\* | 1 baseline group, 0 entitlements                                   | The employee receives only the access required by their attributes. Sensitive entitlements are not automatically granted. |

| 🟡 \*\*Mover\*\*  | Gained 2 dynamic groups, lost 1, but kept `ENT-Medical-Coding`     | A normal department transfer created a new SoD conflict even though nobody requested new sensitive access.                |

| 🔴 \*\*Leaver\*\* | Account disabled and tokens revoked, but 3 dynamic groups remained | Disabling an account does not automatically remove dynamic memberships unless the group rule checks the account state.    |



\---



\# 💡 Why the Mover Test Matters



This became one of the most important findings in the project.



The employee transfer was processed correctly.



Nobody made a bad access request.



Nobody approved dangerous access.



Nobody manually created the conflict.



The employee simply:



```text

Changed jobs

&#x20;     ↓

Dynamic access changed

&#x20;     ↓

Old entitlement remained

&#x20;     ↓

New SoD conflict appeared

```



\### This demonstrates why request-time SoD checking is not enough.



A system that checks conflicts only when users request access would have missed this problem.



The conflict appeared \*\*after a normal role change\*\*.



That is why continuous directory-wide detection matters.



\---



\# ⚠️ Segregation of Duties Detection



I deliberately planted five dangerous access combinations using realistic business explanations.



Examples included:



\* Leave coverage

\* Month-end backfill

\* EHR migration

\* Documentation projects



These are realistic situations where temporary access can slowly become permanent access.



A sixth conflict appeared naturally during the \*\*Mover test\*\*.



\---



\# 🔎 Final Detection Results



\### Final Scan



```text

Identities scanned: 38

Policy rules tested: 5

Findings: 5

Scan time: 4.9 seconds

```



| Identity            | Conflict                         |    Severity | How It Happened                              |

| ------------------- | -------------------------------- | ----------: | -------------------------------------------- |

| \*\*Carl Ndiaye\*\*     | Charge Entry + Claims Submission | 🔴 Critical | Leave coverage access was never removed      |

| \*\*Ivan Petrov\*\*     | Charge Entry + Payment Posting   | 🔴 Critical | Month-end backfill access remained           |

| \*\*Blake Ferris\*\*    | Sysadmin + Full PHI Access       |     🟠 High | EHR migration access became standing access  |

| \*\*Nina Kowalski\*\*   | Prescriber + Medical Coding      |     🟠 High | Documentation project had no expiration date |

| \*\*Grace Lindqvist\*\* | Prescriber + Medical Coding      |     🟠 High | Appeared automatically after a role transfer |



\---



\# 🧪 Detection Accuracy



Of the \*\*5 manually planted conflicts\*\*, the scanner found \*\*4\*\*.



The fifth was intentionally documented as a limitation instead of quietly changing the results.



\### Missed case



```text

Gerald Mbeki

Internal Auditor + Operational Access

```



Version 1.0 of the policy matrix checks conflicts between \*\*group pairs\*\*.



Gerald's conflict depends on a person's \*\*role plus their access\*\*, which the current JSON schema cannot express.



Instead of hiding the gap, I documented it.



📄 See:



```text

docs/sod-methodology.md

```



> A security control should clearly explain what it \*\*cannot\*\* detect, not just what it can detect.



\---



\# 🧠 Key Engineering Decisions



\## 📄 1. Policy Is Data, Not Code



The SoD rules are stored here:



```text

policy/sod-matrix.json

```



Each rule contains information such as:



\* Severity

\* Risk statement

\* Conflicting groups

\* Control mapping

\* Remediation guidance



Control mappings include:



\* SOX ITGC

\* HIPAA 164.312(a)(1)

\* HIPAA 164.502(b)

\* NIST AC-6

\* Billing integrity controls



\### Why?



Compliance rules change.



If the conflict matrix were hardcoded into PowerShell, every policy change would require a code change.



With JSON, a compliance analyst can update a rule without editing the PowerShell detection engine.



\---



\## 🌳 2. Transitive Membership Is Checked



The scanner does not look only at direct group membership.



It uses transitive membership.



```powershell

Get-MgUserTransitiveMemberOf

```



Why?



Because access can hide inside nested groups.



```text

User

&#x20;↓

Group A

&#x20;↓

Group B

&#x20;↓

Sensitive Access

```



A direct membership check may miss that access.



A transitive check follows the full membership chain.



\---



\## 🧹 3. Duplicate Findings Are Removed



Two policy rules may accidentally describe the same group combination in opposite directions.



Example:



```text

Rule A:

Charge Entry + Claims Submission



Rule B:

Claims Submission + Charge Entry

```



The scanner normalizes the group pair.



Instead of creating two findings for the same condition, it creates \*\*one finding\*\* and shows all matching rules.



This prevents policy duplication from making the risk numbers look larger than they really are.



\---



\## 🚨 4. Orphaned Entitlements Are Flagged, Not Automatically Removed



The toolkit can identify access that may no longer match someone's current role.



It does \*\*not\*\* automatically revoke that access.



Why?



Because a script may not understand the business reason behind the permission.



Instead:



```text

Scanner identifies suspicious access

&#x20;             ↓

Manager reviews the finding

&#x20;             ↓

Business owner makes the decision

```



The receiving manager owns the access decision.



\---



\## 🔢 5. Exit Codes Support Automation



`Test-SoDConflicts.ps1` returns:



```text

0 = No conflicts found

1 = Conflicts found

```



That makes the tool easier to run from:



\* Scheduled jobs

\* Automation platforms

\* CI/CD pipelines

\* Monitoring systems



\---



\# 📂 Repository Structure



```text

entra-identity-governance-toolkit/

│

├── scripts/

│   ├── seed-users.ps1

│   │   └── Creates the synthetic organization

│   │

│   ├── create-dynamic-groups.ps1

│   │   └── Creates attribute-based RBAC groups

│   │

│   ├── Test-SoDConflicts.ps1

│   │   └── Scans for dangerous access combinations

│   │

│   ├── Get-OrphanedStaleAccounts.ps1

│   │   └── Detects dormant or unattested identities

│   │

│   ├── Invoke-Joiner.ps1

│   │   └── Demonstrates new-user provisioning

│   │

│   ├── Invoke-Mover.ps1

│   │   └── Processes transfers and reports access changes

│   │

│   └── Invoke-Leaver.ps1

│       └── Demonstrates account termination and containment

│

├── policy/

│   └── sod-matrix.json

│       └── SoD conflict rules stored as data

│

├── docs/

│   ├── sod-methodology.md

│   │   └── Rule design, limitations, and tuning

│   │

│   ├── conditional-access-baseline.md

│   │   └── Conditional Access policies and risk decisions

│   │

│   └── findings-log.md

│       └── Problems found during development

│

├── evidence/

│   └── Timestamped CSV and JSON output from real runs

│

└── screenshots/

&#x20;   └── Visual evidence from the lab environment

```



\---



\# ⚙️ Running the Toolkit



\## Requirements



\* PowerShell 7+

\* Microsoft Entra ID P1 or higher for dynamic groups

\* Microsoft Entra ID P2 for entitlement management

\* Microsoft Graph PowerShell SDK



\---



\## 1️⃣ Install Microsoft Graph Modules



```powershell

Install-Module Microsoft.Graph.Authentication,

&#x20; Microsoft.Graph.Users,

&#x20; Microsoft.Graph.Groups,

&#x20; Microsoft.Graph.Identity.DirectoryManagement,

&#x20; Microsoft.Graph.Identity.Governance,

&#x20; Microsoft.Graph.Identity.SignIns,

&#x20; Microsoft.Graph.Users.Actions -Scope CurrentUser

```



\---



\## 2️⃣ Connect to Microsoft Graph



```powershell

Connect-MgGraph -Scopes 'User.ReadWrite.All',

&#x20; 'Group.ReadWrite.All',

&#x20; 'Directory.ReadWrite.All',

&#x20; 'AuditLog.Read.All',

&#x20; 'Organization.Read.All'

```



> Note: device code authentication is blocked by Security Defaults in newer tenants.

> Use interactive authentication. See Finding #5 below.



\---



\## 3️⃣ Open the Scripts Folder



```powershell

cd scripts

```



\---



\## 4️⃣ Preview User Creation



```powershell

.\\seed-users.ps1 -TenantDomain '<yourtenant>.onmicrosoft.com' -WhatIf

```



\---



\## 5️⃣ Run the SoD Scanner



```powershell

.\\Test-SoDConflicts.ps1 -Format All

```



\---



\## 6️⃣ Scan for Stale or Orphaned Accounts



```powershell

.\\Get-OrphanedStaleAccounts.ps1 -Format All

```



\---



\## 🛟 Safe Testing



Scripts support:



```powershell

\-WhatIf

```



This allows changes to be previewed before they are applied.



\---



\# 🔐 Conditional Access



Identity governance decides \*\*what\*\* access a person should have.



Conditional Access decides \*\*how\*\* that access may be used.



The lab enforces three policies.



\---



\## 🧯 First: A Break-Glass Account



Before creating any Conditional Access policy, I created an emergency access account.



```text

breakglass@<tenant>.onmicrosoft.com

Global Administrator

Excluded from all three policies

```



Why?



Because a Conditional Access mistake can lock every administrator out of the tenant permanently.



```text

Policy requires MFA for all users

&#x20;             ↓

Admin has no MFA method registered

&#x20;             ↓

Nobody can sign in

&#x20;             ↓

Nobody can fix the policy

```



The break-glass account is the recovery path.



> Create the escape hatch \*\*before\*\* you build the door.



\---



\## The Three Policies



| Policy   | Purpose                             | Scope                                                                                | Control                                  |

| -------- | ----------------------------------- | ------------------------------------------------------------------------------------ | ---------------------------------------- |

| \*\*CA01\*\* | Require MFA for all users           | All users                                                                            | Require multifactor authentication       |

| \*\*CA02\*\* | Block legacy authentication         | Exchange ActiveSync clients and other legacy clients                                 | Block access                             |

| \*\*CA03\*\* | Require MFA for privileged roles    | Global Admin, Privileged Role Admin, User Admin, Security Admin                      | Require MFA + sign-in frequency: always  |



All three exclude the break-glass account.



All three are \*\*enabled\*\*, not report-only.



\---



\## Why CA02 Exists



CA01 alone is not enough.



Legacy authentication protocols such as POP, IMAP, and SMTP AUTH cannot perform modern authentication.



That means they \*\*cannot present an MFA prompt\*\*.



```text

Attacker has valid password

&#x20;       ↓

Signs in over a legacy protocol

&#x20;       ↓

MFA is never requested

&#x20;       ↓

CA01 is bypassed

```



Blocking legacy authentication closes that door.



\---



\## Why CA03 Overlaps CA01



CA03 targets directory roles that CA01 already covers.



That overlap is intentional.



```text

If CA01 is ever narrowed, disabled, or misconfigured

&#x20;                   ↓

Privileged accounts remain protected by CA03

```



CA03 also adds a control CA01 does not have:



```text

Sign-in frequency: every time

```



Administrative sessions should not persist indefinitely.



\---



\## 📉 The Security Defaults Trade-Off



This part is worth being honest about.



Entra ID \*\*Security Defaults\*\* and \*\*Conditional Access\*\* cannot both be active.



Security Defaults is a single on/off switch.



Conditional Access is a set of scoped, documented policies.



During the build, Security Defaults had to be turned off.



For a period of time, the tenant had \*\*no authentication controls at all\*\*.



```text

Security Defaults disabled

&#x20;         ↓

Gap period

&#x20;         ↓

Three Conditional Access policies created

&#x20;         ↓

Policies enforced

&#x20;         ↓

Gap closed

```



That gap was a real risk, not a hypothetical one.



I recorded it rather than quietly skipping it.



📄 Full write-up:



```text

docs/conditional-access-baseline.md

```



\---



\# 🐛 Development Findings



I found and fixed \*\*8 defects\*\* while building and testing the project.



These findings are important because identity governance tools can create a dangerous false sense of security when they fail quietly.



Full write-ups are available in:



```text

docs/findings-log.md

```



Here are several of the most important findings.



\---



\## 🚨 Finding #1: A Scanner That Checked Nobody



One test returned:



```text

No violations found.

```



That sounded good.



It was actually a serious failure.



The Microsoft Graph authentication token had expired.



The scan completed structurally, but it checked:



```text

0 identities

```



That meant the tool produced a \*\*false clean result\*\*.



\### Fix



I added a guard clause.



If the scanner cannot retrieve the expected identities, it stops instead of reporting that the environment is clean.



```text

Bad behavior:



Authentication problem

&#x20;       ↓

0 users checked

&#x20;       ↓

"No violations"

&#x20;       ↓

False sense of security





Correct behavior:



Authentication problem

&#x20;       ↓

Validation fails

&#x20;       ↓

Scan stops

&#x20;       ↓

Administrator investigates

```



> For a compliance control, a false green light can be more dangerous than an obvious error.



\---



\## 🧩 Finding #2: Graph Attributes and Dynamic Rule Attributes Do Not Always Match



Microsoft Graph and Entra dynamic membership rules do not always use the same attribute names.



For example:



```text

officeLocation

```



had to be written through:



```text

physicalDeliveryOfficeName

```



`employeeType` was also not usable in the way originally expected, so it was mirrored into:



```text

extensionAttribute1

```



This affected how the dynamic RBAC rules were built.



\---



\## 🎯 Finding #3: A Bad Policy Rule Created a False Negative



One SoD rule originally compared PHI access with a \*\*site group\*\*.



That was not the right business relationship.



The real risk involved IT staff.



I created:



```text

RBAC-IT-Staff

```



and changed one line in the JSON policy.



Detection improved from:



```text

3 findings

```



to:



```text

4 findings

```



\### Lesson



> A detection engine can only be as good as the access model and policy rules behind it.



\---



\## 👤 Finding #4: Every Group Had No Owner



The lab contained:



```text

13 groups

```



At one point:



```text

13 of 13 groups had no owner

```



That included every group involved in an SoD conflict.



Because the groups were created entirely through automation, ownership had never been assigned.



This created another governance problem:



> Who should review the access?



A group-scoped access review needs a clear business owner or reviewer.



Automation can build an environment successfully while still missing an important governance requirement.



\### Fix



I assigned owners based on business accountability rather than convenience.



```text

Billing entitlements    → Billing Manager

PHI and record access   → Director of HIM

Department RBAC groups  → Department leadership

```



Ownerless groups went from \*\*13\*\* to \*\*0\*\*.



\---



\## 🔑 Finding #5: Authentication Behavior Changed



Device code authentication stopped working during the build.



New Entra tenants began blocking device code authentication under Security Defaults as of \*\*July 1, 2026\*\*, in response to device-code phishing risks.



Instead of weakening the security setting, I changed the project to use interactive authentication.



\### Principle



```text

Security control blocks workflow

&#x20;          ↓

Do not disable security just to make the lab work

&#x20;          ↓

Change the workflow

```



\---



\## 🚪 Finding #6: A Terminated Account Kept Its Access



The leaver test disabled a contractor's account and revoked their active sessions.



The account was correctly disabled.



But the contractor stayed in \*\*three dynamic groups\*\*.



\### Why?



None of the dynamic membership rules checked whether the account was still enabled.



```text

Rule:

department = "Revenue Cycle"



Disabled user still has:

department = "Revenue Cycle"

&#x20;       ↓

Rule still matches

&#x20;       ↓

Membership never drops

```



The account was disabled but still appeared as a current member of access groups.



An access review would have listed a terminated contractor as an active member.



\### Fix



Every dynamic rule was rewritten to check account state:



```text

(user.accountEnabled -eq true)

&#x20;       -and

(user.department -eq "Revenue Cycle")

```



After the change, the terminated account dropped from all three groups.



\### Lesson



> Disabling an account is not the same as removing its access.

>

> If your revocation story depends on group removal instead of token revocation, there is a window.



\---



\# 📊 Evidence



The repository includes more than \*\*16 timestamped CSV and JSON exports\*\* from real script runs.



These provide evidence of:



\* User provisioning

\* Group membership

\* Joiner events

\* Mover events

\* Leaver events

\* SoD scans

\* Stale account scans

\* Access changes

\* Detected conflicts



This was intentional.



The goal was not to create scripts that \*look\* correct.



The goal was to run them against an actual Entra tenant and keep evidence of what happened.



\### Before-and-after evidence



Some of the most useful files in this repository are the ones that show remediation:



```text

ownerless-groups-<timestamp>.csv   →  13 groups

ownerless-groups-<timestamp>.csv   →  0 groups (empty file)



sod-findings-<timestamp>.csv       →  3 findings

sod-findings-<timestamp>.csv       →  4 findings (after rule tuning)

```



Two of those files are zero bytes.



That is not an error.



A zero-byte findings file is the proof that a problem was actually fixed.



\---



\# ⚠️ Known Limitations



\## 🧪 This Is a Lab



The environment uses:



\* Synthetic users

\* Fake organization data

\* No patient records

\* No real PHI

\* A disposable Entra tenant



It is a learning and portfolio environment, not a production healthcare system.



\---



\## 🔧 This Demonstrates Governance Concepts, Not SailPoint



Enterprise identity platforms such as:



\* SailPoint

\* Saviynt

\* CyberArk



do not provide the same type of free individual sandbox environment that Microsoft Entra ID provides.



This project therefore demonstrates the \*\*identity governance concepts\*\* using Entra ID.



Those concepts include:



```text

JML

RBAC

SoD

Least Privilege

Entitlement Management

Access Certification

Audit Evidence

Lifecycle Governance

```



The concepts transfer between platforms.



The exact buttons and tools do not.



\---



\## 🧩 SoD Matrix v1.0 Limitation



The current JSON schema handles conflicts between group pairs.



Example:



```text

Group A + Group B = Conflict

```



It cannot yet express more complex conditions such as:



```text

Role = Internal Auditor

AND

Operational Access = True

```



This is documented in:



```text

docs/sod-methodology.md

```



\---



\## 📅 Access Review Cycle Not Completed



The quarterly access review on the access package is \*\*configured and scheduled\*\*.



A full review cycle has not completed inside the lab window.



The control design is documented; a completed recertification campaign is not claimed.



\---



\# 🔒 Evidence and Privacy



The evidence files contain the lab:



\* Tenant ID

\* Administrator UPN



These values belong to the disposable lab environment.



They are included intentionally because the project is designed to show \*\*real timestamped results from a real Entra tenant\*\*, rather than fabricated output.



No real employee or patient information is included.



\---



\# 🔄 Companion Identity Governance Project



This repository represents the \*\*directory / Identity Provider side\*\* of my identity governance portfolio.



The companion project handles the \*\*ITSM and access recertification workflow side\*\*:



\### 🔗 \[ServiceNow Access Recertification — Scoped Application](https://github.com/Kadest-Tech/Servicenow-Access-Recertification)



Together, the projects demonstrate two sides of the same identity governance process:



```mermaid

flowchart LR



&#x20;   A\["Microsoft Entra ID<br/>Identity Provider"]



&#x20;   B\["Identity Governance<br/>RBAC • JML • SoD"]



&#x20;   C\["ServiceNow<br/>ITSM Workflow"]



&#x20;   D\["Access Requests<br/>Approvals • Recertification"]



&#x20;   A --> B

&#x20;   B <--> C

&#x20;   C --> D

```



\### Entra ID Project



```text

Who has access?

What access should they have?

Are dangerous access combinations present?

What changed when their job changed?

```



\### ServiceNow Project



```text

Who reviews access?

Who approves changes?

How is access recertified?

How are decisions documented?

```



\---



\# 🧰 Skills Demonstrated



This project demonstrates hands-on experience with:



| Area                   | Skills                                                  |

| ---------------------- | ------------------------------------------------------- |

| 🔐 \*\*IAM\*\*             | Identity lifecycle, access management, least privilege  |

| 🏛️ \*\*IGA\*\*            | Entitlements, access governance, certification concepts |

| 👥 \*\*RBAC\*\*            | Attribute-driven role assignment                        |

| 🔄 \*\*JML\*\*             | Joiner, Mover, Leaver automation                        |

| ⚠️ \*\*SoD\*\*             | Toxic access combination detection                      |

| ☁️ \*\*Entra ID\*\*        | Users, groups, dynamic membership, Conditional Access   |

| 🌐 \*\*Microsoft Graph\*\* | Identity and directory automation                       |

| ⚙️ \*\*PowerShell\*\*      | Governance automation and reporting                     |

| 🧾 \*\*Audit\*\*           | Timestamped CSV/JSON evidence                           |

| 🛡️ \*\*Security\*\*       | Least privilege, access risk, control validation        |

| 📋 \*\*Compliance\*\*      | HIPAA, SOX ITGC, NIST AC-6 concepts                     |



\---



\# ✅ What This Project Proves



This project is designed to demonstrate more than the ability to create users and groups.



It shows how identity governance problems appear in real environments.



\### The main lesson:



> \*\*Access can be correct when it is granted and become dangerous later.\*\*



Employees transfer.



Temporary access is forgotten.



Projects end.



Managers change.



Groups become nested.



Exceptions become permanent.



That is why effective identity governance requires more than an approval screen.



It requires:



```text

Correct provisioning

&#x20;       +

Continuous detection

&#x20;       +

Clear ownership

&#x20;       +

Access reviews

&#x20;       +

Audit evidence

```



\---



\# 👨‍💻 Author



\*\*Kadest Ekoubegzi\*\*



Cybersecurity | Identity \& Access Management | ServiceNow | Identity Governance



Built and tested in \*\*August 2026\*\*.



\---



⭐ \*\*If you are reviewing this project for an IAM, Identity Governance, GRC, or ServiceNow role, I recommend starting with:\*\*



1\. `scripts/Test-SoDConflicts.ps1`

2\. `policy/sod-matrix.json`

3\. `docs/sod-methodology.md`

4\. `docs/findings-log.md`

5\. `evidence/`



These files show the main governance logic, policy design, testing process, and real execution results.

