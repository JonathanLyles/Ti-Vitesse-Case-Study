# Issue Remediation Plan

Problems found while cleaning up the Ti-Vitesse case study, with the fix, acceptance criteria, effort and status for each. This file in the repo is the master copy.

## Context

The cleanup left `main` deployable but with known loose ends. **Status as of 2026-10-13:** Issues 1, 2B, 2C (replaced by accept-and-document), 3, 4 (same), 5, 6, 7, 8a and 9 are done, and GitHub #5 (admin access) is fixed. Still open: Issue 8b (vehicle loan component on the customer site, plus the live test), then Issue 10 (customer Home tiles); Issue 11 (Case assignment Flow) can be done at any time. This plan lists each issue, what to do, how big it is, and the order to tackle them. Each remaining item gets its own branch from `main`.

Effort scale: **S** under 30 min, **M** about 1-2 hours, **L** a half day or more.

## Numbered issues

### 1. Six disabled tests: portal and agent users cannot read `TiVitesse_Callout_Setting__mdt` (GitHub #4)

- **Summary:** `VehicleLoanApiClient.getOAuthSettings()` (line 181 now; the query is at 186) queries the custom metadata type. Under `System.runAs` for the test customer (profile `Customer Community Clone`, permission set `Vehicle_Claim_Portal_Access`) and agent (`Custom - TVI Agents`), it throws "sObject type ... is not supported". Neither permission set mentions the type. The same path would fail for real customers on reserve and return.
- **Root cause (confirmed 2026-10-11):** neither permission set gave access to the type. Admin-run anonymous Apex read the record fine. Granting `customMetadataTypeAccesses` fixed it. **Known trade-off, accepted:** that grant lets portal customers and agents read the type that holds the OAuth secret and password. This is a practice org, so it is accepted (see the decisions log), but Issue 9 tries to avoid depending on it.
- **Recommendation:** diagnose first with a throwaway test that runs the query as each user and checks their effective access. Then grant read on the type (a `customMetadataTypeAccesses` entry in the permission sets, plus field access) and re-enable the six tests, removing the `TODO #4` block comments in `VehicleLoanControllerTest.cls`.
- **Effort:** M. **Blocks:** 4, 5.

**STATUS: DONE (2026-10-11), on `main` as `93c7c13`; GitHub #4 closed.** Criteria 1-8 passed (91 tests, 0 failures; org-wide coverage 69% -> 80%; `VehicleLoanController` 33% -> 77%; High findings unchanged at 5). Criterion 9 was reduced by decision: the live `updateVehicle` (reserve/return POST) check is dropped, and a real portal-customer login check is not applicable yet because the LWC displays nothing. The read-only live call (OAuth token + `getVehicles`, 10 vehicles returned, run as admin) passed, so Issue 1 is fully done. A second, hidden failure was found and fixed on the way: the shared `LoanApiMock` asserted every POST was `updateVehicle` and never handled the OAuth token request.

**Acceptance criteria for Issue 1. Done when, all of these hold:**

1. **Root cause confirmed with evidence before any fix.** A throwaway diagnostic (not committed) runs the metadata query as the test customer (`Customer Community Clone` + `Vehicle_Claim_Portal_Access`) and as the test agent (see `getAgent()` in `VehicleLoanControllerTest.cls` for the profile and permission sets it assigns). It must show the query failing for them today. If it does not fail, the theory is wrong and the plan is revised before anything is changed.
2. **Access granted in source, minimally.** The permission set(s) those users actually hold gain read access to `TiVitesse_Callout_Setting__mdt` (`customMetadataTypeAccesses`) and the fields the client reads, and nothing broader. The change is deployed and committed.
3. **The same diagnostic now succeeds** for both users, run again after the deploy.
4. **The six tests are re-enabled unchanged.** The `TODO #4` block-comment markers are removed from `VehicleLoanControllerTest.cls` and nothing else in those test bodies changes (`git diff` shows only comment markers removed). No assertion removed or loosened, no `SeeAllData=true`, no `Test.isRunningTest()` branch added to production code.
5. **Tests pass.** `VehicleLoanControllerTest` shows 0 failures, and the full local suite passes (91 tests = 85 existing + 6 re-enabled, 0 failures).
6. **Coverage recovers.** `VehicleLoanController` coverage rises from 33% and is reported with its remaining uncovered lines. The 85% per-class bar is tracked under Issue 5, but if the number is still well under 75% here, say so before closing.
7. **No regressions in scans.** `sf code-analyzer` reports no more than the current 5 High findings (this change must not add any).
8. **Issue closed properly.** GitHub issue #4 gets a closing comment linking the commit, and the baseline comment's numbers are updated or referenced. No credential values appear in the diff.
9. **It works outside tests.** The fix is a permission change, not a test-only workaround, and the read-only live call (OAuth token + `getVehicles`) succeeds against the real API. Live `updateVehicle` and a real portal-customer login are out of scope for now (the LWC displays nothing yet); revisit with Issue 8.

### 2. Plaintext credentials in the `TiVitesse_Callout_Setting.default` record

- **Summary:** The record holds a client secret, a password, a security token and a username in clear text. It is untracked and was never pushed. This is a developer org and a practice scenario, so credential rotation is out of scope (dropped by decision).
- **Recommendation (Part C superseded, see below):** keep the record out of Git (Part B). Moving the secrets into an External or Named Credential (Part C) was investigated and dropped, because External Credentials do not support the OAuth password grant.
- **Effort:** Part B S, Part C M. **Order note:** Part B first, Part C together with issue 4 below.

**Part B. Keep the record out of Git. STATUS: DONE (2026-10-11), merged to `main` and pushed as `853f1e9`.** All four criteria passed; the five real secrets appear in 0 commits (the only history matches were the generic OAuth word "password" in `grantType__c`). Criteria were:

