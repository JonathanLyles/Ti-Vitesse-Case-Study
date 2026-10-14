import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";

export default class CustomerHomeClaimsTile extends NavigationMixin(
  LightningElement
) {
  handleOpenClaims() {
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: {
        name: "My_Vehicle_Claims__c"
      }
    });
  }
}
