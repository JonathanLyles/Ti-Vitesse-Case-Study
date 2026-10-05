import {
  subscribeToClaimSubmitted,
  publishClaimSubmitted
} from "c/claimEvents";

// Subscriptions live in the module, so each test removes its own afterwards
const unsubscribers = [];

function subscribe(handler) {
  const unsubscribe = subscribeToClaimSubmitted(handler);
  unsubscribers.push(unsubscribe);
  return unsubscribe;
}

describe("c-claim-events", () => {
  afterEach(() => {
    unsubscribers.splice(0).forEach((unsubscribe) => unsubscribe());
  });

  it("calls a subscriber each time a claim is submitted", () => {
    const handler = jest.fn();
    subscribe(handler);

    publishClaimSubmitted();
    publishClaimSubmitted();

    expect(handler).toHaveBeenCalledTimes(2);
  });

  it("calls every subscriber", () => {
    const first = jest.fn();
    const second = jest.fn();
    subscribe(first);
    subscribe(second);

    publishClaimSubmitted();

    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(1);
  });

  it("stops calling a subscriber after it unsubscribes", () => {
    const handler = jest.fn();
    const other = jest.fn();
    const unsubscribe = subscribe(handler);
    subscribe(other);

    unsubscribe();
    publishClaimSubmitted();

    expect(handler).not.toHaveBeenCalled();
    expect(other).toHaveBeenCalledTimes(1);
  });

  it("does nothing when nobody is subscribed", () => {
    expect(() => publishClaimSubmitted()).not.toThrow();
  });

  it("runs every subscriber even if one throws, then throws the first error", () => {
    const failing = jest.fn(() => {
      throw new Error("Subscriber failed");
    });
    const after = jest.fn();
    subscribe(failing);
    subscribe(after);

    expect(() => publishClaimSubmitted()).toThrow("Subscriber failed");
    expect(failing).toHaveBeenCalledTimes(1);
    expect(after).toHaveBeenCalledTimes(1);
  });
});
