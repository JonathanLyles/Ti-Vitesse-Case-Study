import { createElement } from "@lwc/engine-dom";
import MyVehicleClaims from "c/myVehicleClaims";
import getMyClaims from "@salesforce/apex/CustomerClaimsController.getMyClaims";
import { setup } from "@sa11y/jest";
import { publishClaimSubmitted } from "c/claimEvents";

const claims = require("./data/claims.json");

jest.mock(
  "@salesforce/apex/CustomerClaimsController.getMyClaims",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// A getter, so each test can switch the user type before creating the component
let mockIsGuest = false;
jest.mock(
  "@salesforce/user/isGuest",
  () => ({
    __esModule: true,
    get default() {
      return mockIsGuest;
    }
  }),
  { virtual: true }
);

const GENERIC_ERROR = "Your claims could not be loaded. Please try again.";

// Promise-based Apex calls resolve on the microtask queue
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function cloneClaims() {
  return JSON.parse(JSON.stringify(claims));
}

// A claim submitted after the page loaded; it is newer than the ones in claims.json
function buildNewClaim() {
  return {
    Id: "500000000000004AAA",
    CaseNumber: "00001004",
    Subject: "Hit while parked",
    Status: "New",
    CreatedDate: "2026-10-04T09:00:00.000Z",
    Date_and_Time_of_Incident__c: "2026-10-03T19:00:00.000Z",
    Damage_Detail__c: "Dented door",
    Description: "Someone drove into the parked car"
  };
}

// A promise the test settles by hand, to control which load finishes first
function createDeferred() {
  const deferred = {};
  deferred.promise = new Promise((resolve, reject) => {
    deferred.resolve = resolve;
    deferred.reject = reject;
  });
  return deferred;
}

async function createComponent(data = cloneClaims()) {
  getMyClaims.mockResolvedValue(data);
  const element = createElement("c-my-vehicle-claims", {
    is: MyVehicleClaims
  });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

// Moves the element out of the page and back, which loads the claims again
async function reconnect(element, data) {
  getMyClaims.mockResolvedValue(data);
  document.body.removeChild(element);
  document.body.appendChild(element);
  await flushPromises();
}

function getCard(element) {
  return element.shadowRoot.querySelector("lightning-card");
}

function getRows(element) {
  return [...element.shadowRoot.querySelectorAll("button[data-id]")];
}

function getDetails(element) {
  return [...element.shadowRoot.querySelectorAll("[data-details]")];
}

function getCell(row, name) {
  return row.querySelector(`[data-cell="${name}"]`);
}

function getDetailText(element, selector) {
  return element.shadowRoot.querySelector(selector).textContent.trim();
}

async function click(row, element) {
  row.click();
  await flushPromises();
  return getRows(element);
}

describe("c-my-vehicle-claims", () => {
  // Registers the toBeAccessible matcher for this test file only
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    mockIsGuest = false;
    getMyClaims.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders nothing when the customer has no claims", async () => {
    const element = await createComponent([]);

    expect(getMyClaims).toHaveBeenCalledTimes(1);
    expect(getCard(element)).toBeNull();
    expect(element.shadowRoot.childElementCount).toBe(0);
  });

  it("renders nothing until the claims have loaded", async () => {
    getMyClaims.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-my-vehicle-claims", {
      is: MyVehicleClaims
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getCard(element)).toBeNull();
    expect(element.shadowRoot.childElementCount).toBe(0);
  });

  it("shows case number, subject, incident date, date submitted and status for each claim", async () => {
    const element = await createComponent();
    const rows = getRows(element);

    expect(rows).toHaveLength(3);
    expect(getCell(rows[0], "caseNumber").textContent).toBe("00001003");
    expect(getCell(rows[0], "subject").textContent).toBe(
      "Windscreen cracked by debris"
    );
    expect(
      getCell(rows[0], "incidentDate").querySelector(
        "lightning-formatted-date-time"
      ).value
    ).toBe("2026-09-30T14:30:00.000Z");
    expect(
      getCell(rows[0], "createdDate").querySelector(
        "lightning-formatted-date-time"
      ).value
    ).toBe("2026-10-01T09:00:00.000Z");
    expect(getCell(rows[0], "status").label).toBe("New");
    expect(getCell(rows[1], "status").label).toBe("In progress");
    expect(getCell(rows[2], "status").label).toBe("Closed");
  });

  it("lists the claims in the order returned by Apex (newest first)", async () => {
    const element = await createComponent();

    expect(
      getRows(element).map((row) => getCell(row, "caseNumber").textContent)
    ).toEqual(["00001003", "00001002", "00001001"]);
  });

  it("hides the details until a claim is clicked", async () => {
    const element = await createComponent();

    expect(getDetails(element)).toHaveLength(0);
    getRows(element).forEach((row) => {
      expect(row.getAttribute("aria-expanded")).toBe("false");
    });
  });

  it("shows the claim and vehicle details when a claim is clicked", async () => {
    const element = await createComponent();
    const rows = await click(getRows(element)[0], element);

    expect(rows[0].getAttribute("aria-expanded")).toBe("true");
    expect(getDetails(element)).toHaveLength(1);
    expect(getDetailText(element, "[data-detail=damageDetail]")).toBe(
      "Cracked windscreen"
    );
    expect(getDetailText(element, "[data-detail=description]")).toBe(
      "Stone thrown up by a lorry on the motorway"
    );
    expect(
      element.shadowRoot.querySelector(
        "[data-detail=incidentDate] lightning-formatted-date-time"
      ).value
    ).toBe("2026-09-30T14:30:00.000Z");
    expect(getDetailText(element, "[data-vehicle-field=make]")).toBe("Ford");
    expect(getDetailText(element, "[data-vehicle-field=model]")).toBe("Focus");
    expect(getDetailText(element, "[data-vehicle-field=registration]")).toBe(
      "FD19 XYZ"
    );
    expect(getDetailText(element, "[data-vehicle-field=mileage]")).toBe(
      "42000"
    );
    expect(getDetailText(element, "[data-vehicle-field=engineCapacity]")).toBe(
      "1600"
    );
  });

  it("collapses a claim when it is clicked again", async () => {
    const element = await createComponent();
    await click(getRows(element)[0], element);
    const rows = await click(getRows(element)[0], element);

    expect(rows[0].getAttribute("aria-expanded")).toBe("false");
    expect(getDetails(element)).toHaveLength(0);
  });

  it("expands one claim at a time", async () => {
    const element = await createComponent();
    await click(getRows(element)[0], element);
    const rows = await click(getRows(element)[1], element);

    expect(rows[0].getAttribute("aria-expanded")).toBe("false");
    expect(rows[1].getAttribute("aria-expanded")).toBe("true");
    expect(getDetails(element)).toHaveLength(1);
    expect(getDetailText(element, "[data-detail=damageDetail]")).toBe(
      "Rear bumper dented"
    );
  });

  it("shows the claim details when the claim has no vehicle", async () => {
    const element = await createComponent();
    await click(getRows(element)[2], element);

    expect(getDetails(element)).toHaveLength(1);
    expect(getDetailText(element, "[data-detail=damageDetail]")).toBe(
      "Left mirror missing"
    );
    expect(element.shadowRoot.querySelectorAll("[data-vehicle]")).toHaveLength(
      0
    );
  });

  it("shows the error message and no claims when loading fails", async () => {
    getMyClaims.mockRejectedValue({
      body: { message: "Your claims could not be loaded: no access" }
    });
    const element = createElement("c-my-vehicle-claims", {
      is: MyVehicleClaims
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getDetailText(element, "[data-error]")).toBe(
      "Your claims could not be loaded: no access"
    );
    expect(getRows(element)).toHaveLength(0);
  });

  it("has no accessibility violations with the claims collapsed", async () => {
    const element = await createComponent();

    await expect(element).toBeAccessible();
  });

  it("has no accessibility violations with a claim expanded", async () => {
    const element = await createComponent();
    await click(getRows(element)[1], element);

    await expect(element).toBeAccessible();
  });

  it("shows no 'undefined' or 'null' text for missing optional fields", async () => {
    const data = cloneClaims();
    data[0].Date_and_Time_of_Incident__c = null;
    delete data[0].Damage_Detail__c;
    data[0].Description = null;
    const element = await createComponent(data);
    await click(getRows(element)[0], element);

    expect(
      getCell(getRows(element)[0], "incidentDate").querySelector(
        "lightning-formatted-date-time"
      )
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector(
        "[data-detail=incidentDate] lightning-formatted-date-time"
      )
    ).toBeNull();
    expect(getDetailText(element, "[data-detail=damageDetail]")).toBe("");
    expect(getDetailText(element, "[data-detail=description]")).toBe("");
    const text = element.shadowRoot.textContent;
    expect(text).not.toContain("undefined");
    expect(text).not.toContain("null");
  });

  it("collapses the expanded claim when it is missing after the claims reload", async () => {
    const element = await createComponent();
    await click(getRows(element)[0], element);
    expect(getDetails(element)).toHaveLength(1);

    await reconnect(element, cloneClaims().slice(1));

    expect(getRows(element)).toHaveLength(2);
    expect(getDetails(element)).toHaveLength(0);
    expect(element.shadowRoot.querySelector("[data-error]")).toBeNull();
  });

  it("disappears when a reload returns no claims", async () => {
    const element = await createComponent();
    expect(getCard(element)).not.toBeNull();

    await reconnect(element, []);

    expect(getCard(element)).toBeNull();
  });

  it("shows a generic message when the error has no message", async () => {
    getMyClaims.mockRejectedValue(new Error("Network failure"));
    const element = createElement("c-my-vehicle-claims", {
      is: MyVehicleClaims
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getDetailText(element, "[data-error]")).toBe(GENERIC_ERROR);
  });

  it("shows every vehicle when a claim has more than one", async () => {
    const element = await createComponent();
    await click(getRows(element)[1], element);

    const vehicles = [...element.shadowRoot.querySelectorAll("[data-vehicle]")];
    expect(vehicles).toHaveLength(2);
    expect(vehicles[0].querySelector("h3").textContent.trim()).toBe(
      "Damaged vehicle 1"
    );
    expect(
      vehicles[0].querySelector("[data-vehicle-field=model]").textContent.trim()
    ).toBe("Golf");
    expect(vehicles[1].querySelector("h3").textContent.trim()).toBe(
      "Damaged vehicle 2"
    );
    expect(
      vehicles[1].querySelector("[data-vehicle-field=model]").textContent.trim()
    ).toBe("Passat");
  });

  it("reloads and shows the new claim at the top when a claim is submitted", async () => {
    const element = await createComponent();
    getMyClaims.mockResolvedValue([buildNewClaim(), ...cloneClaims()]);

    publishClaimSubmitted();
    await flushPromises();

    const rows = getRows(element);
    expect(getMyClaims).toHaveBeenCalledTimes(2);
    expect(rows).toHaveLength(4);
    expect(getCell(rows[0], "caseNumber").textContent).toBe("00001004");
    expect(getCell(rows[0], "subject").textContent).toBe("Hit while parked");
  });

  it("appears when a customer with no claims submits their first claim", async () => {
    const element = await createComponent([]);
    expect(getCard(element)).toBeNull();
    getMyClaims.mockResolvedValue([buildNewClaim()]);

    publishClaimSubmitted();
    await flushPromises();

    expect(getCard(element)).not.toBeNull();
    expect(getRows(element)).toHaveLength(1);
  });

  it("keeps an expanded claim expanded when the list reloads", async () => {
    const element = await createComponent();
    await click(getRows(element)[0], element);
    getMyClaims.mockResolvedValue([buildNewClaim(), ...cloneClaims()]);

    publishClaimSubmitted();
    await flushPromises();

    const expanded = element.shadowRoot.querySelector(
      'button[data-id="500000000000003AAA"]'
    );
    expect(getRows(element)).toHaveLength(4);
    expect(expanded.getAttribute("aria-expanded")).toBe("true");
    expect(getDetails(element)).toHaveLength(1);
  });

  it("shows the error message when the reload after a submit fails", async () => {
    const element = await createComponent();
    getMyClaims.mockRejectedValue({ body: { message: "Reload failed" } });

    publishClaimSubmitted();
    await flushPromises();

    expect(getDetailText(element, "[data-error]")).toBe("Reload failed");
    expect(getRows(element)).toHaveLength(0);
  });

  it("stops reloading once it has been removed from the page", async () => {
    const element = await createComponent();
    document.body.removeChild(element);

    publishClaimSubmitted();
    await flushPromises();

    expect(getMyClaims).toHaveBeenCalledTimes(1);
  });

  it("reloads only once per submitted claim after it has been reconnected", async () => {
    const element = await createComponent();
    await reconnect(element, cloneClaims());
    expect(getMyClaims).toHaveBeenCalledTimes(2);

    publishClaimSubmitted();
    await flushPromises();

    expect(getMyClaims).toHaveBeenCalledTimes(3);
  });

  it("ignores a slow earlier load that finishes after a newer one", async () => {
    const slowLoad = createDeferred();
    getMyClaims.mockReturnValueOnce(slowLoad.promise);
    getMyClaims.mockResolvedValueOnce([buildNewClaim(), ...cloneClaims()]);
    const element = createElement("c-my-vehicle-claims", {
      is: MyVehicleClaims
    });
    document.body.appendChild(element);
    publishClaimSubmitted();
    await flushPromises();
    expect(getRows(element)).toHaveLength(4);

    // The first load finally returns, with the older list that lacks the new claim
    slowLoad.resolve(cloneClaims());
    await flushPromises();

    const rows = getRows(element);
    expect(rows).toHaveLength(4);
    expect(getCell(rows[0], "caseNumber").textContent).toBe("00001004");
  });

  it("ignores a slow earlier load that fails after a newer one succeeded", async () => {
    const slowLoad = createDeferred();
    getMyClaims.mockReturnValueOnce(slowLoad.promise);
    getMyClaims.mockResolvedValueOnce([buildNewClaim(), ...cloneClaims()]);
    const element = createElement("c-my-vehicle-claims", {
      is: MyVehicleClaims
    });
    document.body.appendChild(element);
    publishClaimSubmitted();
    await flushPromises();

    slowLoad.reject({ body: { message: "Late failure" } });
    await flushPromises();

    expect(element.shadowRoot.querySelector("[data-error]")).toBeNull();
    expect(getRows(element)).toHaveLength(4);
  });

  it("renders nothing and never calls Apex for a guest", async () => {
    // The isGuest import is read once, when the component module loads, so the
    // guest needs its own copy of the module (and of the engine and Apex mock
    // that go with it)
    mockIsGuest = true;
    let guestCreateElement;
    let GuestClaims;
    let guestGetMyClaims;
    jest.isolateModules(() => {
      guestCreateElement = require("@lwc/engine-dom").createElement;
      GuestClaims = require("c/myVehicleClaims").default;
      guestGetMyClaims =
        require("@salesforce/apex/CustomerClaimsController.getMyClaims").default;
    });
    guestGetMyClaims.mockResolvedValue(cloneClaims());

    // Another tag name, because "c-my-vehicle-claims" is already registered
    const element = guestCreateElement("c-my-vehicle-claims-guest", {
      is: GuestClaims
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(guestGetMyClaims).not.toHaveBeenCalled();
    expect(getCard(element)).toBeNull();
    expect(element.shadowRoot.childElementCount).toBe(0);
  });
});
