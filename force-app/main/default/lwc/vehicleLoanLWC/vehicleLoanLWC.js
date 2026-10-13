import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import CASE_NUMBER from "@salesforce/schema/Case.CaseNumber";

export default class VehicleLoanLWC extends LightningElement {
  @api recordId;

  @wire(getRecord, { recordId: "$recordId", fields: [CASE_NUMBER] })
  record;

  get caseNumber() {
    return getFieldValue(this.record.data, CASE_NUMBER);
  }
}
