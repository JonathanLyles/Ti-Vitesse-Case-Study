public with sharing class VehicleLoanApiClient {
  public VehicleLoanApiResponse getVehicles() {
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:TiVitesseNamedCredential/getVehicles/');
    request.setMethod('GET');

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new CalloutException(
        'Vehicle request failed with HTTP ' +
          response.getStatusCode() +
          ': ' +
          response.getBody()
      );
    }

    List<VehicleLoanApiResponse.Vehicle> vehicles = (List<VehicleLoanApiResponse.Vehicle>) JSON.deserialize(
      response.getBody(),
      List<VehicleLoanApiResponse.Vehicle>.class
    );
    if (vehicles == null) {
      throw new CalloutException(
        'Vehicle response did not contain a JSON array.'
      );
    }
    return new VehicleLoanApiResponse(vehicles);
  }

  public void updateVehicle(String registrationNumber) {
    if (String.isBlank(registrationNumber)) {
      throw new CalloutException(
        'Vehicle request requires a nonblank registration number.'
      );
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      'callout:TiVitesseNamedCredential/updateVehicle/' +
      encodePathSegment(registrationNumber)
    );
    request.setMethod('POST');
    request.setBody('');

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new CalloutException(
        'Vehicle update failed with HTTP ' +
          response.getStatusCode() +
          ': ' +
          response.getBody()
      );
    }
  }

  private static String encodePathSegment(String value) {
    return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
  }
}
