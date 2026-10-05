# My Vehicle Claims (`myVehicleClaims`)

An Experience Cloud component that shows a signed-in customer the vehicle claims
they have submitted and their status. Customers submit claims with the
`createVehicleClaim` component; this one lets them follow them.

## Requirements

| #   | Requirement                                                                                                                                                                                                                                                 |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R1  | Can be placed only on Experience Cloud pages (`lightningCommunity__Page`, `lightningCommunity__Default`).                                                                                                                                                   |
| R2  | Lists only the signed-in customer's **Vehicle Claims** Cases (`ContactId` = the user's Contact, record type `Vehicle_Claims`). Never shows another customer's claims, including those of another Contact on the same Account.                               |
| R3  | Each row shows **Case Number, Subject, Date of incident, Date submitted, Status**.                                                                                                                                                                          |
| R4  | Clicking a claim expands its details inside the component: Subject, Status, Date of incident, Damage Detail, Description, and **every** linked Damaged Vehicle (Make, Model, Registration number, Mileage, Engine Capacity). Loan Vehicles are never shown. |
| R5  | With no claims, the component renders nothing: no card, no header, no "empty" message.                                                                                                                                                                      |
| R6  | Customers can read vehicles linked to their Contact, including vehicles an agent added, not only the ones they submitted.                                                                                                                                   |
| R7  | Guests (logged-out visitors) get nothing rendered, and Apex is never called.                                                                                                                                                                                |
| R8  | When a customer submits a new claim with `createVehicleClaim`, the list reloads and the new claim appears at the top, without a page reload. For a customer who had no claims, the component appears (R5).                                                  |

### Defaults

| #   | Default                                                                                                                                                        |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | Sorted by date submitted, newest first, with Case Number as the tie-breaker. All claims are shown, with no paging.                                             |
| D2  | Nothing is rendered while loading.                                                                                                                             |
| D3  | If loading fails, a short error message appears in the card (a generic message when the error has none).                                                       |
| D4  | Claims load when the page loads, and again when a claim is submitted (R8). Other changes, such as an agent updating a status, appear after the next page load. |
| D5  | One claim can be expanded at a time. Clicking it again collapses it.                                                                                           |
| D6  | After a reload (R8), the new claim is collapsed, and a claim that was expanded stays expanded.                                                                 |

## How it works

- `myVehicleClaims` calls `CustomerClaimsController.getMyClaims()` from
  `connectedCallback` (not `@wire`), so the call can be skipped for guests (R7).
  A wire with no parameters cannot be switched off.
- `getMyClaims()` runs one query `WITH USER_MODE`: the customer's Cases and,
  as a subquery on `Vehicles__r`, their Damaged Vehicles.
- **Refresh after a submit (R8).** The two components are siblings placed by
  Experience Builder, so neither can call the other. They share a small module,
  `c/claimEvents` (`lwc/claimEvents`), that works like a message channel:
  `createVehicleClaim` calls `publishClaimSubmitted()` after a claim is saved
  (never on a validation failure or a failed save), and `myVehicleClaims`
  subscribes in `connectedCallback` and reloads. It unsubscribes in
  `disconnectedCallback`, so a reconnect does not add a second subscriber. The
  module is loaded once per page, so it works on Aura and LWR sites. If the two
  components are on different pages, nothing needs to be published: the list loads
  when its page loads. A subscriber that throws does not stop the others, and
  `createVehicleClaim` publishes outside its `try`, so such an error is never shown
  as a failed claim.
- `createVehicleClaim` is the only existing component changed for R8.
- Access comes from three places:
  - `Customer_Claims_Access` sharing set: read on Cases and Vehicles whose
    Contact is the user's Contact (R2, R6).
  - `Vehicle_Claim_Portal_Access` permission set: access to the Apex class and
    to the incident, damage and vehicle fields.
  - `Customer Community Clone` profile: read on Case.

## Design decisions

### Request counter on every load (added with R8)

Loads can overlap. `connectedCallback` runs again whenever the same element is
removed and reinserted, and (since R8) a submitted claim triggers a reload. That
can start a second `loadClaims()` while the first is still in flight. Responses can
arrive out of order, so if the older one arrives last it overwrites the newer one.

`loadClaims()` therefore uses a **request counter**: each call takes a number, and
when its response (or error) arrives it is ignored unless its number is still the
latest. Tests J24 and J25 cover this, and fail if the check is removed.

History of this decision (2026-10-04):

