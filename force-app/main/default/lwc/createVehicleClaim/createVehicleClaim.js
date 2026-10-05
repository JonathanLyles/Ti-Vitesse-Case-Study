import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import createClaim from "@salesforce/apex/VehicleClaimController.createClaim";
import getVehicleRecordTypeId from "@salesforce/apex/VehicleClaimController.getVehicleRecordTypeId";
import { publishClaimSubmitted } from "c/claimEvents";

import CASE_OBJECT from "@salesforce/schema/Case";
import CASE_NUMBER_FIELD from "@salesforce/schema/Case.CaseNumber";
import INCIDENT_DATE_FIELD from "@salesforce/schema/Case.Date_and_Time_of_Incident__c";
import SUBJECT_FIELD from "@salesforce/schema/Case.Subject";
import DAMAGE_DETAIL_FIELD from "@salesforce/schema/Case.Damage_Detail__c";
import DESCRIPTION_FIELD from "@salesforce/schema/Case.Description";

import VEHICLE_OBJECT from "@salesforce/schema/Vehicle__c";
import MAKE_FIELD from "@salesforce/schema/Vehicle__c.Make__c";
import MODEL_FIELD from "@salesforce/schema/Vehicle__c.Model__c";
import REGISTRATION_FIELD from "@salesforce/schema/Vehicle__c.Registration_number__c";
import MILEAGE_FIELD from "@salesforce/schema/Vehicle__c.Mileage__c";
import ENGINE_CAPACITY_FIELD from "@salesforce/schema/Vehicle__c.Engine_Capacity__c";

// Form inputs are keyed by these names (data-field in the template)
const CASE_FIELDS = {
  incidentDate: INCIDENT_DATE_FIELD,
  subject: SUBJECT_FIELD,
  damageDetail: DAMAGE_DETAIL_FIELD,
  description: DESCRIPTION_FIELD
};
const VEHICLE_FIELDS = {
  make: MAKE_FIELD,
  model: MODEL_FIELD,
  registration: REGISTRATION_FIELD,
  mileage: MILEAGE_FIELD,
  engineCapacity: ENGINE_CAPACITY_FIELD
};
const NUMBER_FIELDS = new Set(["mileage", "engineCapacity"]);

const GENERIC_ERROR = "Your claim could not be submitted. Please try again.";

/**
 * Vehicle claim form for logged-in Experience Cloud customers. Submits the Case
 * and Vehicle through VehicleClaimController.createClaim and reports every
 * outcome as a toast.
 */
export default class CreateVehicleClaim extends LightningElement {
  values = {};
  isSaving = false;
  caseId;
  maxIncidentDate;

  @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
  caseInfo;

  @wire(getObjectInfo, { objectApiName: VEHICLE_OBJECT })
  vehicleInfo;

  // Claim vehicles are saved as Damaged Vehicles, so Make values come from that
  // record type rather than the user's default
  @wire(getVehicleRecordTypeId)
  vehicleRecordTypeId;

  @wire(getPicklistValues, {
    recordTypeId: "$vehicleRecordTypeId.data",
    fieldApiName: MAKE_FIELD
  })
  makePicklist;

  // Runs only once a claim is saved (caseId set); announces it with its reference number
  @wire(getRecord, { recordId: "$caseId", fields: [CASE_NUMBER_FIELD] })
  wiredCase({ data, error }) {
    if (!this.caseId || (!data && !error)) {
      return;
    }
    const caseNumber = data ? getFieldValue(data, CASE_NUMBER_FIELD) : null;
    const message = caseNumber
      ? `Your claim has been submitted. Your reference number is ${caseNumber}.`
      : "Your claim has been submitted.";
    this.showToast("Claim submitted", message, "success");
    this.caseId = undefined;
  }

  connectedCallback() {
    this.maxIncidentDate = new Date().toISOString();
  }

  get makeOptions() {
    const values = this.makePicklist?.data?.values ?? [];
    return values.map(({ label, value }) => ({ label, value }));
  }

  get labels() {
    const labels = {};
    const addLabels = (fields, objectInfo) => {
      Object.entries(fields).forEach(([key, field]) => {
        labels[key] =
          objectInfo?.data?.fields?.[field.fieldApiName]?.label ??
          field.fieldApiName;
      });
    };
    addLabels(CASE_FIELDS, this.caseInfo);
    addLabels(VEHICLE_FIELDS, this.vehicleInfo);
    return labels;
  }

  handleChange(event) {
    this.values = {
      ...this.values,
      [event.target.dataset.field]: event.detail.value
    };
  }

  async handleSubmit() {
    const inputs = [...this.template.querySelectorAll("[data-field]")];
    // reduce, not every, so each input shows its own error
    const isValid = inputs.reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
    if (!isValid) {
      this.showToast(
        "Missing information",
        "Please complete the required fields.",
        "warning"
      );
      return;
    }

    this.isSaving = true;
    let isSaved = false;
    try {
      this.caseId = await createClaim({
        claim: this.buildRecord(CASE_OBJECT, CASE_FIELDS),
        vehicle: this.buildRecord(VEHICLE_OBJECT, VEHICLE_FIELDS)
      });
      this.values = {};
      isSaved = true;
    } catch (error) {
      this.showToast(
        "Claim not submitted",
        error?.body?.message ?? GENERIC_ERROR,
        "error"
      );
    } finally {
      this.isSaving = false;
    }
    // Outside the try, so a failing subscriber is never reported as a failed claim
    if (isSaved) {
      publishClaimSubmitted();
    }
  }

  buildRecord(objectRef, fields) {
    const record = { sobjectType: objectRef.objectApiName };
    Object.entries(fields).forEach(([key, field]) => {
      const value = this.values[key];
      record[field.fieldApiName] =
        NUMBER_FIELDS.has(key) && value != null && value !== ""
          ? Number(value)
          : value;
    });
    return record;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
