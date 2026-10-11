VehicleLoanApiResponse response = new VehicleLoanApiClient().getVehicles();

if (response == null || response.vehicles == null) {
  throw new CalloutException(
    'VehicleLoanApiClient.getVehicles did not return a vehicle list.'
  );
}
if (response.vehicles.isEmpty()) {
  throw new CalloutException(
    'VehicleLoanApiClient.getVehicles returned an empty vehicle list.'
  );
}

Integer index = 0;
for (VehicleLoanApiResponse.Vehicle vehicle : response.vehicles) {
  System.debug(
    LoggingLevel.INFO,
    'VEHICLE[' +
      index +
      '] registration=' +
      vehicle.RegistrationNumber +
      ', make=' +
      vehicle.Make +
      ', model=' +
      vehicle.Model +
      ', year=' +
      vehicle.YearOfVehicle
  );
  index++;
}

System.debug(
  LoggingLevel.INFO,
  'SUCCESS: VehicleLoanApiClient.getVehicles returned ' +
    response.vehicles.size() +
    ' vehicles.'
);
