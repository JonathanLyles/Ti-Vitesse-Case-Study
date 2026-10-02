import { createElement } from "@lwc/engine-dom";
import CreateVehicleClaim from "c/createVehicleClaim";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { getRecord } from "lightning/uiRecordApi";
import createClaim from "@salesforce/apex/VehicleClaimController.createClaim";
import getVehicleRecordTypeId from "@salesforce/apex/VehicleClaimController.getVehicleRecordTypeId";

const caseObjectInfo = require("./data/caseObjectInfo.json");
const vehicleObjectInfo = require("./data/vehicleObjectInfo.json");
const makePicklistValues = require("./data/makePicklistValues.json");
const caseRecord = require("./data/caseRecord.json");

jest.mock(
  "@salesforce/apex/VehicleClaimController.createClaim",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/VehicleClaimController.getVehicleRecordTypeId",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const TOAST_EVENT = "lightning__showtoast";
const DAMAGED_VEHICLE_RECORD_TYPE_ID = "012000000000001AAA";
const CASE_ID = "500000000000001AAA";

const FORM_VALUES = {
  incidentDate: "2026-09-30T14:30:00.000Z",
  subject: "Rear-ended at traffic lights",
  damageDetail: "Rear bumper dented",
  description: "Hit from behind while stationary",
  make: "Volkswagen",
  model: "Golf",
  registration: "AB12 CDE",
  mileage: "42000",
  engineCapacity: "1600"
};

// Promise-based Apex calls resolve on the microtask queue
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function objectApiName(config) {
  return config.objectApiName?.objectApiName ?? config.objectApiName;
}

async function createComponent() {
  const element = createElement("c-create-vehicle-claim", {
    is: CreateVehicleClaim
  });
  document.body.appendChild(element);
  getObjectInfo.emit(
    caseObjectInfo,
    (config) => objectApiName(config) === "Case"
  );
  getObjectInfo.emit(
    vehicleObjectInfo,
    (config) => objectApiName(config) === "Vehicle__c"
  );
  getVehicleRecordTypeId.emit(DAMAGED_VEHICLE_RECORD_TYPE_ID);
  await flushPromises();
  getPicklistValues.emit(makePicklistValues);
  await flushPromises();
  return element;
}

function getInputs(element) {
  return [...element.shadowRoot.querySelectorAll("[data-field]")];
}

function getInput(element, field) {
  return element.shadowRoot.querySelector(`[data-field="${field}"]`);
}

// The base component stubs don't validate, so each test decides the result
function setValidity(element, isValid) {
  getInputs(element).forEach((input) => {
    input.reportValidity = jest.fn(() => isValid);
  });
}

function fillForm(element) {
  Object.entries(FORM_VALUES).forEach(([field, value]) => {
    const input = getInput(element, field);
    input.value = value;
    input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  });
}

function listenForToasts(element) {
  const handler = jest.fn();
  element.addEventListener(TOAST_EVENT, handler);
  return handler;
}

function submit(element) {
  element.shadowRoot.querySelector("lightning-button").click();
}

describe("c-create-vehicle-claim", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the incident and vehicle fields with org labels and Make options", async () => {
    const element = await createComponent();

    expect(getInputs(element).map((input) => input.dataset.field)).toEqual(
      Object.keys(FORM_VALUES)
    );
    expect(getInput(element, "incidentDate").label).toBe(
      "Date and Time of Incident"
    );
    expect(getInput(element, "engineCapacity").label).toBe("Engine Capacity");
    expect(getInput(element, "make").options).toEqual([
      { label: "Ford", value: "Ford" },
      { label: "Volkswagen", value: "Volkswagen" }
    ]);
    expect(getPicklistValues.getLastConfig().recordTypeId).toBe(
      DAMAGED_VEHICLE_RECORD_TYPE_ID
    );
  });

  it("shows a warning toast and does not submit when required fields are missing", async () => {
    const element = await createComponent();
    const toastHandler = listenForToasts(element);
    setValidity(element, false);

    submit(element);
    await flushPromises();

    expect(createClaim).not.toHaveBeenCalled();
    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Missing information",
      variant: "warning"
    });
  });

  it("submits the claim, shows a success toast with the Case number and clears the form", async () => {
    createClaim.mockResolvedValue(CASE_ID);
    const element = await createComponent();
    const toastHandler = listenForToasts(element);
    fillForm(element);
    setValidity(element, true);

    submit(element);
    await flushPromises();

    expect(createClaim).toHaveBeenCalledWith({
      claim: {
        sobjectType: "Case",
        Date_and_Time_of_Incident__c: FORM_VALUES.incidentDate,
        Subject: FORM_VALUES.subject,
        Damage_Detail__c: FORM_VALUES.damageDetail,
        Description: FORM_VALUES.description
      },
      vehicle: {
        sobjectType: "Vehicle__c",
        Make__c: "Volkswagen",
        Model__c: "Golf",
        Registration_number__c: "AB12 CDE",
        Mileage__c: 42000,
        Engine_Capacity__c: 1600
      }
    });

    getRecord.emit(caseRecord);
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Claim submitted",
      message:
        "Your claim has been submitted. Your reference number is 00001234.",
      variant: "success"
    });
    getInputs(element).forEach((input) => expect(input.value).toBeUndefined());
  });

  it("shows an error toast with the server message and keeps the form values", async () => {
    createClaim.mockRejectedValue({
      body: {
        message: "The date and time of the incident cannot be in the future."
      }
    });
    const element = await createComponent();
    const toastHandler = listenForToasts(element);
    fillForm(element);
    setValidity(element, true);

    submit(element);
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Claim not submitted",
      message: "The date and time of the incident cannot be in the future.",
      variant: "error"
    });
    expect(getInput(element, "subject").value).toBe(FORM_VALUES.subject);
    expect(getInput(element, "mileage").value).toBe(FORM_VALUES.mileage);
  });
});
