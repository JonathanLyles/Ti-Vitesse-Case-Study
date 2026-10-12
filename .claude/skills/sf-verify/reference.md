# sf-verify reference

## Coverage bar
- Salesforce requires 75% org-wide coverage to deploy to production. That is the floor, not the target.
- Our bar: **85% for every Apex class or trigger changed in this task.**
- Find per-class coverage in the "Code Coverage by Class" table of the `sf apex run test` output.
- New or changed logic needs tests for: a single record, a bulk case (200 records),
  a negative case (bad input or a validation error), and a permission case
  (`System.runAs` with a restricted user) where sharing or FLS matters.

## What counts as a weakened test
Any of these needs an explicit reason in the report, or must be reverted:
- An assertion removed, or made looser (e.g. `assertEquals` → `assertNotEquals(null, …)`).
- An expected value changed to match new output, without the user having asked for that behaviour change.
- A test method deleted or commented out.
- `@IsTest(SeeAllData=true)` added.
- `Test.isRunningTest()` branches added to production code.
- A try/catch in a test that swallows the failure instead of asserting on it.

The script only catches the first and fourth automatically. Check the rest while reading the diff.

## Reading the gates
- `static-analysis` severities: 1 Critical, 2 High, 3 Moderate, 4 Low, 5 Info. The gate fails at 2 or worse;
  mention any 3s in the report without failing.
- If `apex-tests` fails because no default org is set, ask the user for the org alias rather than guessing.
