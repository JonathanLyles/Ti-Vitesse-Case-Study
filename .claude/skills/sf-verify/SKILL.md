---
name: sf-verify
description: Verify a Salesforce change before calling it done. Use whenever you finish changing Apex classes, triggers, LWC, or Flow metadata under force-app, and before telling the user the task is complete or proposing a commit.
---

# Verify a Salesforce change

1. From the project root, run `bash .claude/skills/sf-verify/scripts/check.sh`.
   If the user named an org alias, pass it as the first argument.
2. Read the full diff with `git diff main`. Confirm each changed file matches
   what was asked, and flag anything out of scope.
3. If the script reports weakened tests, do not call the task done: restore
   the test, or explain exactly why the change is correct.
4. If any class you changed has coverage under the bar in
   [reference.md](reference.md), add tests and run the script again.
5. Report:
   - **Result:** PASS or FAIL
   - **Gates:** the PASS/FAIL line for each gate, copied from the script output
   - **Evidence:** tests run, failures, and coverage for each changed class
   - **Diff check:** files changed, and anything that looks out of scope

Report PASS only if every gate printed PASS in this run.
