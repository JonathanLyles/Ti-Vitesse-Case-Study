import { createElement } from "@lwc/engine-dom";
import LoanVehicleLWC from "c/loanVehicleLWC";
import getLoanContext from "@salesforce/apex/VehicleLoanController.getLoanContext";
import reserveVehicle from "@salesforce/apex/VehicleLoanController.reserveVehicle";
import returnVehicle from "@salesforce/apex/VehicleLoanController.returnVehicle";
import { setup } from "@sa11y/jest";

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

const CASE_ID = "500000000000001AAA";
const VEHICLES = [
  {
    registrationNumber: "REG 123",
    make: "Volkswagen",
    model: "Golf",
    yearOfVehicle: "2024"
  },
  {
    registrationNumber: "REG 456",
    make: "Ford",
    model: "Focus",
    yearOfVehicle: "2023"
  }
];
const ACTIVE_LOAN = {
  Id: "a00000000000001AAA",
  Make__c: "Volkswagen",
  Model__c: "Golf",
  Year_of_Vehicle__c: "2024",
  Registration_number__c: "REG 123",
  Mileage__c: 42000,
  Engine_Capacity__c: 1600
};
const TOAST_EVENT = "lightning__showtoast";

// Promise-based Apex calls resolve on the microtask queue
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function availableContext() {
  return {
    availableVehicles: VEHICLES,
    activeLoan: null,
    canReturnActiveLoan: false
  };
}

function activeLoanContext(canReturnActiveLoan = true) {
  return {
    availableVehicles: [],
    activeLoan: ACTIVE_LOAN,
    canReturnActiveLoan
  };
}

async function createComponent(context = availableContext()) {
  getLoanContext.mockResolvedValue(context);
  const element = createElement("c-loan-vehicle-lwc", {
    is: LoanVehicleLWC
  });
  document.body.appendChild(element);
  element.recordId = CASE_ID;
  await flushPromises();
  return element;
}

function listenForToasts(element) {
  const handler = jest.fn();
  element.addEventListener(TOAST_EVENT, handler);
  return handler;
}

async function filter(element, name, value) {
  const input = element.shadowRoot.querySelector(`[data-filter="${name}"]`);
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await flushPromises();
}

function reserveButton(element, registration) {
  return element.shadowRoot.querySelector(
    `lightning-button[data-registration="${registration}"]`
  );
}

function setLoanDetails(element, mileage = "42000", engineCapacity = "1600") {
  const mileageInput = element.shadowRoot.querySelector(
    '[data-field="mileage"]'
  );
  const engineCapacityInput = element.shadowRoot.querySelector(
    '[data-field="engineCapacity"]'
  );
  jest.spyOn(mileageInput, "reportValidity").mockReturnValue(true);
  jest.spyOn(engineCapacityInput, "reportValidity").mockReturnValue(true);
  mileageInput.dispatchEvent(
    new CustomEvent("change", { detail: { value: mileage } })
  );
  engineCapacityInput.dispatchEvent(
    new CustomEvent("change", { detail: { value: engineCapacity } })
  );
}

