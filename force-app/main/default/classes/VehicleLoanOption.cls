public class VehicleLoanOption {
  @AuraEnabled
  public String registrationNumber { get; set; }
  @AuraEnabled
  public String make { get; set; }
  @AuraEnabled
  public String model { get; set; }
  @AuraEnabled
  public String yearOfVehicle { get; set; }

  public VehicleLoanOption(VehicleLoanApiResponse.Vehicle vehicle) {
    registrationNumber = vehicle.RegistrationNumber;
    make = vehicle.Make;
    model = vehicle.Model;
    yearOfVehicle = vehicle.YearOfVehicle;
  }
}
