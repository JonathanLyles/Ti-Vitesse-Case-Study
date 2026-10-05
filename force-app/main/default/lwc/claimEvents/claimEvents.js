/**
 * Lets components on the same Experience Cloud page tell each other that a claim
 * was submitted. The page loads this module once, so every component that imports
 * it shares the same list of subscribers. createVehicleClaim publishes and
 * myVehicleClaims subscribes, so the claims list refreshes without a page reload.
 */
const subscribers = new Set();

/**
 * Registers a function to call whenever a claim has been submitted.
 * @param {Function} handler Called with no arguments.
 * @returns {Function} Call it to stop receiving events (do this in
 *   disconnectedCallback).
 */
export function subscribeToClaimSubmitted(handler) {
  subscribers.add(handler);
  return () => {
    subscribers.delete(handler);
  };
}

/**
 * Tells every subscriber that a claim was submitted. A subscriber that throws does
 * not stop the others; the first error is thrown once all of them have run.
 */
export function publishClaimSubmitted() {
  let firstError;
  [...subscribers].forEach((handler) => {
    try {
      handler();
    } catch (error) {
      firstError = firstError ?? error;
    }
  });
  if (firstError) {
    throw firstError;
  }
}
