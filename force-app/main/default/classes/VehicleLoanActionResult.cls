public class VehicleLoanActionResult {
  @AuraEnabled
  public Boolean remoteSucceeded { get; set; }
  @AuraEnabled
  public Boolean recordSaved { get; set; }
  @AuraEnabled
  public String message { get; set; }

  public VehicleLoanActionResult(
    Boolean remoteSucceeded,
    Boolean recordSaved,
    String message
  ) {
    this.remoteSucceeded = remoteSucceeded;
    this.recordSaved = recordSaved;
    this.message = message;
  }
}
