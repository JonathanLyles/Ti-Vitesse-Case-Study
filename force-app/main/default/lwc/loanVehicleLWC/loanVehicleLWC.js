import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getLoanContext from "@salesforce/apex/VehicleLoanController.getLoanContext";
import reserveVehicle from "@salesforce/apex/VehicleLoanController.reserveVehicle";
import returnVehicle from "@salesforce/apex/VehicleLoanController.returnVehicle";

const GENERIC_LOAD_ERROR =
  "Vehicle loan information could not be loaded. Please try again.";

export default class LoanVehicleLWC extends LightningElement {
  _recordId;
  loadSequence = 0;
  context;
  isLoading = false;
  isSaving = false;
  hasPersistenceIssue = false;
  errorMessage;
  selectedRegistrationNumber;
  mileage;
  engineCapacity;
  filters = { make: "", model: "", year: "" };

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value === this._recordId) {
      return;
    }
    this._recordId = value;
    this.context = undefined;
    this.errorMessage = undefined;
    this.hasPersistenceIssue = false;
    this.clearSelection();
    if (value) {
      this.loadContext();
    }
  }

  get filteredVehicles() {
    const vehicles = this.context?.availableVehicles ?? [];
    return vehicles
      .filter((vehicle) =>
        ["make", "model", "year"].every((field) => {
          const filter = this.filters[field].trim().toLowerCase();
          const value =
            field === "year" ? vehicle.yearOfVehicle : vehicle[field];
          return (
            !filter ||
            String(value ?? "")
              .toLowerCase()
              .includes(filter)
          );
        })
      )
      .map((vehicle) => ({
        ...vehicle,
        isSelected:
          vehicle.registrationNumber === this.selectedRegistrationNumber
      }));
  }

  get hasActiveLoan() {
    return Boolean(this.context?.activeLoan);
  }

  get missingRecordId() {
    return !this.recordId && !this.isLoading;
  }

  get hasVehicles() {
    return this.filteredVehicles.length > 0;
  }

  get hasNoMatchingVehicles() {
    return (
      !this.hasActiveLoan &&
      !this.isLoading &&
      !this.errorMessage &&
      (this.context?.availableVehicles?.length ?? 0) > 0 &&
      !this.hasVehicles
    );
  }

  get canReturnActiveLoan() {
    return Boolean(
      this.context?.canReturnActiveLoan &&
      this.context?.activeLoan &&
      !this.isSaving &&
      !this.hasPersistenceIssue
    );
  }

  get actionDisabled() {
    return this.isSaving || this.isLoading || this.hasPersistenceIssue;
  }

  async loadContext() {
    if (!this.recordId) {
      return;
    }
    const sequence = ++this.loadSequence;
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const context = await getLoanContext({ caseId: this.recordId });
      if (sequence === this.loadSequence) {
        this.context = context;
      }
    } catch (error) {
      if (sequence === this.loadSequence) {
        this.context = undefined;
        this.errorMessage = error?.body?.message ?? GENERIC_LOAD_ERROR;
      }
    } finally {
      if (sequence === this.loadSequence) {
        this.isLoading = false;
      }
    }
  }

  handleFilterChange(event) {
    this.filters = {
      ...this.filters,
      [event.target.dataset.filter]: event.detail.value ?? ""
    };
  }

  handleSelectVehicle(event) {
    this.selectedRegistrationNumber = event.currentTarget.dataset.registration;
    this.mileage = undefined;
    this.engineCapacity = undefined;
  }

  handleLoanDetailChange(event) {
    this[event.target.dataset.field] = event.detail.value;
  }

  handleCancelSelection() {
    this.clearSelection();
  }

  async handleReserve() {
    const inputs = [...this.template.querySelectorAll("[data-loan-detail]")];
    const isValid = inputs.reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
    if (!isValid) {
      this.showToast(
        "Missing vehicle details",
        "Enter the mileage and engine capacity to continue.",
        "warning"
      );
      return;
    }

    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const result = await reserveVehicle({
        caseId: this.recordId,
        registrationNumber: this.selectedRegistrationNumber,
        mileage: Number(this.mileage),
        engineCapacity: Number(this.engineCapacity)
      });
      if (!result.remoteSucceeded) {
        this.showToast("Vehicle not reserved", result.message, "error");
      } else if (result.recordSaved) {
        this.showToast("Vehicle reserved", result.message, "success");
        this.clearSelection();
        await this.loadContext();
      } else {
        this.hasPersistenceIssue = true;
        this.errorMessage = result.message;
      }
    } catch (error) {
      this.showToast(
        "Vehicle not reserved",
        error?.body?.message ??
          "The vehicle reservation could not be completed. Please try again.",
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  async handleReturn() {
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const result = await returnVehicle({
        caseId: this.recordId,
        loanVehicleId: this.context.activeLoan.Id
      });
      if (!result.remoteSucceeded) {
        this.showToast("Vehicle not returned", result.message, "error");
      } else if (result.recordSaved) {
        this.showToast("Vehicle returned", result.message, "success");
        await this.loadContext();
      } else {
        this.hasPersistenceIssue = true;
        this.errorMessage = result.message;
      }
    } catch (error) {
      this.showToast(
        "Vehicle not returned",
        error?.body?.message ??
          "The vehicle could not be returned. Please try again.",
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  clearSelection() {
    this.selectedRegistrationNumber = undefined;
    this.mileage = undefined;
    this.engineCapacity = undefined;
  }
}
