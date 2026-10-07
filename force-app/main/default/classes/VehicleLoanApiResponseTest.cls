@IsTest
private class VehicleLoanApiResponseTest {
  @IsTest
  static void deserializesMultipleVehiclesAndMapsVehicleRecords() {
    VehicleLoanApiResponse response = deserializeResponse(
      '[{"RegistrationNumber":"7897NV15","Make":"Nissan","Model":"Hardbody x38","YearOfVehicle":"2015"},{"RegistrationNumber":"11000DC17","Make":"Renault","Model":"kwid climber","YearOfVehicle":"2017"}]'
    );

    Assert.areEqual(2, response.vehicles.size());
    assertVehicle(
      response.vehicles[0],
      '7897NV15',
      'Nissan',
      'Hardbody x38',
      '2015'
    );
    assertVehicle(
      response.vehicles[1],
      '11000DC17',
      'Renault',
      'kwid climber',
      '2017'
    );

    Vehicle__c mappedRecord = response.vehicles[0].toVehicleRecord();
    Assert.areEqual('7897NV15', mappedRecord.Registration_number__c);
    Assert.areEqual('Nissan', mappedRecord.Make__c);
    Assert.areEqual('Hardbody x38', mappedRecord.Model__c);
    Assert.areEqual('2015', mappedRecord.Year_of_Vehicle__c);
    Assert.isNull(mappedRecord.Case__c);
    Assert.isNull(mappedRecord.Contact__c);
    Assert.isNull(mappedRecord.Mileage__c);
    Assert.isNull(mappedRecord.Engine_Capacity__c);
  }

  @IsTest
  static void supportsEmptyVehicleArray() {
    VehicleLoanApiResponse response = deserializeResponse('[]');

    Assert.isNotNull(response.vehicles);
    Assert.areEqual(0, response.vehicles.size());
  }

  @IsTest
  static void rejectsMissingRegistrationNumberOrModelBeforeMapping() {
    VehicleLoanApiResponse.Vehicle missingRegistration = new VehicleLoanApiResponse.Vehicle();
    missingRegistration.Model = 'Hardbody x38';
    assertInvalidVehicle(
      missingRegistration,
      'Vehicle response is missing required field RegistrationNumber.'
    );

    VehicleLoanApiResponse.Vehicle missingModel = new VehicleLoanApiResponse.Vehicle();
    missingModel.RegistrationNumber = '7897NV15';
    missingModel.Model = ' ';
    assertInvalidVehicle(
      missingModel,
      'Vehicle response is missing required field Model.'
    );
  }

  private static VehicleLoanApiResponse deserializeResponse(String jsonBody) {
    List<VehicleLoanApiResponse.Vehicle> vehicles = (List<VehicleLoanApiResponse.Vehicle>) JSON.deserialize(
      jsonBody,
      List<VehicleLoanApiResponse.Vehicle>.class
    );
    return new VehicleLoanApiResponse(vehicles);
  }

  private static void assertInvalidVehicle(
    VehicleLoanApiResponse.Vehicle vehicle,
    String expectedMessage
  ) {
    String errorMessage;
    try {
      vehicle.toVehicleRecord();
    } catch (IllegalArgumentException e) {
      errorMessage = e.getMessage();
    }

    Assert.areEqual(
      expectedMessage,
      errorMessage,
      'Incomplete API data should not be mapped to an incomplete Salesforce record'
    );
  }

  private static void assertVehicle(
    VehicleLoanApiResponse.Vehicle vehicle,
    String registrationNumber,
    String make,
    String model,
    String year
  ) {
    Assert.areEqual(registrationNumber, vehicle.RegistrationNumber);
    Assert.areEqual(make, vehicle.Make);
    Assert.areEqual(model, vehicle.Model);
    Assert.areEqual(year, vehicle.YearOfVehicle);
  }
}
