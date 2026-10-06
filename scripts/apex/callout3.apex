Tivitesse_Callout_Setting__mdt settings = Tivitesse_Callout_Setting__mdt.getInstance(
  'default'
);
VehicleLoanApiClient client = new VehicleLoanApiClient();
String accessToken = client.getAccessToken(
  settings.grantType__c,
  settings.clientId__c,
  settings.clientSecret__c,
  settings.username__c,
  settings.password__c,
  settings.securityToken__c
);

VehicleLoanApiResponse response = client.getVehicles(accessToken);
System.debug(
  LoggingLevel.INFO,
  'Retrieved ' + response.vehicles.size() + ' vehicles.'
);
