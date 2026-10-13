import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getLoanContext from "@salesforce/apex/VehicleLoanController.getLoanContext";
import reserveVehicle from "@salesforce/apex/VehicleLoanController.reserveVehicle";
import returnVehicle from "@salesforce/apex/VehicleLoanController.returnVehicle";

const GENERIC_ERROR = "Something went wrong. Please try again.";
const NO_ACCESS_ERROR =
  "You do not have permission to manage vehicle loans. Please contact your administrator.";
const APEX_ACCESS_PATTERN = /do not have access to the Apex class/i;

export default class VehicleLoanLWC extends LightningElement {
  @api recordId;

  isLoading = true;
  loadError;
  availableVehicles = [];
  activeLoan;
  canReturnActiveLoan = false;
  selectedVehicle;

  connectedCallback() {
    this.loadContext();
  }

  get hasActiveLoan() {
    return !!this.activeLoan;
  }

  get showVehicleList() {
    return !this.isLoading && !this.loadError && !this.hasActiveLoan;
  }

  get noVehicles() {
    return this.availableVehicles.length === 0;
  }

  get isModalOpen() {
    return !!this.selectedVehicle;
  }

  async loadContext() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const context = await getLoanContext({ caseId: this.recordId });
      this.availableVehicles = context.availableVehicles || [];
      this.activeLoan = context.activeLoan;
      this.canReturnActiveLoan = !!context.canReturnActiveLoan;
    } catch (error) {
      this.loadError = this.errorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleReserveClick(event) {
    const registrationNumber = event.currentTarget.dataset.registration;
    this.selectedVehicle = this.availableVehicles.find(
      (vehicle) => vehicle.registrationNumber === registrationNumber
    );
  }

  handleCancel() {
    this.selectedVehicle = undefined;
  }

  async handleConfirmReserve() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    if (!inputs.every((input) => input.reportValidity())) {
      return;
    }
    const [mileage, engineCapacity] = inputs.map((input) =>
      Number(input.value)
    );
    this.isLoading = true;
    try {
      const result = await reserveVehicle({
        caseId: this.recordId,
        registrationNumber: this.selectedVehicle.registrationNumber,
        mileage,
        engineCapacity
      });
      this.selectedVehicle = undefined;
      this.toastResult(result);
    } catch (error) {
      this.toast("Reservation failed", this.errorMessage(error), "error");
    }
    await this.loadContext();
  }

  async handleReturn() {
    this.isLoading = true;
    try {
      const result = await returnVehicle({
        caseId: this.recordId,
        loanVehicleId: this.activeLoan.Id
      });
      this.toastResult(result);
    } catch (error) {
      this.toast("Return failed", this.errorMessage(error), "error");
    }
    await this.loadContext();
  }

  // The remote call can succeed while the Salesforce save fails: a warning, not a success.
  toastResult(result) {
    this.toast(
      result.recordSaved ? "Done" : "Attention",
      result.message,
      result.recordSaved ? "success" : "warning"
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  // Salesforce words a missing class permission as a technical message; show a plain one instead.
  errorMessage(error) {
    const message = error?.body?.message;
    if (message && APEX_ACCESS_PATTERN.test(message)) {
      return NO_ACCESS_ERROR;
    }
    return message || GENERIC_ERROR;
  }
}
