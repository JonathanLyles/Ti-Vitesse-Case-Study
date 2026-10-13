public class VehicleLoanContext {
  @AuraEnabled
  public List<VehicleLoanOption> availableVehicles { get; set; }
  @AuraEnabled
  public Vehicle__c activeLoan { get; set; }
  // False when the Contact has no open Vehicle Claims Case, so no loan can be reserved
  @AuraEnabled
  public Boolean hasOpenClaim { get; set; }
  // The claim a reservation will be linked to: the Contact's most recent open claim
  @AuraEnabled
  public String claimCaseNumber { get; set; }

  public VehicleLoanContext() {
    availableVehicles = new List<VehicleLoanOption>();
    hasOpenClaim = false;
  }
}
