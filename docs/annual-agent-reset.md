# Annual Agent Reset

## Requirement

For Agents (Accounts), on January 1st every year:

> Total Loss Vehicles Yearly = 0

## Solution

The requirement is implemented with two Apex classes: a **Batch Apex** class that does the reset, and a **Schedulable** class that starts it every January 1st.

| Class | Role |
|---|---|
| `AnnualAgentResetBatch` | Selects every Account where `Is_Agent__c = true` and sets `Total_Loss_Vehicles_Yearly__c` to 0. When finished, it emails the user who started the job a summary of batches processed and failures. |
| `AnnualAgentResetSchedulable` | Runs on a schedule and starts `AnnualAgentResetBatch`. |
| `AnnualAgentResetBatchTest`, `AnnualAgentResetSchedulableTest` | Unit tests. Both classes have 100% coverage. |

### How it runs

```
January 1st, 00:00
  └─ AnnualAgentResetSchedulable.execute()
       └─ Database.executeBatch(new AnnualAgentResetBatch())
            ├─ start()   → query all agent Accounts
            ├─ execute() → set Total_Loss_Vehicles_Yearly__c = 0, 200 records at a time
            └─ finish()  → email a job summary to the user who started it
```

### Scheduling the job

The job is scheduled once, from Anonymous Apex, and then repeats every year:

```apex
System.schedule(
    'Annual Agent Reset',
    '0 0 0 1 1 ?',   // 00:00:00 on January 1st, every year
    new AnnualAgentResetSchedulable()
);
```

The time is based on the time zone of the user who schedules the job, so that user's time zone should match the business's. The job shows under **Setup → Scheduled Jobs**.

## Why these decisions

### Why Batch Apex for the reset

- **It scales with the number of agents.** A single transaction can update at most 10,000 records. Batch Apex splits the work into chunks of 200 records by default, and each chunk gets its own governor limits. The job works the same with 50 agents or 500,000.
- **One bad record doesn't stop the rest.** If a chunk fails, for example because of a validation rule, only that chunk is rolled back and the others still commit.
- **Failures are visible.** The class implements `Database.RaisesPlatformEvents`, so unhandled errors publish a `BatchApexErrorEvent` that can be monitored or handled automatically. `finish()` also emails the user who started the job the number of failures.
- **It can run on demand.** An admin can run `Database.executeBatch(new AnnualAgentResetBatch())` to rerun the reset outside the schedule, for example after a failed run.

### Why a separate Schedulable class

- **Salesforce's built-in scheduler supports this directly.** A yearly schedule is one cron expression, with no external tool or middleware.
- **Keeping scheduling separate from the work.** The Schedulable only starts the batch. The reset logic stays in one place and can be tested, run, or rescheduled on its own.
- **A Schedulable shouldn't do the updates itself.** Its `execute()` runs as a single transaction with the same record limits, so it has the same scaling problem as a single update. Starting a batch from it avoids that.

### Why not a Scheduled Flow

A Scheduled Flow could also set a field once a year without code. Apex was chosen because:

- **Record volume:** a Scheduled Flow has daily limits on the number of records it processes, while Batch Apex has no practical limit here.
- **Testing:** the Apex solution comes with unit tests that check the result, not only that the code ran.
- **Error handling:** the batch reports failures by email and through platform events.

A Scheduled Flow would be a reasonable choice if the org prefers declarative tools and the number of agents stays small.

### Other design choices

- **Selecting all agents regardless of sharing.** The query in `start()` runs in system mode, so every agent Account is selected even if the running user can't see all of them. This means the job must run as a user who can edit those records, such as an admin or integration user.
- **Only agent Accounts are changed.** The query filters on `Is_Agent__c = true`, and the tests confirm that non-agent Accounts keep their values.

## Tests

| Test | Checks |
|---|---|
| `resetsAgentTotalsToZero` | Every agent's total is set to 0. |
| `leavesNonAgentsUnchanged` | Non-agent Accounts keep their totals. |
| `jobCompletesWithoutErrors` | The batch completes with no errors, which also runs `finish()`. |
| `handlesNoAgents` | The batch completes when there are no agents. |
| `schedulesJob` | The Schedulable registers with the January 1st cron expression. |
| `executeEnqueuesBatch` | The Schedulable starts exactly one `AnnualAgentResetBatch` job. |

## Possible improvements

- **Skip Accounts already at 0.** Adding `AND Total_Loss_Vehicles_Yearly__c != 0` to the query would avoid updating records that don't need it.
- **Store the schedule in configuration.** The cron expression could live in Custom Metadata so admins can change it without code.