1. `force-app/main/default/customMetadata/` is listed in `.gitignore`, and
   `git check-ignore -v force-app/main/default/customMetadata/TiVitesse_Callout_Setting.default.md-meta.xml` prints the matching rule.
2. `git status --short` no longer shows `customMetadata/` as untracked.
3. The credential values are not in history: `git log --all -S"<fragment of each secret>"` returns no commits (fragments read locally from the file, never printed).
4. The change is committed on its own branch and `.gitignore` is the only file in the diff.

**Part C DECISION (2026-10-12): replaced by "accept and document" (path 4).** Step 0 found that External Credentials do not support the OAuth password grant the remote API requires, and the user does not control the remote org (`doushka-dev-ed`), so the grant cannot be changed. The two `ApexSuggestUsingNamedCred` findings are suppressed with a documented reason in `VehicleLoanApiClient` (commit `02863cc`, merged and pushed to `main`; High findings 5 -> 3). The OAuth-settings code and the metadata type STAY, so the 12 OAuth-settings lines and the `VehicleLoanApiClient:178` CRUD finding remain, and Issue 5's reorder benefit no longer applies. Original criteria below are kept for reference only.

**Part C (original, superseded). Move authentication to a Named or External Credential. Done when, all of these hold:** 0. **Feasibility check first.** Before any code changes, confirm which credential type can perform this API's token exchange. The current flow is an OAuth password grant (username, password plus security token, client id and secret) sent to `callout:TiVitesseBearerToken`. I believe External Credentials do not support the password grant natively, so this may not be possible as written. If it isn't, stop and bring the options back for a decision (for example: keep the token call but store the secrets in a protected store, or change the API's grant type) instead of improvising.

1. `VehicleLoanApiClient` no longer queries `TiVitesse_Callout_Setting__mdt` or builds the `Authorization: Bearer` header itself. The OAuth settings code (`getOAuthSettings`, `OAuthSettings`, the token request) is removed or replaced.
2. No secret is stored in custom metadata or source: `grep -r` for the old field names (`clientSecret__c`, `password__c`, `securityToken__c`) and the old values finds nothing in `force-app/`. The `TiVitesse_Callout_Setting__mdt` type and record are removed from source and the org, or left only as a non-secret settings holder.
3. The two `ApexSuggestUsingNamedCred` findings at `VehicleLoanApiClient` lines 10 and 61 are gone from `sf code-analyzer run --workspace force-app --severity-threshold 2`, and no new High findings appear.
4. `VehicleLoanApiClientTest` and `VehicleLoanControllerTest` pass with the tests rewritten for the new flow, and no assertion is removed or loosened to get there.
5. In the org, the read-only live call (`new VehicleLoanApiClient().getVehicles()` via anonymous Apex) still returns vehicles through the credential, and does so without reading `TiVitesse_Callout_Setting__mdt`. Live `updateVehicle` is not required.
6. **Clean-up of Issue 1's grants.** If the metadata type is deleted, the `customMetadataTypeAccesses` entries added to `Vehicle_Claim_Portal_Access` and `Vehicle_Loan_Internal_Access` in `93c7c13` are removed too, and both permission sets still deploy. The test agent's `Vehicle_Loan_Internal_Access` assignment stays only if that set is still needed for another reason.
7. **Suite and scans hold.** The full local suite passes with 0 failures and org-wide coverage stays at or above 80%. `sf code-analyzer` shows the two `ApexSuggestUsingNamedCred` findings and the `VehicleLoanApiClient:178` `ApexCRUDViolation` gone, with no new High findings.
8. **Delivery.** Done on its own branch from `main`, merged and pushed, with the plan updated.

### 3. Three `ApexCRUDViolation` findings (static analysis, High)

- **Where:** `CustomerClaimsController.cls:20`, `VehicleClaimController.cls:42` (both `SELECT ... FROM User WHERE Id = :UserInfo.getUserId()`), and `VehicleLoanApiClient.cls:186` (the metadata query).
- **Recommendation:** add `WITH USER_MODE` to the two User queries (low risk, users can read their own record). The metadata query was left alone here: the OAuth-settings code was kept (see Issue 2C). Issue 9 tries `WITH USER_MODE` on it, since the users now hold the type access.
- **Effort:** S. **Order note:** after issue 1.

**STATUS: DONE (2026-10-12), merged and pushed to `main` as `a8fb0ad`.** Only the two User queries changed (`WITH USER_MODE`, 1 line each). High findings 3 -> 1 (the remaining one is `VehicleLoanApiClient.cls:186`, the metadata query, accepted). 109 tests, 0 failures, org-wide coverage 85%; `CustomerClaimsController` 92%, `VehicleClaimController` 96%. The portal customer could already read its own `ContactId` and `Contact.AccountId` in user mode, so no permission change was needed.

**Acceptance criteria for Issue 3 (all passed):**

1. Only the two queries change: `git diff` shows `WITH USER_MODE` added to each, nothing else in production code.
2. `sf code-analyzer` no longer reports `ApexCRUDViolation` at those two places and adds no new findings (High 3 -> 1).
3. `CustomerClaimsControllerTest` and `VehicleClaimControllerTest` pass unchanged as the portal customer; no assertion removed or loosened.
4. If user mode had blocked the customer's read of `User.ContactId` or `Contact.AccountId`, the minimum grant would go into the portal permission set. Not needed.
5. Full `RunLocalTests` suite: 109 tests, 0 failures; org-wide coverage stays at or above 85%.
6. Own branch from `main`, merged; plan updated. Merged and pushed.

### 4. Two `ApexSuggestUsingNamedCred` findings (High)

**STATUS: REPLACED (2026-10-12) by accept-and-document.** The remote API needs an OAuth password grant that External Credentials do not support, and the remote org is not under our control. The two findings are suppressed with a documented reason (`02863cc`). The original recommendation below is kept for reference.

- **Where:** `VehicleLoanApiClient.cls:10` and `:61`. The code already calls `callout:TiVitesseNamedCredential/...` but builds the `Authorization: Bearer` header by hand from a token fetched with the credentials in issue 2.
- **Recommendation:** fix by letting the named credential handle authentication, as part of issue 2's redesign. Do not suppress the warning, because the manual token flow is the real exposure.
- **Effort:** M. **Order note:** do together with issue 2's redesign.

### 5. Low coverage (re-verified 2026-10-11 after Issue 1)

- **Current numbers (full `RunLocalTests`, 91 tests, org-wide 80%):** `VehicleLoanApiClient` 77% (105/137), `VehicleLoanController` 77% (134/175). `VehicleLoanActionResult` and `VehicleLoanOption` are now 100% (fixed as a side effect of Issue 1). The project bar is 85% per changed class.
- **Uncovered, `VehicleLoanApiClient`:** network-failure catches (lines 15-16, 66-67, 116-117); bad JSON or wrong structure in the vehicle response (30-36, 40-41) and token response (132-135, 139, 144-145); the OAuth-settings code (178, 190-196, 215-221, 12 lines) which Issue 2C deletes.
- **Uncovered, `VehicleLoanController`:** callout and JSON failure handling (32-40, 83-91, 111-119); input checks (55, 159, 175, 212); more than one active loan (281-282); missing Loan Vehicle record type (292-293); DML failure after a successful remote return (200-205); `getVehicles()` (141-147), which Issue 7 may change or remove.
- **Recommendation:** add about 15 to 20 small tests, mostly new mock responses. Do this after Issue 2C, which removes the 12 OAuth-settings lines and lifts `VehicleLoanApiClient` to about 84% without new tests.
- **Effort:** M. **Order note:** after Issue 2C and 4.

**STATUS: DONE (2026-10-12), on `main`.** `VehicleLoanApiClient` 77% -> 89%, `VehicleLoanController` 77% -> 89%; 109 tests (91 + 18 new), 0 failures; org-wide coverage 80% -> 85%; High findings unchanged at 3; only `*Test.cls` files changed, no assertion removed. Note: the OAuth-settings lines were NOT deleted (path 4 chosen), but the 85% bar was still reached without covering them.

**Acceptance criteria for Issue 5. Done when, all of these hold:**

1. `VehicleLoanApiClient` and `VehicleLoanController` are each at or above **85%** in a full `RunLocalTests` run.
2. **Only tests change.** `git diff` against `main` shows only `*Test.cls` files; no production code is edited.
3. Every new test asserts a specific outcome (exact error message or returned result). No empty assertions, no `SeeAllData=true`, no `Test.isRunningTest()` branches.
4. The full suite passes: 91 plus the new tests, 0 failures. Org-wide coverage stays at or above 80%.
5. `VehicleLoanActionResult`, `VehicleLoanOption`, `VehicleLoanApiResponse` and `VehicleLoanContext` stay at 100%.
6. `sf code-analyzer` reports no more than the current High findings (5, or fewer once Issues 2C, 3 and 4 land). The new tests add none.
7. **Out of scope on purpose:** the OAuth-settings code (until 2C removes it) and `getVehicles()` (until Issue 7 decides its fate). No tests are written for either.

### 6. Org-only metadata not in source

- **Summary:** confirmed 2026-10-12 by listing org metadata: `Vehicle__c` has 7 validation rules in the org and 4 in source. The three org-only rules are `Make_field_is_required`, `Mileage_is_required` and `Engine_Capacity_is_a_required_field`. The org has no source tracking (`sf project retrieve preview` errors), so other drift can only be found by retrieving and diffing.
- **Proposed solution:** (1) retrieve the three rules into source. (2) Retrieve the metadata types tonight's work touched (the `Vehicle__c` object, the loan and claim classes, the two permission sets, the Case and Vehicle FlexiPages, layouts) into a scratch folder outside the repo and `diff -r` against `force-app`. (3) Review each difference with you: the org is the source of truth unless you say otherwise. (4) Commit only reviewed items.
- **Effort:** S to M. Independent of the rest.

**Acceptance criteria for Issue 6. Done when, all of these hold:**

1. The three rules exist in `force-app/main/default/objects/Vehicle__c/validationRules/`, retrieved from the org, and the folder holds 7 rules matching the 7 in the org.
2. Each retrieved rule is shown to you (formula, error message, active flag) and you confirm it applies to both record types as already agreed.
3. A scratch retrieve of the touched types plus `diff -r` against `force-app` is run. The result is listed in the issue: either "no other differences" or each difference with a decision (commit, ignore, or fix the org).
4. No secrets or org-specific noise are committed (no `customMetadata/` records, no user-specific files). `git diff` shows only the reviewed files.
5. `sf project deploy start` of the changed files succeeds with no changes reported (source already equals the org), and the full suite still passes with the same 109 tests, 0 failures.
6. **Referenced fields exist in source.** Every field named in the three rules' formulas (for example the Engine Capacity, Make and Mileage fields on `Vehicle__c`) has its field file in `force-app/main/default/objects/Vehicle__c/fields/`. Any that exist only in the org go into the drift list from criterion 3.
7. Own branch from `main`, reviewed by you before commit, merged and pushed after approval; plan updated.

**STATUS: DONE (2026-10-12), on `main` as `f7e62d9`.** Criteria 1-7 passed. Retrieved the 3 org-only rules and, by decision, the rest of the `Vehicle__c` object: the object file, 14 fields, 3 layouts, the `All` list view and the 2 record types (the org versions add the `Colour__c` picklist values). Also retrieved `Case_Record_Page`, which in source still pointed at the deleted `loanVehicleLWC`. Drift check result: classes, permission sets, `Vehicle_Record_Page` and the existing rules matched the org apart from formatting; the 28 org-only Experience Cloud template classes (login, registration) and one managed-package class are ignored. A deploy dry run of the retrieved metadata reported 31 components, 0 errors, nothing changed; the full suite stayed at 109 tests, 0 failures. Four files that came back with formatting-only changes (`Loan_Active__c`, `Loan_End_Date__c`, the Case and Contact rules) were left as they were.

### 7. `getVehicles()` semantics

- **Summary:** loan records are created at reservation time (`reserveVehicle` inserts a `Loan_Vehicle` with `Loan_Active__c = true`). So `getVehicles()` (`VehicleLoanController.cls:140-150`, `Loan_Active__c = FALSE`, record type `Loan_Vehicle`) returns past, ended loans, not available vehicles. Available vehicles already come from the remote API through `getLoanContext` (`availableVehicles`), which also returns the active loan and `canReturnActiveLoan`. `vehicleLoanLWC` currently wires `getVehicles()`, so it would list old loans as if they were available.
- **Options:** (A) delete `getVehicles()` and its wire; the component uses `getLoanContext`, `reserveVehicle` and `returnVehicle`. (B) Keep it but turn it into "loan history", renamed `getLoanHistory(caseId)` and scoped to the Contact/Case. (C) Leave it.
- **Proposed solution (recommended): A.** The remote API is the source of truth for availability, the controller already has the authorised, tested path, and a second unscoped query invites a wrong "available" list. Add B later only if you want a history panel.
- **Effort:** S to decide, S to change.

**STATUS: DONE (2026-10-12), option A chosen, branch `fix/issue-7-remove-local-get-vehicles`.** `VehicleLoanController.getVehicles()` is removed, together with the `getVehicles` import, the `@wire(getVehicles)` and the vehicle list in `vehicleLoanLWC` (the placeholder now shows only the record Id and case number until Issue 8a). `grep` finds no remaining reference; the `VehicleLoanApiClient.getVehicles()` remote call is untouched. `check.sh` passes all four gates: 109 tests, 0 failures, org-wide coverage 85%, `VehicleLoanController` 89% -> 91%, 0 High findings.

**Acceptance criteria for Issue 7. Done when, all of these hold:**

1. **Decision recorded:** you pick A, B or C and the choice and reason are written in this plan.
2. **If A:** `getVehicles()` is removed from `VehicleLoanController`; the `getVehicles` import and `@wire(getVehicles)` are removed from `vehicleLoanLWC`; no other reference remains (`grep -r "VehicleLoanController.getVehicles" force-app` returns nothing, and the `VehicleLoanApiClient.getVehicles()` remote call is untouched).
3. **If B:** the method is renamed, takes the Case Id, calls the same `authorizeCase` check as the other methods, returns only that Contact's ended loans, is `WITH USER_MODE` or documented otherwise, and has tests for: owner customer, other customer rejected, no history.
4. Tests: full suite passes with 0 failures; no assertion removed; `VehicleLoanController` coverage stays at or above 85%.
5. `sf code-analyzer` shows no new High findings (the count after Issue 9 is the baseline: 0, or 1 if Issue 9 is not done yet).
6. Own branch from `main`, reviewed before commit, merged and pushed after approval; plan updated.

### 8. Customer site lost its "Loan a Vehicle" component, and `vehicleLoanLWC` is a placeholder (split into 8a and 8b, 2026-10-12)

- **Summary:** the old component was removed from the "TI Vitesse Insurance Ltd" Home sidebar so it could be deleted. `vehicleLoanLWC` only shows the case number (`lightning__RecordPage` target only), so it cannot go in Experience Builder. Both permission sets already give `VehicleLoanController` class access (`Vehicle_Claim_Portal_Access`, `Vehicle_Loan_Internal_Access`). The Experience site metadata is not in source.
- **Why split:** the live reserve and return calls change data in a remote org you do not control. That step is isolated in 8b so it gets its own review and go-ahead.
- **Proposed solution, 8a (internal component, after Issue 7):** build `vehicleLoanLWC` on the existing controller.
  - `getLoanContext(recordId)` loads the state: an active loan (with a Return button only when `canReturnActiveLoan`), or the available vehicles list.
  - A reserve form: pick a vehicle, enter mileage and engine capacity (the controller validates ranges), call `reserveVehicle`, then reload.
  - A return action calling `returnVehicle`.
  - Loading, empty and error states; messages come from the `AuraHandledException` text.
  - Jest tests. Target stays `lightning__RecordPage`.
- **Proposed solution, 8b (customer site):** the site is **TI Vitesse Insurance Ltd** (URL prefix `/customers`, Network `0DBg70000028L4XGAU`). It has two active pages: **Home** (claim submission) and **My Vehicle Claims** (a Case record page). Add `lightningCommunity__Page` and `lightningCommunity__Default` targets with `recordId`, place the component on **My Vehicle Claims** in Experience Builder, shown only for `Vehicle_Claims` cases as on the internal page, and publish (a manual UI step). Then do the real customer login and the live reserve and return. The Home tiles that lead customers to this page are Issue 10, done after 8b (decided 2026-10-13).
- **Return from any claim (added 2026-10-13, a behaviour change in 8b):** a Contact's active loan can be returned from the component on any of that Contact's open `Vehicle_Claims` Cases, not only the Case it was reserved on. This applies on the internal page too, since it is the same component.
  - `VehicleLoanController`: `canReturnActiveLoan` becomes true whenever an active loan exists for the authorized Contact. `returnVehicle` matches the loan by Contact, dropping its `Case__c = caseId` condition. The loan keeps its original `Case__c`.
  - The Jest test "shows the active loan without a Return button when it belongs to another case" is **rewritten on purpose** to expect the Return button. The tests-not-weakened gate may flag the changed assertion, so note it in the review.
- **Effort:** 8a L to M, 8b M.

**STATUS 8a: DONE (2026-10-13), on `main` as `be1f7c7` and `a128dc0`.** Criteria 1-6 passed. The final `check.sh` run on `main` (after #6 and #7) passed all four gates: 113 Apex tests, 0 failures, org-wide coverage 85%, 54 Jest tests (16 for `vehicleLoanLWC`), 0 High findings, no assertions removed. Criterion 3: agent view confirmed 2026-10-12 (Jack Sparrow), admin view confirmed 2026-10-13 after the #5 fix (PR #6). Build notes from 2026-10-12 follow. Design decided with you: a vehicle list with a Reserve button per row; the Reserve modal shows the callout details (registration, make, model, year) read-only and asks for mileage and engine capacity, because the availability API does not return those two values (option A); success, warning and error messages are toasts. 15 Jest tests; `check.sh` passes all four gates (109 Apex tests, 0 failures, org-wide coverage 85%, 53 Jest tests, 0 High findings). Deployed to the org. Placement decided and deployed: `vehicleLoanLWC` is removed from `Vehicle_Record_Page` (there `recordId` is a Vehicle, so it would only show an authorisation error) and shown on `Case_Record_Page` only when `Record.RecordType.DeveloperName` equals `Vehicle_Claims`. Agent view confirmed 2026-10-12 (Jack Sparrow sees the vehicle list). Getting there needed three org grants, found from debug logs: the permission set assignment, then `externalCredentialPrincipalAccesses` for `TiVitesseExternalCredential-IntegrationUser` and read on the `UserExternalCredential` object, both added to `Vehicle_Loan_Internal_Access` and `Vehicle_Claim_Portal_Access` (the portal set for 8b), and `externalCredentials/TiVitesseExternalCredential` is now tracked in source. The component also shows a plain message when the user lacks class access.

**Acceptance criteria for Issue 8a. Done when, all of these hold:**

1. **Behaviour (Jest):** tests cover loading, available vehicles shown, active loan shown with and without the Return button, reserve success, reserve error message shown, return success, return error shown. The mocked Apex calls assert the exact arguments (case Id, registration, mileage, engine capacity). `npm run test:unit` passes.
2. `vehicleLoanLWC` no longer imports or wires the local `getVehicles()` (Issue 7), and deploys cleanly.
3. **Agent view:** on the internal Case record page, a user with `Vehicle_Loan_Internal_Access` sees the component and the loan state (result recorded). No live reserve or return is done in 8a.
4. **No secrets** appear in the component, tests or the diff.
5. **Suite and scans:** full Apex suite passes with 0 failures and org-wide coverage at or above 85%; no new High findings; ESLint and Prettier pass (the Husky hook enforces them).
6. **Delivery:** own branch from `main`, reviewed before commit, merged and pushed after approval; plan updated.

**Acceptance criteria for Issue 8b. Done when, all of these hold:**

1. `vehicleLoanLWC.js-meta.xml` exposes `lightning__RecordPage`, `lightningCommunity__Page` and `lightningCommunity__Default`, with `recordId` available to the site page; Jest still passes; deploys cleanly.
2. The component is placed on the **My Vehicle Claims** Case record page of **TI Vitesse Insurance Ltd** (`/customers`), shown only for `Vehicle_Claims` cases, and the site is published. The placement lives in the org, not in source. Retrieving the site bundle into source is optional and decided with you.
3. **Go-ahead and safeguard before the live POST.** You explicitly approve running reserve and return against the remote org. Before it runs, the chosen vehicle's registration and availability are recorded. If the return call fails, stop, report, and restore the vehicle by hand; do not retry blindly. After the test, the vehicle's state equals the recorded "before".
4. **Real portal customer login** (the check dropped at Issue 1): the customer sees available vehicles from the live API, reserves one with valid mileage and engine capacity, sees the active loan, and returns it. The OAuth settings read works as the portal customer, which also proves whichever approach Issue 9 chose for that query.
5. **Security:** a customer cannot load or act on another customer's Case (the controller's authorization rejects it; existing tests plus one manual attempt).
6. **Per-Contact rule, return from any claim, closed claims:**
   - While the customer has an active loan, every open claim of theirs shows that loan **with** a Return button and offers no Reserve. Returning from a claim other than the one it was reserved on succeeds.
   - Apex tests cover: return from another open claim of the same Contact succeeds; return of another Contact's loan is rejected; return from a closed claim is rejected.
   - A closed claim shows the plain "not authorized" message, not a blank or broken component.
7. **No secrets** appear in the diff or the plan.
8. **Suite and scans:** full Apex suite 0 failures, coverage at or above 85%, no new High findings.
9. **Delivery:** own branch from `main`, reviewed before commit, merged and pushed after approval; plan updated.

### 10. Customer Home tiles: My open claims and Loan a vehicle (added 2026-10-13, after 8b)

- **Summary:** on the Home page of TI Vitesse Insurance Ltd, the customer can submit a claim (`createVehicleClaim`) but has no direct way to reach their claims or a loan vehicle. You want two tiles: **My open claims**, and **Loan a vehicle**, which appears only when the customer has an open claim and no active loan. Requirements: `VEHICLE_LOAN_LWC_REQUIREMENTS.md` FR-18 to FR-22 and US-5.
- **Depends on 8b:** the Loan tile leads to a claim's **My Vehicle Claims** page, where `vehicleLoanLWC` (placed in 8b) shows the vehicles and Reserve. The customer sees and returns an active loan on any of their open claims' pages (8b's return-from-any-claim change).
- **Rules decided with you:**
  - Per-Contact loan rule, the same as the internal page: one active loan per Contact across all claims.
  - The Loan tile is hidden while any loan is active.
  - With several open claims, the tile goes to the **most recently submitted** one (latest `CreatedDate`), with no choice step.
  - Guests have no access to the site, so there is no guest case to handle.
- **Proposed solution (to be designed at the start of the issue):**
  - A new LWC for Home with the two tiles.
  - A read-only Apex method returns whether the customer has an open claim, the Id of the most recent one, and whether the Contact has an active loan, all worked out server-side from the running user.
  - Navigation goes to the Case record page with `NavigationMixin`.
  - It refreshes on `c/claimEvents` `subscribeToClaimSubmitted`, the same pattern as `myVehicleClaims`.
  - The open decisions are listed in the requirements' Open Decisions.
- **Reuse:** `CustomerClaimsController.getMyClaims()` (user-mode claims query, newest first); `VehicleLoanController.getActiveLoans(contactId)` (per-Contact active-loan query, private today); `c/claimEvents`; the request ordering in `myVehicleClaims.js`.
- **Effort:** M.

**Acceptance criteria for Issue 10. Done when, all of these hold:**

1. **Requirements settled:** the Issue 10 open decisions in `VEHICLE_LOAN_LWC_REQUIREMENTS.md` are decided with you and recorded before building.
2. **Tile visibility (Jest and Apex tests):**
   - no open claim → no Loan tile;
   - an open claim and no active loan → Loan tile shown;
   - an active loan on any claim → no Loan tile.
3. **Server-side eligibility:** the Apex method derives everything from the running user's Contact and accepts no Contact or Case Id from the browser. It has tests for: customer with no claims; open claim with no loan; active loan; closed claims only; another customer's data is never returned; internal user (no Contact).
4. **Navigation:** the Loan tile opens the My Vehicle Claims page of the customer's most recently submitted open claim (Apex test with two open claims checks the newest is chosen). My open claims opens the agreed list. Jest asserts the navigation targets.
5. **Refresh:** submitting a first claim on Home makes the Loan tile appear without a page reload (Jest, through `claimEvents`).
6. **Live check on the site:** as a real customer, the tiles appear as described, the Loan tile leads to the claim page with the vehicle list, and after a reservation (done under 8b's safeguards, or none if you prefer) the Loan tile is gone.
7. **No secrets; suite and scans:** full Apex suite 0 failures, coverage at or above 85%, no new High findings, ESLint and Prettier pass.
8. **Delivery:** own branch from `main`, reviewed before commit, merged and pushed after approval; plan updated.

### 9. sf-verify Stop hook (was in `stash@{0}`, now restored)

- **Summary:** the skill and hook script are stashed (4 files: `.claude/hooks/verify-on-stop.sh`, `.claude/skills/sf-verify/{SKILL.md,reference.md,scripts/check.sh}`). `check.sh` runs four gates: `apex-tests`, `lwc-tests`, `static-analysis` (fails at severity 2 or worse) and `tests-not-weakened`. The hook is not wired in `settings.local.json`. One thing blocks a green run today: the High finding at `VehicleLoanApiClient.cls:186` (the metadata query) still fails `static-analysis`.
- **Proposed solution (decided 2026-10-12: try USER_MODE first):** (1) restore the stash. (2) Add `WITH USER_MODE` to the metadata query. Portal customers and agents already hold the type access from Issue 1, so it should pass; if it does, no suppression is needed and the finding is fixed rather than hidden. (3) Only if user mode breaks the tests or the live call, fall back to a documented `@SuppressWarnings('PMD.ApexCRUDViolation')` whose reason is true (a single known record, read by design). Do not claim the secrets are "protected from users", because Issue 1 gave users read access. (4) Run `check.sh` and confirm all four gates PASS. (5) Wire the Stop hook in `.claude/settings.local.json`. (6) Prove it works: a deliberately broken change blocks the stop; a clean one does not.
- **Open points to watch:** the hook runs the full Apex suite on every stop that touched `force-app`, which takes minutes; restrict it if too slow. `check.sh` and the hook run under Git Bash, where some `sf` commands misbehave (a deploy from Git Bash failed with a `C:\Program` path error on 2026-10-12), so the negative test in criterion 5 doubles as a check that the hook's shell works.
- **Effort:** S.

**STATUS: DONE (2026-10-12), branch `chore/issue-9-sf-verify-hook`.**

- **Static analysis:** `WITH USER_MODE` on the metadata query passed, so no suppression was needed. High findings are now 0. The settings query is not run as a portal user by any unit test (they inject fake settings), so a throwaway test (deleted afterwards) ran the same query as a real portal customer holding `Vehicle_Claim_Portal_Access`, as an agent given `Vehicle_Loan_Internal_Access`, and as admin. All three read the record with the secret fields non-blank. The read-only live call (OAuth token + `getVehicles`) returned 10 vehicles.
- **Two bugs found and fixed in the stashed files:** (1) from Git Bash, `sf` exits 1 even on success (`sf --version` included), so `check.sh` reported `apex-tests` and `static-analysis` FAIL while they passed; `check.sh` now goes through `cmd //c sf` on Windows. (2) `jq` is not installed, so the hook's loop guard silently did nothing; it now uses `grep`.
- **Gates:** `bash .claude/skills/sf-verify/scripts/check.sh` prints PASS for all four gates (109 tests, 0 failures, org-wide coverage 85%).
- **Hook tests:** loop guard exits 0 instantly. A clean change exits 0. A test with an assertion removed exits 2 and prints `GATE tests-not-weakened: FAIL`; after restoring the file the stop is allowed. A clean checkout of `main` exits 0 in under a second without running anything.
- **Run time:** one full verification took 66 s and another 225 s. Decision: keep the hook as is for now; restrict it if it gets in the way.
- **Wiring:** the Stop hook is in `.claude/settings.local.json`, which is gitignored, so it applies on this machine only. Another machine needs the same entry.

**Acceptance criteria for Issue 9. Done when, all of these hold:**

1. `git stash pop` restores the 4 files; the stash is dropped and `git stash list` is empty. Nothing else in the working tree changes.
2. `bash .claude/skills/sf-verify/scripts/check.sh` prints `GATE apex-tests: PASS`, `GATE lwc-tests: PASS`, `GATE static-analysis: PASS` and `GATE tests-not-weakened: PASS`, copied into the issue.
3. **How static-analysis passes.** First choice: `WITH USER_MODE` on the metadata query, with all tests passing as the customer, agent and admin, and the read-only live call (`new VehicleLoanApiClient().getVehicles()` via anonymous Apex) still returning vehicles. If that is not possible, the fallback is a documented suppression with a truthful reason. Never by lowering the severity threshold or excluding files. `git diff` is limited to that change and reviewed by you before commit.
4. The hook is wired in `.claude/settings.local.json` (Stop event, running `verify-on-stop.sh`), and `jq` is confirmed available (the script needs it).
5. **Negative test:** a throwaway change that breaks a test makes the hook block the stop (exit 2 with the failing `GATE` lines); reverting it lets the stop through. Both outcomes are shown.
6. **No-op test:** a stop with no changes under `force-app` exits 0 without running the suite.
7. The run time of a full verification is measured and written in the plan, with a decision on whether to restrict when the hook runs.
8. Own branch from `main`, reviewed before commit, merged and pushed after approval; plan updated. The `.claude/settings.local.json` change is committed only if you want it shared.

### 11. Case assignment Flow updates the Case after save (analyzer `flow:SameRecordUpdate`, added 2026-10-13)

- **Summary:** `Case_Assignment_Vehicle_Claims` is a record-triggered **after-save** Flow on Case create. For Vehicle Claims Cases, it sets `OwnerId` to `$Record.Contact.Account.OwnerId` with an Update Records element on the same record. That causes a second save of every new claim, so triggers, other flows and validation rules run twice. The analyzer reports it as Moderate.
- **Proposed solution:** make it a **before-save** (fast field update) Flow that assigns `$Record.OwnerId` directly; there is no separate DML. First confirm that before-save can read `$Record.Contact.Account.OwnerId` on create in this org. If it can't, fall back to an after-save Get Records + assignment, or stop and decide with you.
- **Effort:** S.

**Acceptance criteria for Issue 11. Done when, all of these hold:**

1. The flow is a before-save record-triggered Flow with no Update Records element on the triggering Case, and the `flow:SameRecordUpdate` finding is gone.
2. **Same outcome:** an Apex test inserts a Vehicle Claims Case for a Contact whose Account is owned by a given user, and asserts the Case owner is that user. A non-Vehicle-Claims Case keeps its default owner. The test is written and run **before** the change, to prove the current behaviour, and again after.
3. Claim submission through `createVehicleClaim` / `VehicleClaimController` still works: its existing tests pass, plus one manual claim on the site whose owner is checked.
4. Full Apex suite 0 failures, coverage at or above 85%, no new High findings.
5. Own branch from `main`, reviewed before commit, merged and pushed after approval; plan updated.

## Accepted analyzer findings (reviewed 2026-10-13)

The `check.sh` gate fails only on High (severity 2) or worse. The 2026-10-13 run on `main` found 0 High, 39 Moderate, 84 Low and 2 Info. Everything except the Flow finding (Issue 11) was reviewed and **accepted, no action**. Re-review only if a count rises or a new rule appears.

| Rule (count)                                                                              | Where                                                                     | Why accepted                                                                                                       |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `ApexUnitTestClassShouldHaveAsserts` (2)                                                  | `VehicleClaimControllerTest`, `VehicleLoanApiResponseTest`                | False positive: the asserts are in helper methods (`assertMissingRecordTypeConfiguration`, `assertInvalidVehicle`) |
| `CyclomaticComplexity`, `ExcessiveParameterList`, `NcssCount` (19)                        | Loan controller, API client, claim controller, test helpers               | Mostly guard clauses and test helpers; refactoring adds risk for no user benefit                                   |
| `AvoidBooleanMethodParameters` (5), `PropertyNamingConventions` (4)                       | `VehicleLoanActionResult`, `VehicleLoanContext`, `VehicleLoanApiResponse` | Simple result flags; property names must match the remote API's JSON                                               |
| ESLint `no-unexpected-wire-adapter-usages` (5), `no-inline-disable` (3)                   | Jest tests only                                                           | Standard LWC test idioms (wire mocks, the `setTimeout` flush helper)                                               |
| `OperationWithLimitsInLoop` (1)                                                           | `VehicleClaimControllerTest`                                              | Test-only code                                                                                                     |
| `ApexDoc` (55), `ApexUnitTestClassShouldHaveRunAs` (34), `AvoidDebugStatements` (4) — Low | Various                                                                   | Documentation and style; the debug statements are deliberate error logging                                         |
| `NoTrailingWhitespace` (2) — Info                                                         | `AnnualAgentResetBatch`, `MonthlyAgentCommissionCalculationBatch`         | Trivial; fix when those files are next touched                                                                     |

## Recommended order

1. ~~**Issue 2, Part B: `.gitignore` for the credentials record**~~ **DONE**, on `main` (`853f1e9`).
2. ~~**Issue 1**~~ **DONE** (`93c7c13`). Diagnosed, granted access, re-enabled the tests.
3. ~~**Issue 2 Part C and issue 4 together**~~ **REPLACED** (`02863cc`): accept and document, no migration.
4. ~~**Issue 5**~~ **DONE** (`e240cb1`). Both loan classes at 89%.
5. ~~**Issue 3**~~ **DONE** (`a8fb0ad`, pushed). High findings now 1.
6. ~~**Issue 6**~~ **DONE** (`f7e62d9`). `Vehicle__c` object, fields, layouts, rules and `Case_Record_Page` now in source.
7. ~~**Issue 9**~~ **DONE** (branch `chore/issue-9-sf-verify-hook`). Metadata query in user mode, all four gates PASS, Stop hook wired locally.
8. ~~**Issue 7**~~ **DONE** (branch `fix/issue-7-remove-local-get-vehicles`). Option A: local `getVehicles()` removed.
9. ~~**Issue 8a**~~ **DONE** (`be1f7c7`, `a128dc0`). Internal component; agent and admin views confirmed.
10. **Issue 8b** (M). The component on the customer site's My Vehicle Claims page, then the live test.
11. **Issue 10** (M). Customer Home tiles, after 8b.
12. **Issue 11** (S). Case assignment Flow to before-save. It is independent of 8b and 10, so it can be done at any time.

Each remaining item gets its own branch from the current `main`, reviewed before commit, merged and pushed after approval.

## Decisions log

- 2026-10-11: credential rotation is not needed (private repo, developer org, practice scenario).
- 2026-10-11: the `customMetadata/` record is gitignored and never committed.
- 2026-10-11: portal customers and agents can read the callout-settings type (needed to fix Issue 1). Known trade-off, accepted for a practice org.
- 2026-10-11: live `updateVehicle` and a real portal login are deferred to Issue 8b.
- 2026-10-12: the Named Credential migration (Issues 2C and 4) is dropped. The `ApexSuggestUsingNamedCred` findings are accepted and documented (`02863cc`).
- 2026-10-12: Issue 9 tries `WITH USER_MODE` on the metadata query before any suppression.
- 2026-10-12: Issue 8 is split into 8a (internal) and 8b (customer site and live test).
- 2026-10-12: this plan lives in the repo as `docs/issue-remediation-plan.md`, the master copy.
- 2026-10-12: Issue 6 retrieves the whole `Vehicle__c` object and `Case_Record_Page`; the Experience Cloud template classes are ignored.
- 2026-10-12: Issue 9 finished with `WITH USER_MODE` (no suppression). The hook's wiring stays in the gitignored `.claude/settings.local.json`.
- 2026-10-12: Issue 7 option A: the local `getVehicles()` is removed. Availability comes from the remote API through `getLoanContext`. A loan-history panel can be added later if wanted.
- 2026-10-13: GitHub #5. The requirements only let the customer or the Contact-owning agent use the loan component, so administrators were blocked on cases they did not own. The requirements now add a `Manage_All_Vehicle_Loans` custom permission (granted by the `Vehicle_Loan_Manage_All` permission set). Holders can view, reserve and return loans on any qualifying Case. Portal users never get this bypass.
- 2026-10-13: Issue 8a is closed; the final `check.sh` run on `main` passed (113 Apex tests, 85% coverage, 54 Jest tests, 0 High).
- 2026-10-13: the customer site is TI Vitesse Insurance Ltd (`/customers`). 8b places the loan component on its My Vehicle Claims Case record page.
- 2026-10-13: 8b is done before the Home tiles (new Issue 10), because the Loan tile leads to the page 8b sets up.
- 2026-10-13: the customer site uses the same per-Contact loan rule as the internal page (one active loan per Contact across all claims). No backend rule change.
- 2026-10-13: the Loan a vehicle tile goes to the My Vehicle Claims page of the customer's most recently submitted open claim (no choice step), and is hidden while a loan is active.
- 2026-10-13: an active loan can be returned from the page of any of the Contact's open claims, not only the claim it was reserved on (customer and internal pages alike). This is a controller and test change, done in 8b.
- 2026-10-13: guests have no access to the customer site, so no guest-specific requirements are needed.
- 2026-10-13: analyzer review. The after-save Case assignment Flow becomes Issue 11; every other Moderate, Low and Info finding is accepted (see "Accepted analyzer findings").
- **Pending:** none. Next is Issue 8b.

## Parked (not scheduled)

- The `Test.isRunningTest()` branch in `VehicleLoanApiClient.getOAuthSettings()` (line 182) lets tests inject settings. It pre-dates this work. Replacing it with injection is a possible cleanup.
- Still uncovered in `VehicleLoanApiClient`: the vehicle-response `TypeException` catch (lines 38-41) and the OAuth-settings query lines (186-198, 215-221).
- Four vault notes in `00 Inbox/` are waiting for your review (not part of the repo).

## Critical files

- `force-app/main/default/classes/VehicleLoanApiClient.cls` (suppressions at lines 9 and 54, metadata query at 186)
- `force-app/main/default/classes/VehicleLoanController.cls` (`getVehicles()` at 140-150)
- `force-app/main/default/lwc/vehicleLoanLWC/` (component, meta file)
- `force-app/main/default/objects/Vehicle__c/validationRules/` and `fields/`
- `force-app/main/default/permissionsets/Vehicle_Claim_Portal_Access.permissionset-meta.xml`, `Vehicle_Loan_Internal_Access.permissionset-meta.xml`
- `.claude/` (stash: sf-verify skill and hook), `.claude/settings.local.json`

## Verification per issue

- **Issue 6:** rule count in source equals the org's 7; scratch `diff -r` result recorded; full suite 109 tests, 0 failures.
- **Issue 9:** `bash .claude/skills/sf-verify/scripts/check.sh` prints four PASS lines; the hook blocks a broken change and allows a clean one.
- **Issue 7:** the grep for `VehicleLoanController.getVehicles` finds nothing (if A); full suite 0 failures.
- **Issue 8a:** `npm run test:unit` passes; the component appears on the internal Case record page.
- **Issue 8b:** real customer login completes reserve and return, and the remote vehicle returns to its recorded "before" state.
- **Issue 10:** Jest and Apex tests for tile visibility and eligibility pass; a real customer sees the tiles behave as described on Home.
- **Issue 11:** the owner-assignment Apex test passes before and after the change; `flow:SameRecordUpdate` no longer reported.
- **Every issue:** full `RunLocalTests` 0 failures, org-wide coverage at or above 85%, no new High findings, and a diff you reviewed before commit.
