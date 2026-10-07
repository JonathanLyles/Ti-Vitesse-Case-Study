# Vehicle Loan Reservation Integration Requirements

## Functional Requirements

### Vehicle availability

FR-1. The integration shall retrieve the list of available loan vehicles from the
other Salesforce org using its `GET /services/apexrest/v1.0/getVehicles/`
operation through an administrator-configured Named Credential.

FR-2. The integration shall use the vehicle data returned by that GET request,
including registration number, make, model, and year when supplied. Make/model
filtering is performed in this org.

FR-3. This sprint shall deliver the callable integration and the related
`Vehicle__c` updates only. A booking or cancellation user interface is out of
scope.

### Booking

FR-4. The reservation operation shall use the selected vehicle returned by the
availability GET, the related claim, customer Contact, start date, and end date
as local inputs. It shall validate that the start date is not before today and
that the end date is at least one day after the start date. Only the selected
vehicle's registration number, as returned by the GET, shall be sent in the
reservation POST; the claim, Contact, dates, and other vehicle details shall
not be sent.

FR-5. An internal agent may book only for a Contact record that the agent owns
(`Contact.OwnerId` matches the agent's user Id). An authenticated Experience
Cloud customer may book only for the Contact record associated with their own
user (`User.ContactId`). In either case, the Case must be linked to that same
Contact. The operation shall verify these relationships using server-side
record data; caller-supplied identifiers alone do not establish authorization.

FR-6. After validating the request, the integration shall POST only the
selected vehicle's registration number, obtained from the availability GET, to
`/services/apexrest/v1.0/updateVehicle/{RegistrationNumber}` using the Named
Credential. No claim, Contact, date, or other vehicle details shall be sent in
the POST.

FR-7. Any HTTP `2xx` response shall confirm the booking. After that response,
this org shall update the corresponding `Vehicle__c` record with the claim,
Contact, start and end dates, and the vehicle information returned by the
availability GET request.

FR-8. A failed booking shall not fail, roll back, or otherwise change the claim.
If booking ultimately fails, the callable operation shall return a failure
outcome that a future UI can use to tell the user to retry or select another
vehicle.

### Cancellation

FR-9. The cancellation operation shall POST the selected vehicle's registration
number to the same `updateVehicle` operation. Under the practice-service
assumption, another successful POST represents cancellation.

FR-10. Any HTTP `2xx` response to the cancellation POST shall confirm
cancellation. This org shall clear the `Vehicle__c` Contact, Case, start date,
and end date values for that booking.

FR-11. Cancellation shall follow the same authorization rules as booking: an
agent may cancel only for a Contact they own, and an authenticated customer may
cancel only for the Contact associated with their own user. The booking's Case
and Contact must match.

### Retries, recovery, and logging

FR-12. For a booking or cancellation POST, the integration shall make one
initial call and may make up to five immediate retries (six attempts total) for
retryable failures. A `4xx` response shall not be retried; a `5xx` response and
a callout exception or timeout with no HTTP response shall be retried. No delay
is required between attempts.

FR-13. When a POST returns `2xx` but the local `Vehicle__c` update fails, the
vehicle shall be considered booked based on the successful POST response. The
integration shall not repeat the callout. It shall persist a pending local
update and retry only that update asynchronously, for up to six total local
update attempts. The operation shall expose that the vehicle is booked but its
local record update is pending.

FR-14. If local reconciliation is not successful within the allowed attempts,
the vehicle shall remain considered booked based on the successful POST, while
the local `Vehicle__c` record remains out of sync. The integration shall retain
a log requiring support follow-up. A local update failure shall not be
reported as though the remote POST or booking failed.

FR-15. The integration shall write a record to a dedicated integration log
object for each operation, including its outcome and diagnostic information:
action, related claim and vehicle identifiers, selected registration number,
attempt count, HTTP status when available, timing, sanitized error details, and
final outcome. Logs shall not contain credentials, authorization headers, or
other authentication secrets.

## Non-Functional Requirements

NFR-1. The integration shall use an administrator-configured Named Credential
for the remote endpoint and authentication. Secrets shall not be embedded in
Apex, source-controlled metadata, or log records.

NFR-2. The integration shall enforce caller authorization for both internal
agents and Experience Cloud customers using the Contact owner relationship for
agents and the running user's associated Contact for customers. A caller must
not be able to book, cancel, or update another customer's vehicle by changing
request identifiers.

NFR-3. The remote callout and local Salesforce update shall have clearly
separated outcomes: a remote `2xx` is a confirmed remote response; a failed
local update after that response is pending reconciliation, not a reason to
repeat the callout.

NFR-4. The API shall return structured outcomes that distinguish success,
pending local update, and failure, with a user-safe message suitable for a
future UI. Detailed sanitized diagnostics shall be available in the integration
log for support.

NFR-5. Integration logs shall be durable and searchable by the related claim,
vehicle, action, and outcome. Access to logs shall be restricted to
appropriately authorized support or administrative users.

NFR-6. The implementation shall not add a user interface in this sprint and
shall remain callable by a future agent and Experience Cloud booking
experience.

## User Stories and Acceptance Criteria

### US-1: Retrieve and filter available vehicles

As an agent or authenticated customer beginning a vehicle-loan request, I want
the integration to retrieve available vehicles so that a future booking
experience can let me choose by make and model.

**Acceptance criteria**

- Given the Named Credential is configured and the remote service returns a
  valid vehicle list, when the availability operation is called, then the
  returned registration number, make, model, and supplied year are available
  to the caller.
- Given a make/model filter, when filtering is applied, then only matching
  vehicles from the retrieved available list are returned.
- Given the remote service returns an error or an invalid response, when
  availability is requested, then the operation returns a failure outcome and
  writes a diagnostic integration log without exposing credentials.

### US-2: Book a vehicle for a claim

As an authorized agent or customer, I want a selected available vehicle
associated with a claim and booking dates so that the loan details are recorded
in this org after the remote service confirms the request.

**Acceptance criteria**

- Given an authorized agent and a claim belonging to one of that agent's
  customers, or a customer and their own claim, when the request is submitted
  with a valid vehicle and dates, then the integration POSTs the vehicle's
  registration number to the remote `updateVehicle` operation.
- Given a start date before today, when a booking is requested, then it is
  rejected without making the POST.
- Given an end date earlier than one day after the start date, when a booking
  is requested, then it is rejected without making the POST.
- Given the remote POST returns any `2xx` response and the local update
  succeeds, then the matching `Vehicle__c` is updated with the returned vehicle
  information, Contact, Case, start date, and end date, and the operation
  reports success.
- Given the remote POST returns `4xx`, then no retry is made and the operation
  reports failure.
- Given the remote POST returns `5xx`, then up to five retries are made with no
  delay; a later `2xx` reports success, and exhaustion reports failure.
- Given a callout exception or timeout produces no HTTP response, then up to
  five retries are made with no delay; a later `2xx` reports success, and
  exhaustion reports failure.
- Given the remote POST returns `2xx` but the local `Vehicle__c` update fails,
  then the vehicle is considered booked, the POST is not repeated, a pending
  local update is persisted, local reconciliation is attempted asynchronously
  up to six total attempts, and the operation reports that booking is confirmed
  while the local update is pending.
- Given booking fails after the allowed callout attempts, then the claim
  remains unchanged and the caller receives an outcome suitable for prompting
  the user to retry or select another vehicle.
- Given any booking outcome, then an integration log is written with the
  action, related record identifiers, attempt count, status/timing when
  available, sanitized diagnostics, and final or pending outcome.

### US-3: Cancel a vehicle booking

As an authorized agent or the customer who owns a booking, I want to cancel it
so that the vehicle's booking details are cleared after the remote service
confirms cancellation.

**Acceptance criteria**

- Given an authorized agent acting for the booking's customer or the customer
  acting on their own booking, when cancellation is requested, then the
  integration POSTs the vehicle registration number to the same
  `updateVehicle` operation.
- Given the cancellation POST returns any `2xx` response, then cancellation is
  considered confirmed. If the local update succeeds, the Contact, Case, start
  date, and end date are cleared on the associated `Vehicle__c`.
- Given the cancellation POST fails, then retry rules are applied as for
  booking, local booking fields are not cleared before remote confirmation,
  and the outcome is logged.
- Given a local clear operation fails after remote `2xx`, then the callout is
  not repeated; cancellation remains confirmed, only local reconciliation is
  retried, and the outcome reports confirmed cancellation with the local
  update pending.

### US-4: Diagnose integration outcomes

As a support person, I want durable logs for booking, cancellation, and local
reconciliation so that I can diagnose failures without access to secrets.

**Acceptance criteria**

- Given any attempted operation, then a dedicated integration log record
  captures the action, claim/vehicle identifiers, registration number,
  attempt count, HTTP status if available, timing, sanitized error details,
  and outcome.
- Given a local reconciliation remains unsuccessful after six total attempts,
  then the log remains available and clearly indicates that support action is
  required.
- Given any logged error, then credentials, authorization headers, and
  authentication secrets are absent.

## Assumptions

- The other Salesforce org is the source of the available vehicle list. Its GET
  operation returns only vehicles available for selection.
- The service endpoints and response shapes are those in the supplied
  web-service specification: `getVehicles` returns registration number, make,
  model, and year; `updateVehicle/{RegistrationNumber}` returns a response.
- The remote service is a practice integration. A successful POST is treated
  as confirmation; the service does not need to persist booking data for this
  exercise. Duplicate POSTs are safe under this assumption, and concurrent
  selection of the same vehicle is not guarded against.
- `Vehicle__c` is the local Salesforce object to update. The local vehicle
  record corresponding to the selected registration is expected to exist.
- A `2xx` response confirms success regardless of response body. The
  cancellation POST uses the same endpoint and is assumed to represent a
  cancellation in this exercise.
- “Up to five retries” means five retries after the initial attempt, for six
  total callout attempts. The same six-attempt maximum applies to asynchronous
  local update reconciliation.
- Callout exceptions and timeouts with no HTTP response are retryable, up to
  the same six total callout attempts.
- Retry attempts occur immediately, with no configured delay.
- Booking failure has no effect on the already-created claim. A future UI will
  present a failure message asking the user to retry or select another vehicle,
  and a pending message while local reconciliation is underway.
- The booking and cancellation UI is out of scope for this sprint.
- A Named Credential will be configured outside the feature implementation;
  this document contains no credential values.

## Risks

- The specified remote POST only confirms a response and does not persist a
  reservation in the other org. The booking record and booking state therefore
  exist only in this org for this exercise.
- The GET response is a snapshot. Since the remote list is not updated when a
  vehicle is selected, two users can select the same vehicle; this sprint will
  not prevent that.
- A callout can succeed remotely while its response is lost. The retry policy
  may submit the same POST again; this is accepted only because duplicate POSTs
  are considered safe in this exercise.
- Local field names, record types, and the mechanism for matching a remote
  registration number to an existing `Vehicle__c` need verification. Incorrect
  matching could update the wrong record or prevent reconciliation.
- If the remote POST returns `2xx` and all local reconciliation attempts fail,
  the remote confirmation and local state will temporarily disagree and
  require support follow-up.
- The supplied authentication example and the requested Named Credential
  configuration must be reconciled during setup. Misconfiguration can prevent
  every callout; authentication secrets must remain outside logs and source.
- Immediate retries can increase latency and remote load. Salesforce callout
  limits and transaction timeouts must be respected.
- The practice API describes the same POST for booking and cancellation without
  an explicit action parameter. A real service with this contract could not
  reliably distinguish those operations.
- “Log everything” is constrained to operational diagnostics. Logging
  credentials, authorization headers, or unnecessary personal information
  would create a security and privacy risk.

## Open Decisions

- What exact Apex/API contract should callers use for availability, booking,
  cancellation, and structured outcomes (for example, Apex service methods
  versus `@AuraEnabled` methods)?
- What are the authoritative API names and types on `Vehicle__c` for year,
  booking dates, and booking state? Does a matching Loan Vehicle record already
  exist for every registration returned by the GET operation, and what should
  happen if it does not?
- How should `3xx` responses be handled? The agreed rules specify no retry for
  `4xx` and retry for `5xx`, but do not explicitly classify redirects.
- What timezone/business-date rule defines “today” for start-date validation?
- Which exact fields should the integration log object expose, and what
  retention period and access policy should apply?
- Which endpoint and Named Credential configuration should be used in each
  Salesforce environment, and what authentication mechanism will the
  administrator configure?
- Should a confirmed cancellation also clear any explicit booked/status field
  or returned vehicle details beyond Contact, Case, start date, and end date?
