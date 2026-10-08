TiVitesse_Callout_Setting__mdt settings = [
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

if (
  String.isBlank(settings.grantType__c) ||
  String.isBlank(settings.clientId__c) ||
  String.isBlank(settings.clientSecret__c) ||
  String.isBlank(settings.username__c) ||
  String.isBlank(settings.password__c) ||
  String.isBlank(settings.securityToken__c)
) {
  throw new CalloutException(
    'The TiVitesse_Callout_Setting default record is missing required OAuth settings.'
  );
}

try {
  HttpRequest request = new HttpRequest();
  request.setEndpoint('callout:TiVitesseBearerToken');
  request.setMethod('POST');
  request.setTimeout(120000);
  request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
  request.setBody(
    'grant_type=' +
      EncodingUtil.urlEncode(settings.grantType__c, 'UTF-8') +
      '&client_id=' +
      EncodingUtil.urlEncode(settings.clientId__c, 'UTF-8') +
      '&client_secret=' +
      EncodingUtil.urlEncode(settings.clientSecret__c, 'UTF-8') +
      '&username=' +
      EncodingUtil.urlEncode(settings.username__c, 'UTF-8') +
      '&password=' +
      EncodingUtil.urlEncode(
        settings.password__c + settings.securityToken__c,
        'UTF-8'
      )
  );

  HttpResponse response = new Http().send(request);
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

  String accessToken = tokenResponse == null
    ? null
    : (String) tokenResponse.get('access_token');
  if (String.isBlank(accessToken)) {
    throw new CalloutException(
      'OAuth token response did not contain an access_token.'
    );
  }

  HttpRequest vehiclesRequest = new HttpRequest();
  vehiclesRequest.setEndpoint(
    'callout:TiVitesseNamedCredential/getVehicles/'
  );
  vehiclesRequest.setMethod('GET');
  vehiclesRequest.setHeader('Authorization', 'Bearer ' + accessToken);

  HttpResponse vehiclesResponse = new Http().send(vehiclesRequest);
  if (
    vehiclesResponse.getStatusCode() < 200 ||
    vehiclesResponse.getStatusCode() >= 300
  ) {
    throw new CalloutException(
      'getVehicles request failed with HTTP ' +
        vehiclesResponse.getStatusCode() +
        '.'
    );
  }

  List<Object> vehicles;
  try {
    vehicles = (List<Object>) JSON.deserializeUntyped(
      vehiclesResponse.getBody()
    );
  } catch (System.JSONException e) {
    throw new CalloutException(
      'getVehicles response was not a valid JSON vehicle array.'
    );
  } catch (System.TypeException e) {
    throw new CalloutException(
      'getVehicles response did not have the expected JSON array structure.'
    );
  }

  if (vehicles == null) {
    throw new CalloutException(
      'getVehicles response did not contain a JSON vehicle array.'
    );
  }

  System.debug(
    LoggingLevel.INFO,
    'SUCCESS: OAuth token was retrieved and getVehicles returned ' +
      vehicles.size() +
      ' vehicles.'
  );
} catch (CalloutException e) {
  String safeError = e.getMessage();
  List<String> sensitiveValues = new List<String>{
    settings.clientId__c,
    settings.clientSecret__c,
    settings.username__c,
    settings.password__c,
    settings.securityToken__c,
    settings.password__c + settings.securityToken__c
  };
  for (String sensitiveValue : sensitiveValues) {
    if (!String.isBlank(sensitiveValue)) {
      safeError = safeError.replace(sensitiveValue, '[REDACTED]');
      safeError = safeError.replace(
        EncodingUtil.urlEncode(sensitiveValue, 'UTF-8'),
        '[REDACTED]'
      );
    }
  }

  System.debug(LoggingLevel.ERROR, 'getAccessToken failed: ' + safeError);
  throw new CalloutException(safeError);
}
