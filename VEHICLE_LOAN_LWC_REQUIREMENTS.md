# Vehicle Loan LWC Requirements

## Functional Requirements

### Vehicle availability

FR-1. The component shall retrieve available vehicles through the secured
`VehicleLoanController.getLoanContext(caseId)` operation. The controller
validates access to the Case and obtains available vehicles through
`VehicleLoanApiClient.getVehicles()`, which sends a `GET` request to
`callout:TiVitesseNamedCredential/getVehicles/` and parses a JSON array
containing registration number, make, model, and year.

FR-2. The component shall display the returned registration number, make,
model, and year when supplied. The existing response model exposes these
properties as `RegistrationNumber`, `Make`, `Model`, and `YearOfVehicle`.

FR-3. The component shall let users filter available vehicles by make, model,
and year.

### Component placement and eligibility

FR-4. The component shall be available on a Case record page and on the
Experience Cloud site.

FR-5. On the Experience Cloud site, the component shall be available only to
an authenticated customer with an active (not closed) `Vehicle_Claims` Case.
Any Case status qualifies unless the Case is closed. The customer may request
a loan only if their Contact has no active vehicle loan. If the Contact
already has an active loan, the component shall show that loan instead of
allowing another vehicle request.

FR-6. The component shall respect the `Customer Community Clone` profile and
the `Vehicle_Claim_Portal_Access` permission set when showing loan details.
The permission set shall grant access to the `Loan_Vehicle` record type and
read access to loan details, but shall not grant direct Vehicle edit access.
The secured server-side controller shall create and update loan records after
independently validating the user and Case.

FR-7. The component shall also be available on a Case record page to an
internal agent who owns the Contact associated with that Case. The agent may
view, reserve, and return a loan for that Contact, subject to the active Case
and one-active-loan-per-Contact rules.

### Reservation

FR-8. An authorized user shall be able to select an available vehicle and
request a reservation for the claim.

FR-9. After a successful reservation, the system shall create or update a
`Vehicle__c` loan record using the `Loan_Vehicle` record type, related to the
customer's Contact and Case, so it appears in the Contact's Vehicles related
list. The record shall be marked as an active loan by setting
`Loan_Active__c` to true. Registration number, make, model, and year shall be
populated from the selected vehicle returned by the availability service.
Because the availability response does not contain mileage or engine capacity,
the user shall enter both values before confirming the reservation.

FR-10. The reservation request shall invoke
`VehicleLoanApiClient.updateVehicle(registrationNumber)`. The client sends an
empty-body `POST` to
`callout:TiVitesseNamedCredential/updateVehicle/{RegistrationNumber}`. It
URL-encodes the registration number as a path segment and lets the configured
Named Credential provide authorization.

FR-11. The reservation shall be considered successful for any HTTP `2xx`
response. The response body shall not be used to determine success. The
component shall show a success confirmation only after receiving that
successful outcome.

FR-12. If the reservation call fails, the user shall receive a clear failure
message and be able to try again.

FR-13. If the reservation call succeeds but creation or update of the local
`Vehicle__c` loan record fails, the system shall report the remote reservation
as successful and present the local-record error separately. It shall not
report that the remote reservation failed.

### Existing loan and return

FR-14. When the authenticated customer or authorized internal agent's Contact
has an active loan, the component shall display the existing loan record and
its available details instead of the vehicle availability and reservation
form.

FR-15. The customer or authorized internal agent shall be able to return the
loaned vehicle. The server shall send another `POST` to the `updateVehicle`
endpoint using the loaned vehicle's registration number. Any HTTP `2xx`
response shall count as a successful return.

FR-16. After a successful return response, the system shall retain the
`Vehicle__c` loan record for history, set `Loan_Active__c` to false, and set
`Loan_End_Date__c` to the return date. The record shall remain in the
Contact's Vehicles related list.

FR-17. If the return call fails, `Loan_Active__c` shall remain true and
`Loan_End_Date__c` shall remain unchanged. The component shall show a failure
message that allows the user to retry.

## Non-Functional Requirements

