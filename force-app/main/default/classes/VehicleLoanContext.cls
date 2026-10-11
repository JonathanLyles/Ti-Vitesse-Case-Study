public class VehicleLoanContext {
  @AuraEnabled
  public List<VehicleLoanOption> availableVehicles { get; set; }
  @AuraEnabled
  public Vehicle__c activeLoan { get; set; }
  @AuraEnabled
  public Boolean canReturnActiveLoan { get; set; }

  public VehicleLoanContext() {
    availableVehicles = new List<VehicleLoanOption>();
    canReturnActiveLoan = false;
  }
}