describe("c-loan-vehicle-lwc", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    getLoanContext.mockReset();
    reserveVehicle.mockReset();
    returnVehicle.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("loads available vehicle details and passes the Case ID to Apex", async () => {
    const element = await createComponent();

    expect(getLoanContext).toHaveBeenCalledWith({ caseId: CASE_ID });
    expect(element.shadowRoot.textContent).toContain("Volkswagen");
    expect(element.shadowRoot.textContent).toContain("Golf");
    expect(element.shadowRoot.textContent).toContain("2024");
    expect(element.shadowRoot.textContent).toContain("REG 123");
    expect(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).toHaveLength(2);
  });

  it("filters by make, model, and year and shows no-match feedback", async () => {
    const element = await createComponent();

    await filter(element, "make", "volks");
    expect(reserveButton(element, "REG 123")).not.toBeNull();
    expect(reserveButton(element, "REG 456")).toBeNull();

    await filter(element, "make", "");
    await filter(element, "model", "focus");
    expect(reserveButton(element, "REG 456")).not.toBeNull();
    expect(reserveButton(element, "REG 123")).toBeNull();

    await filter(element, "model", "");
    await filter(element, "year", "2022");
    expect(element.shadowRoot.textContent).toContain(
      "No vehicles match the selected filters."
    );
  });

  it("shows the active loan instead of availability and offers return", async () => {
    const element = await createComponent(activeLoanContext());

    expect(element.shadowRoot.textContent).toContain("Your active loan");
    expect(element.shadowRoot.textContent).toContain("REG 123");
    expect(element.shadowRoot.textContent).toContain("42000");
    expect(element.shadowRoot.textContent).toContain("1600");
    expect(
      element.shadowRoot.querySelector(
        'section[aria-label="Available vehicles"]'
      )
    ).toBeNull();
    expect(element.shadowRoot.querySelector("lightning-button").label).toBe(
      "Return vehicle"
    );
  });

  it("reserves a selected vehicle and reloads the active loan", async () => {
    const element = await createComponent();
    const toastHandler = listenForToasts(element);
    reserveVehicle.mockResolvedValue({
      remoteSucceeded: true,
      recordSaved: true,
      message: "The vehicle has been reserved."
    });
    getLoanContext.mockResolvedValueOnce(activeLoanContext());

    reserveButton(element, "REG 123").click();
    await flushPromises();
    expect(reserveVehicle).not.toHaveBeenCalled();
    setLoanDetails(element);
    element.shadowRoot.querySelector("[data-confirm-reservation]").click();
    await flushPromises();

    expect(reserveVehicle).toHaveBeenCalledWith({
      caseId: CASE_ID,
      registrationNumber: "REG 123",
      mileage: 42000,
      engineCapacity: 1600
    });
    expect(getLoanContext).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.textContent).toContain("Your active loan");
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Vehicle reserved",
      variant: "success"
    });
  });

  it("keeps the reservation form available after a server failure", async () => {
    const element = await createComponent();
    const toastHandler = listenForToasts(element);
    reserveVehicle.mockRejectedValue({
      body: { message: "The vehicle reservation could not be completed." }
    });

    reserveButton(element, "REG 123").click();
    await flushPromises();
    setLoanDetails(element);
    element.shadowRoot.querySelector("[data-confirm-reservation]").click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("[data-confirm-reservation]")
    ).not.toBeNull();
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Vehicle not reserved",
      variant: "error"
    });
  });

  it("blocks a retry after remote success and local save failure", async () => {
    const element = await createComponent();
    reserveVehicle.mockResolvedValue({
      remoteSucceeded: true,
      recordSaved: false,
      message:
        "The remote reservation succeeded, but Salesforce could not save the loan record."
    });

    reserveButton(element, "REG 123").click();
    await flushPromises();
    setLoanDetails(element);
    element.shadowRoot.querySelector("[data-confirm-reservation]").click();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "The remote reservation succeeded"
    );
    expect(
      element.shadowRoot.querySelector("[data-confirm-reservation]").disabled
    ).toBe(true);
  });

  it("returns an active loan and reloads available vehicles", async () => {
    const element = await createComponent(activeLoanContext());
    returnVehicle.mockResolvedValue({
      remoteSucceeded: true,
      recordSaved: true,
      message: "The vehicle has been returned."
    });
    getLoanContext.mockResolvedValueOnce(availableContext());

    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();

    expect(returnVehicle).toHaveBeenCalledWith({
      caseId: CASE_ID,
      loanVehicleId: ACTIVE_LOAN.Id
    });
    expect(element.shadowRoot.textContent).toContain("Available vehicles");
  });

  it("preserves the active loan and allows retry after a return failure", async () => {
    const element = await createComponent(activeLoanContext());
    const toastHandler = listenForToasts(element);
    returnVehicle.mockRejectedValue({
      body: { message: "The vehicle could not be returned. Please try again." }
    });

    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("Your active loan");
    expect(element.shadowRoot.querySelector("lightning-button").disabled).toBe(
      false
    );
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Vehicle not returned",
      variant: "error"
    });
  });

  it("shows a safe loading error when the Apex request fails", async () => {
    getLoanContext.mockRejectedValue(new Error("Internal detail"));
    const element = createElement("c-loan-vehicle-lwc", {
      is: LoanVehicleLWC
    });
    document.body.appendChild(element);
    element.recordId = CASE_ID;
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "Vehicle loan information could not be loaded. Please try again."
    );
    expect(element.shadowRoot.textContent).not.toContain("Internal detail");
  });

  it("has no accessibility violations in the vehicle list", async () => {
    const element = await createComponent();

    await expect(element).toBeAccessible();
  });
});
