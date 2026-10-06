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
  String accessToken = new VehicleLoanApiClient()
    .getAccessToken(
      settings.grantType__c,
      settings.clientId__c,
      settings.clientSecret__c,
      settings.username__c,
      settings.password__c,
      settings.securityToken__c
    );

  if (String.isBlank(accessToken)) {
    throw new CalloutException(
      'getAccessToken returned an empty access token.'
    );
  }

  System.debug(
    LoggingLevel.INFO,
    'SUCCESS: getAccessToken returned a non-empty token; the OAuth response was successful.'
  );
} catch (CalloutException e) {
  String safeError = e.getMessage();
  List<String> sensitiveValues = new List<String>{
    settings.clientId__c,
    settings.clientSecret__c,
    settings.username__c,
    settings.password__c,
    settings.securityToken__c
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
