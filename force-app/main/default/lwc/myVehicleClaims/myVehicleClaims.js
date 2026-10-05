import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import getMyClaims from "@salesforce/apex/CustomerClaimsController.getMyClaims";
import { subscribeToClaimSubmitted } from "c/claimEvents";

const GENERIC_ERROR = "Your claims could not be loaded. Please try again.";

/**
 * Lists the logged-in Experience Cloud customer's vehicle claims with their
 * status. A claim expands to show its details and damaged vehicles. Nothing is
 * rendered while loading, for guests, or when the customer has no claims. The list
 * reloads when createVehicleClaim reports a submitted claim.
 */
export default class MyVehicleClaims extends LightningElement {
  claims = [];
  error;
  selectedClaimId;
  latestRequest = 0;
  unsubscribe;

  connectedCallback() {
    // Guests have no Contact and no claims, so Apex is never called for them
    if (!isGuest) {
      this.loadClaims();
      this.unsubscribe = subscribeToClaimSubmitted(() => this.loadClaims());
    }
  }

  disconnectedCallback() {
    // Otherwise every reconnect would add one more subscriber
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  // Loads can overlap (the element is reconnected, or a claim is submitted while
  // a load is running) and responses can arrive out of order. Each call takes a
  // number and ignores its result if a newer call has started (see "Design
  // decisions" in REQUIREMENTS.md)
  async loadClaims() {
    this.latestRequest += 1;
    const requestId = this.latestRequest;
    try {
      const claims = await getMyClaims();
      if (requestId !== this.latestRequest) {
        return;
      }
      this.claims = claims;
      this.error = undefined;
      // A claim that is no longer in the list cannot stay expanded
      if (!this.claims.some(({ Id }) => Id === this.selectedClaimId)) {
        this.selectedClaimId = undefined;
      }
    } catch (error) {
      if (requestId !== this.latestRequest) {
        return;
      }
      this.claims = [];
      this.selectedClaimId = undefined;
      this.error = error?.body?.message ?? GENERIC_ERROR;
    }
  }

  get hasClaims() {
    return this.claims.length > 0;
  }

  get rows() {
    return this.claims.map((claim) => {
      const isExpanded = claim.Id === this.selectedClaimId;
      const vehicles = claim.Vehicles__r ?? [];
      return {
        id: claim.Id,
        caseNumber: claim.CaseNumber,
        subject: claim.Subject,
        status: claim.Status,
        createdDate: claim.CreatedDate,
        incidentDate: claim.Date_and_Time_of_Incident__c,
        damageDetail: claim.Damage_Detail__c,
        description: claim.Description,
        isExpanded,
        // aria-expanded needs the strings "true" / "false"
        ariaExpanded: String(isExpanded),
        vehicles: vehicles.map((vehicle, index) => ({
          id: vehicle.Id,
          title:
            vehicles.length > 1
              ? `Damaged vehicle ${index + 1}`
              : "Damaged vehicle",
          make: vehicle.Make__c,
          model: vehicle.Model__c,
          registration: vehicle.Registration_number__c,
          mileage: vehicle.Mileage__c,
          engineCapacity: vehicle.Engine_Capacity__c
        }))
      };
    });
  }

  handleToggle(event) {
    const { id } = event.currentTarget.dataset;
    this.selectedClaimId = this.selectedClaimId === id ? undefined : id;
  }
}
