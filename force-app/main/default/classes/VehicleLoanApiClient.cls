public with sharing class VehicleLoanApiClient {
  private static String cachedAccessToken;

  private static OAuthSettings testOAuthSettings;

  public VehicleLoanApiResponse getVehicles() {
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:TiVitesseNamedCredential/getVehicles/');
    request.setMethod('GET');
    request.setHeader('Authorization', 'Bearer ' + getAccessToken());

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new CalloutException('Vehicle request failed.');
    }
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new CalloutException(
        'Vehicle request failed with HTTP ' + response.getStatusCode() + '.'
      );
    }

    List<VehicleLoanApiResponse.Vehicle> vehicles;
    try {
      vehicles = (List<VehicleLoanApiResponse.Vehicle>) JSON.deserialize(
        response.getBody(),
        List<VehicleLoanApiResponse.Vehicle>.class
      );
    } catch (System.JSONException e) {
      throw new CalloutException(
        'Vehicle response did not contain a valid JSON array.'
      );
    } catch (System.TypeException e) {
      throw new CalloutException(
        'Vehicle response did not have the expected JSON array structure.'
      );
    }
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
    request.setHeader('Authorization', 'Bearer ' + getAccessToken());

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new CalloutException('Vehicle update request failed.');
    }
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new CalloutException(
        'Vehicle update failed with HTTP ' + response.getStatusCode() + '.'
      );
    }
  }

  private static String getAccessToken() {
    if (!String.isBlank(cachedAccessToken)) {
      return cachedAccessToken;
    }

    OAuthSettings settings = getOAuthSettings();
    if (
      String.isBlank(settings.grantType) ||
      String.isBlank(settings.clientId) ||
      String.isBlank(settings.clientSecret) ||
      String.isBlank(settings.username) ||
      String.isBlank(settings.password) ||
      String.isBlank(settings.securityToken)
    ) {
      throw new CalloutException(
        'The TiVitesse_Callout_Setting default record is missing required OAuth settings.'
      );
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:TiVitesseBearerToken');
    request.setMethod('POST');
    request.setTimeout(120000);
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    request.setBody(
      'grant_type=' +
        encodeFormValue(settings.grantType) +
        '&client_id=' +
        encodeFormValue(settings.clientId) +
        '&client_secret=' +
        encodeFormValue(settings.clientSecret) +
        '&username=' +
        encodeFormValue(settings.username) +
        '&password=' +
        encodeFormValue(settings.password + settings.securityToken)
    );

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new CalloutException('OAuth token request failed.');
    }
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new CalloutException(
        'OAuth token request failed with HTTP ' + response.getStatusCode() + '.'
      );
    }

    Map<String, Object> tokenResponse;
    try {
      tokenResponse = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
    } catch (System.JSONException e) {
      throw new CalloutException('OAuth token response was not valid JSON.');
    } catch (System.TypeException e) {
      throw new CalloutException(
        'OAuth token response did not have the expected JSON structure.'
      );
    }

    Object tokenValue = tokenResponse == null
      ? null
      : tokenResponse.get('access_token');
    if (
      !(tokenValue instanceof String) || String.isBlank((String) tokenValue)
    ) {
      throw new CalloutException(
        'OAuth token response did not contain an access_token.'
      );
    }

    cachedAccessToken = (String) tokenValue;
    return cachedAccessToken;
  }

  @TestVisible
  private static void setTestOAuthSettings(
    String grantType,
    String clientId,
    String clientSecret,
    String username,
    String password,
    String securityToken
  ) {
    testOAuthSettings = new OAuthSettings(
      grantType,
      clientId,
      clientSecret,
      username,
      password,
      securityToken
    );
    cachedAccessToken = null;
  }

  private static OAuthSettings getOAuthSettings() {
    if (Test.isRunningTest() && testOAuthSettings != null) {
      return testOAuthSettings;
    }

    List<TiVitesse_Callout_Setting__mdt> settings = [
      SELECT
        grantType__c,
        clientId__c,
        clientSecret__c,
        username__c,
        password__c,
        securityToken__c
      FROM TiVitesse_Callout_Setting__mdt
      WHERE DeveloperName = 'default'
      LIMIT 1
    ];
    if (settings.isEmpty()) {
      throw new CalloutException(
        'The TiVitesse_Callout_Setting default record is missing required OAuth settings.'
      );
    }

    return new OAuthSettings(settings[0]);
  }

  private static String encodeFormValue(String value) {
    return EncodingUtil.urlEncode(value, 'UTF-8');
  }

  private static String encodePathSegment(String value) {
    return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
  }

  private class OAuthSettings {
    private String grantType;
    private String clientId;
    private String clientSecret;
    private String username;
    private String password;
    private String securityToken;

    private OAuthSettings(TiVitesse_Callout_Setting__mdt settings) {
      grantType = settings.grantType__c;
      clientId = settings.clientId__c;
      clientSecret = settings.clientSecret__c;
      username = settings.username__c;
      password = settings.password__c;
      securityToken = settings.securityToken__c;
    }

    private OAuthSettings(
      String grantType,
      String clientId,
      String clientSecret,
      String username,
      String password,
      String securityToken
    ) {
      this.grantType = grantType;
      this.clientId = clientId;
      this.clientSecret = clientSecret;
      this.username = username;
      this.password = password;
      this.securityToken = securityToken;
    }
  }
}