NFR-1. Every server operation that retrieves claim or loan information,
reserves a vehicle, or returns a vehicle shall independently verify the
running user's identity and authorization using Salesforce records. For an
Experience Cloud customer, the Case's `ContactId` must match the running
user's `ContactId`. For an internal agent, the Case Contact's `OwnerId` must
match the running user's Id. In either flow, the Case must not be closed,
reservation must be rejected if the Contact already has an active loan, and a
return must target an active loan related to that Contact and Case. The server
shall not trust Case IDs, Contact IDs, registration numbers, loan-active
flags, or other authorization claims supplied by the browser.

Hiding or disabling a component in the LWC is only a user-interface behavior;
it is not an authorization check. A user can bypass the UI and invoke exposed
server methods directly or alter request values. Therefore, each Apex method
must derive and verify the running user's Contact or Contact-ownership
relationship and repeat the Case-status and active-loan checks before
returning protected data or making a callout.

NFR-2. An Experience Cloud user or internal agent shall not be able to view,
reserve, or return a vehicle for a Contact, Case, or loan they are not
authorized to access.

NFR-3. Authentication secrets and bearer tokens shall not be exposed to the
browser or included in user-visible errors. Vehicle API authorization shall
be provided by the existing server-side Named Credential and External
Credential configuration; no credentials or token parameters shall be
accepted from the component.

NFR-4. Reservation success and failure messages shall reflect the server-side
callout result. A non-`2xx` response or callout exception shall not be reported
as success.

## User Stories and Acceptance Criteria

### US-1: View available vehicles

As an eligible customer, I want to view available vehicles for an active Case
so that I can choose one to loan if my Contact does not already have an active
loan.

**Acceptance criteria**

- Given I am the authenticated customer associated with the Contact on an
  active `Vehicle_Claims` Case, or an internal agent who owns that Contact,
  and the Contact has no active vehicle loan, when I open the component, then
  I can see the available vehicles returned by the service.
- Given my Case is closed or I do not have an authorized Case, when I open the
  site, then I cannot access that Case's vehicle-loan information or actions.
- Given my Contact already has an active loan, when I open the component for
  an active Case, then I see the existing loan instead of the
  available-vehicle reservation form.
- Given the vehicle service returns a non-`2xx` response, when the list is
  requested, then the component shows an error rather than presenting the
  request as successful.

### US-2: Filter available vehicles

As a user viewing available vehicles, I want to filter by make, model, and
year so that I can find a suitable vehicle.

**Acceptance criteria**

- Given the vehicle list is displayed, when I apply a make, model, or year
  filter, then only vehicles matching the selected criteria are displayed.
- Given no vehicles match the selected criteria, then the component indicates
  that no matching vehicles were found.

### US-3: Reserve a selected vehicle

As an eligible customer or internal agent, I want to reserve a selected
vehicle for an active Case so that the customer can use a loan vehicle.

**Acceptance criteria**

- Given I am the authenticated customer associated with the Contact on an
  active Case, or an internal agent who owns that Contact, the Contact has no
  active loan, and I select an available vehicle and enter its mileage and
  engine capacity, when the reservation endpoint returns any HTTP `2xx`
  status, then I see a success confirmation and the active `Loan_Vehicle`
  `Vehicle__c` record is visible in the Contact's Vehicles related list with
  the entered values saved.
- Given the reservation endpoint returns a non-`2xx` status or the callout
  fails, then I see a failure message and can retry.
- Given I am neither the authenticated customer associated with the Case
  Contact nor an internal agent who owns that Contact, when I attempt to
  reserve a vehicle, then the server rejects the request without reserving it.
- Given I submit a registration number, then the server sends it as the
  encoded path segment and does not treat caller-supplied claim access as
  authorization.
- Given the Case is closed, I fail the applicable Contact authorization
  check, or the Contact already has an active loan, when I attempt to reserve
  a vehicle, then the server rejects the request without making the
  reservation callout.

### US-4: View and return an existing loan

As a customer with an active vehicle loan, or the internal agent who owns the
customer's Contact, I want to view the loan and return the vehicle so that the
loan can be marked complete while its record remains available for history.

**Acceptance criteria**

- Given my Contact has an active loan associated with an active Case, when I
  open the component as the customer associated with that Contact or its
  owning agent, then I can view the existing loan details and access a return
  action.
- Given I return the vehicle and the `updateVehicle` callout returns any HTTP
  `2xx` status, then the server sets `Loan_Active__c` to false, sets
  `Loan_End_Date__c` to the return date, preserves the `Vehicle__c` in the
  Contact's related list, and shows a return confirmation.
