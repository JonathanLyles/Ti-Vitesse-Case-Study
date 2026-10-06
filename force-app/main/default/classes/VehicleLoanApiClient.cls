public with sharing class VehicleLoanApiClient {
  public String getAccessToken(
    String grantType,
    String clientId,
    String clientSecret,
    String username,
    String password,
    String securityToken
  ) {
    Http http = new Http();
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:TiVitesseBearerToken');
    request.setMethod('POST');
    request.setTimeout(2 * 60 * 1000);
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    request.setBody(
      'grant_type=' +
        encodeFormValue(grantType) +
        '&client_id=' +
        encodeFormValue(clientId) +
        '&client_secret=' +
        encodeFormValue(clientSecret) +
        '&username=' +
        encodeFormValue(username) +
        '&password=' +
        encodeFormValue(password + (securityToken == null ? '' : securityToken))
    );

    HttpResponse response = http.send(request);

    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new CalloutException(
        'OAuth token request failed with HTTP ' +
          response.getStatusCode() +
          ': ' +
          response.getBody()
      );
    }

    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    String accessToken = (String) responseMap.get('access_token');
    if (String.isBlank(accessToken)) {
      throw new CalloutException(
        'OAuth token response did not contain an access_token.'
      );
    }
    return accessToken;
  }

  private static String encodeFormValue(String value) {
    return EncodingUtil.urlEncode(value, 'UTF-8');
  }

  public VehicleLoanApiResponse getVehicles(String accessToken) {
    Http http = new Http();
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:TiVitesseNamedCredential/getVehicles/');
    request.setHeader('Authorization', 'Bearer ' + accessToken);
    request.setMethod('GET');
    HttpResponse response = http.send(request);

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
}