1. **First decision: no counter.** Before R8 the only trigger was a reconnect, and
   a customer's claims change rarely, so two calls moments apart almost always
   returned identical data (roughly 999 times in 1000, as a rough estimate). The
   worst case was a list that stayed out of date until the next page load, with
   nothing lost or written. Reconnecting the same instance is itself uncommon (a
   parent's `lwc:if` creates a new instance instead). Revisit conditions were: data
   that changes often (like a stock ticker), auto-refresh or polling, or writes.
2. **Then R8.** Reloading after a submit is the one case where two results really
   differ: one contains the new claim and an older in-flight one does not. The
   overlap is unlikely (the first load is usually long finished when a customer
   has filled in the form), but a quick second submit could let an older reload hide
   the newest claim until the next page load. Guarding against out-of-order
   responses is standard practice once a call can be re-triggered and its results
   can differ, and it costs about five lines and two tests, so Jonathan chose to
   add the counter.

What we also handle: the instance state that survives a reconnect. After each load,
an expanded claim that is no longer in the list is collapsed (J13), and an empty
list makes the component disappear (J14).

### `getMyClaims` is not cacheable

`getMyClaims` is a plain `@AuraEnabled` method, **not** `cacheable=true`, so every
load goes to the server.

Why: cacheable Apex results can be kept on the client under a key made of the
method and its parameters. `getMyClaims()` has no parameters, so every call uses the
same key. The claim is saved by a different Apex method (`createVehicleClaim`'s
`createClaim`), so nothing tells the cache the list changed, and `refreshApex` only
works with `@wire`, which this component does not use. After a submit (R8) the
reload returned the cached list without the new claim, so the list looked
unchanged.

History:

1. R8 shipped with `cacheable=true`. It passed the Jest tests, which mock Apex, but
   on the site the list did not refresh (GitHub issue #2).
2. On 2026-10-05 `cacheable=true` was removed and the change was confirmed on the
   site: the new claim appears without a page reload. This resolved issues #1 and #2.

Cost: one extra server call per page view and per submitted claim. Add caching back
only with a way to clear it after a submit.

Decisions: Jonathan, 2026-10-04 and 2026-10-05.

## Tests that must pass

### Apex: `CustomerClaimsControllerTest`

| #   | Test                                         | Proves                                                                                                                         |
| --- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| A1  | `returnsOwnVehicleClaimsWithCaseFields`      | Own claims come back with all Case fields (R2, R3, R4)                                                                         |
| A2  | `includesDamagedVehicleDetails`              | Each claim includes its vehicle's details (R4)                                                                                 |
| A3  | `sortsNewestFirst`                           | Newest submitted first (D1)                                                                                                    |
| A4  | `excludesOtherCustomersClaims`               | A claim of a customer on another Account is never returned (R2)                                                                |
| A6  | `returnsEmptyListWhenCustomerHasNoClaims`    | Empty list, not an error (R5)                                                                                                  |
| A7  | `returnsEmptyListForInternalUser`            | A user with no Contact gets an empty list (R2)                                                                                 |
| A8  | `throwsReadableErrorWithoutClaimPermissions` | Without `Vehicle_Claim_Portal_Access` the user gets a readable error and no data, which shows the query runs in user mode (R2) |
| A9  | `returnsClaimWithoutVehicle`                 | A claim with no vehicle is still returned (R4)                                                                                 |
| A10 | `excludesSameAccountDifferentContact`        | Another Contact on the same Account cannot see the claim (R2)                                                                  |
| A11 | `returnsClaimsInEveryStatus`                 | Every status, including Closed, is returned (R3)                                                                               |
| A12 | `ordersSameSecondClaimsByCaseNumber`         | Same created date: higher Case Number first (D1)                                                                               |
| A13 | `returnsAllClaimsWhenCustomerHasMany`        | 201 claims with vehicles all come back (D1)                                                                                    |
| A14 | `excludesLoanVehicleFromDetails`             | A Loan Vehicle is not listed as a damaged vehicle (R4)                                                                         |
| A15 | `showsVehiclesAddedByAgent`                  | Vehicles added by an agent are visible, oldest first (R4, R6)                                                                  |

A5 (a Case of another record type is excluded) is not tested: the org has one
Case record type and Apex tests cannot create another. The record-type filter
stays in the query as a safeguard.

The tests create only two portal users, because the org has 5 Customer
Community licences. Run: `sf apex run test -n CustomerClaimsControllerTest -c -r human -w 15`.

### Jest: `__tests__/myVehicleClaims.test.js`

| #   | Test                                                                                                          | Proves        |
| --- | ------------------------------------------------------------------------------------------------------------- | ------------- |
| J1  | renders nothing when the customer has no claims                                                               | R5            |
| J2  | renders nothing until the claims have loaded                                                                  | D2            |
| J3  | shows the five columns for each claim                                                                         | R3            |
| J4  | lists claims in the order returned                                                                            | D1            |
| J5  | hides the details until a claim is clicked                                                                    | R4            |
| J6  | shows claim and vehicle details when clicked                                                                  | R4            |
| J7  | collapses a claim when clicked again                                                                          | D5            |
| J8  | expands one claim at a time                                                                                   | D5            |
| J9  | shows details when the claim has no vehicle                                                                   | R4            |
| J10 | shows the error message and no claims when loading fails                                                      | D3            |
| J11 | no accessibility violations, with the claims collapsed and with one expanded (two tests, using `@sa11y/jest`) | Accessibility |
| J12 | no "undefined" or "null" text for missing optional fields                                                     | R4            |
| J13 | an expanded claim missing after a reload is collapsed                                                         | D4            |
| J14 | disappears when a reload returns no claims                                                                    | R5            |
| J15 | generic message when the error has no message                                                                 | D3            |
| J16 | shows every vehicle when a claim has more than one                                                            | R4            |
| J17 | for a guest, nothing renders and Apex is never called                                                         | R7            |
| J18 | reloads and shows the new claim at the top when a claim is submitted                                          | R8            |
| J19 | appears when a customer with no claims submits their first claim                                              | R8, R5        |
| J20 | an expanded claim stays expanded when the list reloads                                                        | D6            |
| J21 | shows the error message when the reload after a submit fails                                                  | R8, D3        |
| J22 | stops reloading once it has been removed from the page                                                        | R8            |
| J23 | reloads only once per submitted claim after it has been reconnected                                           | R8            |
| J24 | ignores a slow earlier load that finishes after a newer one                                                   | Counter       |
| J25 | ignores a slow earlier load that fails after a newer one succeeded                                            | Counter       |

The accessibility matcher is registered in this test file only (`setup()` from
`@sa11y/jest` in `beforeAll`). In Jest the `lightning-*` components are simple
stubs, so J11 checks this component's own markup, not the real base components.

J24 and J25 were checked by temporarily disabling the counter's check: both fail
without it. The J18 to J25 tests rely on the real `c/claimEvents` module, so they
test the publish and subscribe path as well.

### Jest: `claimEvents/__tests__/claimEvents.test.js`

| #   | Test                                                                  | Proves                                  |
| --- | --------------------------------------------------------------------- | --------------------------------------- |
| E1  | calls a subscriber each time a claim is submitted                     | R8                                      |
| E2  | calls every subscriber                                                | R8                                      |
| E3  | stops calling a subscriber after it unsubscribes                      | No leaked subscribers                   |
| E4  | does nothing when nobody is subscribed                                | A submit with no list on the page works |
| E5  | runs every subscriber even if one throws, then throws the first error | One bad subscriber cannot block others  |

### Jest: `createVehicleClaim/__tests__/createVehicleClaim.test.js` (added for R8)

| #   | Test                                                             | Proves                           |
| --- | ---------------------------------------------------------------- | -------------------------------- |
| F1  | tells other components once when a claim has been submitted      | R8                               |
| F2  | does not tell other components when required fields are missing  | No refresh without a saved claim |
| F3  | does not tell other components when the claim could not be saved | No refresh without a saved claim |

The existing `createVehicleClaim` tests are unchanged and must still pass.

Run: `npm run test:unit`, `npm run lint`, `npm run prettier:verify`.

### Manual acceptance on the site, after deploy and publish

| #   | Check                                                                                                                                            | Proves     |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| M1  | "My Vehicle Claims" is in the Experience Builder component panel, and not in the Lightning App Builder                                           | R1         |
| M2  | A customer with claims sees only their own, newest first, with the five columns. Also confirms the permission set grants class access.           | R2, R3, D1 |
| M3  | Clicking a claim shows its details; clicking again hides them                                                                                    | R4, D5     |
| M4  | A second customer's claims are not visible to the first customer                                                                                 | R2         |
| M5  | A customer with no claims sees no component                                                                                                      | R5         |
| M6  | An agent changes a claim's Status; after a reload the customer sees it                                                                           | R3, D4     |
| M7  | A logged-out visitor on a public page with the component sees nothing, and no error                                                              | R7         |
| M8  | At phone width rows and details are readable, with no horizontal scrolling                                                                       | Mobile     |
| M9  | An agent adds a damaged vehicle to a claim; the customer sees it in the details                                                                  | R6         |
| M10 | With the form and the list on one page, a customer with no claims submits a claim: the list appears, with the new claim, without a page reload   | R8, R5     |
| M11 | A customer with claims submits another: it appears at the top, collapsed, and a claim that was expanded stays expanded                           | R8, D6     |
| M12 | Submit a claim, navigate to another page and back: the new claim is still listed (this is the cache check, see "`getMyClaims` is not cacheable") | R8         |

## Placing it on the site

Add **My Vehicle Claims** to a page in Experience Builder and publish.

For the list to refresh the moment a claim is submitted (R8), put it on the **same
page** as **Create Vehicle Claim**. On different pages it still shows the new claim
the next time its page loads.

The component ships with `claimEvents` (an internal module, not shown in Experience
Builder), so deploy `lwc/claimEvents` together with `lwc/myVehicleClaims` and
`lwc/createVehicleClaim`.
