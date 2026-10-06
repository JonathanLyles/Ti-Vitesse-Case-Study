public class VehicleLoanApiResponse {
  public List<Vehicle> vehicles { get; private set; }

  public VehicleLoanApiResponse(List<Vehicle> vehicles) {
    this.vehicles = vehicles;
  }

  public class Vehicle {
    public String RegistrationNumber { get; set; }
    public String Make { get; set; }
    public String Model { get; set; }
    public String YearOfVehicle { get; set; }

    public Vehicle__c toVehicleRecord() {
      return new Vehicle__c(
        Registration_number__c = RegistrationNumber,
        Make__c = Make,
        Model__c = Model,
        Year_of_Vehicle__c = YearOfVehicle
      );
    }
  }
}
