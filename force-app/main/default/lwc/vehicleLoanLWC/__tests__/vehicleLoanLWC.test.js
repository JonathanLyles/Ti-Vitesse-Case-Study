import { createElement } from "lwc";
import VehicleLoanLWC from "c/vehicleLoanLWC";
import getLoanContext from "@salesforce/apex/VehicleLoanController.getLoanContext";
import reserveVehicle from "@salesforce/apex/VehicleLoanController.reserveVehicle";
import returnVehicle from "@salesforce/apex/VehicleLoanController.returnVehicle";

jest.mock(
  "@salesforce/apex/VehicleLoanController.getLoanContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VehicleLoanController.reserveVehicle",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VehicleLoanController.returnVehicle",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const TOAST_EVENT = "lightning__showtoast";
const CASE_ID = "500000000000001AAA";
const LOAN_ID = "a00000000000001AAA";

const VEHICLES = [
  {
    registrationNumber: "AB12CDE",
    make: "Ford",
    model: "Focus",
    yearOfVehicle: "2019"
  },
  {
    registrationNumber: "XY34ZZZ",
    make: "Audi",
    model: "A3",
    yearOfVehicle: "2021"
  }
];

const ACTIVE_LOAN = {
  Id: LOAN_ID,
  Registration_number__c: "AB12CDE",
  Make__c: "Ford",
  Model__c: "Focus",
  Year_of_Vehicle__c: "2019"
};

// Promise-based Apex calls resolve on the microtask queue
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function createComponent() {
  const element = createElement("c-vehicle-loan-lwc", {
    is: VehicleLoanLWC
  });
  element.recordId = CASE_ID;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function listenForToasts(element) {
  const handler = jest.fn();
  element.addEventListener(TOAST_EVENT, (event) => handler(event.detail));
  return handler;
}

async function openReserveModal(element, registration) {
  element.shadowRoot
    .querySelector(`.reserve-button[data-registration="${registration}"]`)
    .click();
  await flushPromises();
}

async function confirmReservation(element, mileage, engineCapacity) {
  const [mileageInput, engineInput] =
    element.shadowRoot.querySelectorAll("lightning-input");
  // The Jest stub of lightning-input has no reportValidity, so give both a passing one
  mileageInput.reportValidity = jest.fn(() => true);
  engineInput.reportValidity = jest.fn(() => true);
  mileageInput.value = mileage;
  engineInput.value = engineCapacity;
  element.shadowRoot.querySelector(".confirm-button").click();
  await flushPromises();
}

describe("c-vehicle-loan-lwc", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });

  it("asks Apex for the loan context of the current case", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: [] });

    await createComponent();

    expect(getLoanContext).toHaveBeenCalledTimes(1);
    expect(getLoanContext).toHaveBeenCalledWith({ caseId: CASE_ID });
  });

  it("shows a spinner while the context is loading", async () => {
    getLoanContext.mockReturnValue(new Promise(() => {}));

    const element = await createComponent();

    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector(".vehicle-row")).toBeNull();
  });

  it("lists each available vehicle with its own Reserve button", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: VEHICLES });

    const element = await createComponent();

    const rows = element.shadowRoot.querySelectorAll(".vehicle-row");
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Ford Focus (2019)");
    expect(rows[0].textContent).toContain("AB12CDE");
    expect(rows[1].textContent).toContain("Audi A3 (2021)");
    expect(element.shadowRoot.querySelectorAll(".reserve-button")).toHaveLength(
      2
    );
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
  });

  it("says so when no vehicles are available", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: [] });

    const element = await createComponent();

    expect(element.shadowRoot.querySelector(".no-vehicles")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".vehicle-row")).toBeNull();
  });

  it("shows the load error and a retry button when the context fails", async () => {
    getLoanContext.mockRejectedValueOnce({
      body: { message: "Available vehicles could not be loaded." }
    });
    getLoanContext.mockResolvedValueOnce({ availableVehicles: VEHICLES });

    const element = await createComponent();

    expect(element.shadowRoot.querySelector(".load-error").textContent).toBe(
      "Available vehicles could not be loaded."
    );
    expect(element.shadowRoot.querySelector(".vehicle-row")).toBeNull();

    element.shadowRoot.querySelector(".retry-button").click();
    await flushPromises();

    expect(getLoanContext).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector(".load-error")).toBeNull();
    expect(element.shadowRoot.querySelectorAll(".vehicle-row")).toHaveLength(2);
  });

  it("shows the active loan with a Return button when it belongs to this case", async () => {
    getLoanContext.mockResolvedValue({
      activeLoan: ACTIVE_LOAN,
      canReturnActiveLoan: true,
      availableVehicles: []
    });

    const element = await createComponent();

    expect(
      element.shadowRoot.querySelector(".loan-registration").textContent
    ).toBe("AB12CDE");
    expect(element.shadowRoot.querySelector(".return-button")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".other-case")).toBeNull();
    expect(element.shadowRoot.querySelector(".vehicle-row")).toBeNull();
  });

  it("shows the active loan without a Return button when it belongs to another case", async () => {
    getLoanContext.mockResolvedValue({
      activeLoan: ACTIVE_LOAN,
      canReturnActiveLoan: false,
      availableVehicles: []
    });

    const element = await createComponent();

    expect(
      element.shadowRoot.querySelector(".loan-registration").textContent
    ).toBe("AB12CDE");
    expect(element.shadowRoot.querySelector(".return-button")).toBeNull();
    expect(element.shadowRoot.querySelector(".other-case")).not.toBeNull();
  });

  it("opens the reserve form with the callout details and closes it on Cancel", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: VEHICLES });
    const element = await createComponent();

    await openReserveModal(element, "XY34ZZZ");

    const dialog = element.shadowRoot.querySelector("section[role=dialog]");
    expect(dialog.textContent).toContain("XY34ZZZ");
    expect(dialog.textContent).toContain("Audi A3 (2021)");
    expect(element.shadowRoot.querySelectorAll("lightning-input")).toHaveLength(
      2
    );

    element.shadowRoot.querySelector(".cancel-button").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector("section[role=dialog]")).toBeNull();
    expect(reserveVehicle).not.toHaveBeenCalled();
  });

  it("reserves the chosen vehicle with the typed mileage and engine capacity, toasts success and reloads", async () => {
    getLoanContext
      .mockResolvedValueOnce({ availableVehicles: VEHICLES })
      .mockResolvedValueOnce({
        activeLoan: ACTIVE_LOAN,
        canReturnActiveLoan: true,
        availableVehicles: []
      });
    reserveVehicle.mockResolvedValue({
      remoteSucceeded: true,
      recordSaved: true,
      message: "The vehicle has been reserved."
    });
    const element = await createComponent();
    const toasts = listenForToasts(element);

    await openReserveModal(element, "AB12CDE");
    await confirmReservation(element, "45000", "1600");

    expect(reserveVehicle).toHaveBeenCalledTimes(1);
    expect(reserveVehicle).toHaveBeenCalledWith({
      caseId: CASE_ID,
      registrationNumber: "AB12CDE",
      mileage: 45000,
      engineCapacity: 1600
    });
    expect(toasts).toHaveBeenCalledWith({
      title: "Done",
      message: "The vehicle has been reserved.",
      variant: "success"
    });
    expect(getLoanContext).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector("section[role=dialog]")).toBeNull();
    expect(element.shadowRoot.querySelector(".return-button")).not.toBeNull();
  });

  it("does not call Apex while the reserve form is invalid", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: VEHICLES });
    const element = await createComponent();
    await openReserveModal(element, "AB12CDE");
    const [mileageInput] =
      element.shadowRoot.querySelectorAll("lightning-input");
    mileageInput.reportValidity = jest.fn(() => false);

    element.shadowRoot.querySelector(".confirm-button").click();
    await flushPromises();

    expect(reserveVehicle).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector("section[role=dialog]")
    ).not.toBeNull();
  });

  it("toasts the controller message as an error when the reservation fails and keeps the form open", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: VEHICLES });
    reserveVehicle.mockRejectedValue({
      body: { message: "That vehicle is no longer available." }
    });
    const element = await createComponent();
    const toasts = listenForToasts(element);

    await openReserveModal(element, "AB12CDE");
    await confirmReservation(element, "100", "1000");

    expect(toasts).toHaveBeenCalledWith({
      title: "Reservation failed",
      message: "That vehicle is no longer available.",
      variant: "error"
    });
    expect(
      element.shadowRoot.querySelector("section[role=dialog]")
    ).not.toBeNull();
  });

  it("warns when the remote reservation worked but Salesforce could not save the record", async () => {
    getLoanContext.mockResolvedValue({ availableVehicles: VEHICLES });
    reserveVehicle.mockResolvedValue({
      remoteSucceeded: true,
      recordSaved: false,
      message:
        "The remote reservation succeeded, but Salesforce could not save the loan record."
    });
    const element = await createComponent();
    const toasts = listenForToasts(element);

    await openReserveModal(element, "AB12CDE");
    await confirmReservation(element, "100", "1000");

    expect(toasts).toHaveBeenCalledWith({
      title: "Attention",
      message:
        "The remote reservation succeeded, but Salesforce could not save the loan record.",
      variant: "warning"
    });
  });

  it("returns the active loan, toasts success and reloads", async () => {
    getLoanContext
      .mockResolvedValueOnce({
        activeLoan: ACTIVE_LOAN,
        canReturnActiveLoan: true,
        availableVehicles: []
      })
      .mockResolvedValueOnce({ availableVehicles: VEHICLES });
    returnVehicle.mockResolvedValue({
      remoteSucceeded: true,
      recordSaved: true,
      message: "The vehicle has been returned."
    });
    const element = await createComponent();
    const toasts = listenForToasts(element);

    element.shadowRoot.querySelector(".return-button").click();
    await flushPromises();

    expect(returnVehicle).toHaveBeenCalledTimes(1);
    expect(returnVehicle).toHaveBeenCalledWith({
      caseId: CASE_ID,
      loanVehicleId: LOAN_ID
    });
    expect(toasts).toHaveBeenCalledWith({
      title: "Done",
      message: "The vehicle has been returned.",
      variant: "success"
    });
    expect(getLoanContext).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelectorAll(".vehicle-row")).toHaveLength(2);
  });

  it("toasts the controller message as an error when the return fails", async () => {
    getLoanContext.mockResolvedValue({
      activeLoan: ACTIVE_LOAN,
      canReturnActiveLoan: true,
      availableVehicles: []
    });
    returnVehicle.mockRejectedValue({
      body: { message: "The vehicle could not be returned. Please try again." }
    });
    const element = await createComponent();
    const toasts = listenForToasts(element);

    element.shadowRoot.querySelector(".return-button").click();
    await flushPromises();

    expect(toasts).toHaveBeenCalledWith({
      title: "Return failed",
      message: "The vehicle could not be returned. Please try again.",
      variant: "error"
    });
    expect(element.shadowRoot.querySelector(".return-button")).not.toBeNull();
  });

  it("falls back to a generic message when the error has no body", async () => {
    getLoanContext.mockRejectedValue(new Error("network"));

    const element = await createComponent();

    expect(element.shadowRoot.querySelector(".load-error").textContent).toBe(
      "Something went wrong. Please try again."
    );
  });

  it("replaces the technical Apex class access error with a plain message", async () => {
    getLoanContext.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'VehicleLoanController'."
      }
    });

    const element = await createComponent();

    expect(element.shadowRoot.querySelector(".load-error").textContent).toBe(
      "You do not have permission to manage vehicle loans. Please contact your administrator."
    );
  });
});
