import { createElement } from "@lwc/engine-dom";
import CustomerHomeClaimsTile from "c/customerHomeClaimsTile";

const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        mockNavigate(pageReference);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin };
});

describe("c-customer-home-claims-tile", () => {
  beforeEach(() => {
    mockNavigate.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens My Vehicle Claims when the tile is clicked", () => {
    const element = createElement("c-customer-home-claims-tile", {
      is: CustomerHomeClaimsTile
    });
    document.body.appendChild(element);

    element.shadowRoot.querySelector("[data-open-claims]").click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "comm__namedPage",
      attributes: {
        name: "My_Vehicle_Claims__c"
      }
    });
  });
});