- Given the return callout fails, then `Loan_Active__c` remains true and
  `Loan_End_Date__c` remains unchanged, and I can retry.
- Given the return callout succeeds but updating the local `Vehicle__c` fails,
  then the system shall report remote return success separately from the
  local update failure and shall not claim the remote return failed.
- Given the loan is not associated with my Contact and Case, or I am neither
  that Contact's customer nor its owning agent, when I attempt to view or
  return it, then the server rejects the request.

## Assumptions

- `VehicleLoanController` is the LWC-facing server boundary. It derives the
  Contact from the authorized Case and the running user's identity.
- The existing `VehicleLoanApiClient` and `VehicleLoanApiResponse` are the
  integration components used by the controller.
- The `getVehicles` and `updateVehicle` methods use the
  `TiVitesseNamedCredential` and rely on its configured External Credential for
  authorization. The component neither accepts nor handles credentials or
  bearer tokens.
- The reservation callout is `updateVehicle`, and any `2xx` status is success;
  the response body is ignored.
- A Case qualifies for a loan request if it is not closed (`IsClosed = false`);
  no additional Case status restriction applies.
- The authenticated Experience Cloud customer's `User.ContactId` is expected
  to match the Case's `ContactId` for the customer-facing workflow.
- An internal agent is authorized for a Case when the agent owns the Contact
  associated with the Case (`Contact.OwnerId` matches the running user's Id).
- A Contact may have at most one active vehicle loan at a time, including
  across multiple Cases.
- A successful reservation shall be represented by a `Vehicle__c` loan record
  related to the Case and Contact and visible in the Contact's Vehicles
  related list. The active-loan field is `Loan_Active__c` (Checkbox). On
  return, the record is retained for history, `Loan_Active__c` is set to
  false, and `Loan_End_Date__c` (Date) is set to the return date. These field
  definitions are confirmed requirements but their metadata is not yet
  present in the repository.
- OAuth is already configured in the Salesforce org. The server-side
  integration shall use that configuration and shall not pass credential
  values or bearer tokens through the LWC.
- The vehicle service always returns a non-empty, valid vehicle list for this
  use case. Empty or malformed responses are outside this use case.
- The vehicle availability response does not include `Mileage__c` or
  `Engine_Capacity__c`; the user supplies those required values when
  reserving. Test fixtures use fake values and do not prepopulate production
  reservations.
- Stale availability, timeouts with an unknown outcome, and duplicate
  reservation attempts do not occur in this practice use case.
- `VehicleClaimController` creates a Case with record type
  `Vehicle_Claims` and status `New`, and creates a related Vehicle with record
  type `Damaged_Vehicle` for the logged-in user's Contact. Its current methods
  are `getVehicleRecordTypeId()` and `createClaim(Case, Vehicle__c)`; it does
  not currently expose vehicle-list or reservation operations.
- The loan operations are exposed by `VehicleLoanController`, not by the
  claim-creation controller. Its public methods independently authorize the
  current customer or Contact-owning internal agent and the active Case.
- The API client does not send its own Authorization header. Salesforce
  Named Credential configuration supplies server-side authorization.

## Risks

- The target org's External Credential principal and its user access are
  configured outside the repository and must be verified during deployment.
- The secured controller uses narrowly scoped system-mode queries and DML
  after explicit Case/Contact authorization because portal users do not have
  direct edit access to Vehicle records. This boundary requires continued
  authorization tests and careful review if new operations are added.
- The response model requires registration number and model when converting
  the response to a `Vehicle__c`, but make and year are optional in that
  conversion. The service is assumed to supply valid, complete data for this
  use case.
- The low-level reservation client throws on non-`2xx` responses; the
  controller converts those errors into safe user messages without including
  raw service response content.
- Internal users need the `Vehicle_Loan_Internal_Access` permission set for
  Apex access and loan details; administrators must assign it to authorized
  agents.

## Open Decisions

- If a remote reservation or return succeeds but local Vehicle persistence
  fails, what administrative repair or reconciliation action should follow?
  The controller reports remote success separately and blocks another action
  in the current component session, but no durable recovery workflow is
  specified.
