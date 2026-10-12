@IsTest
private class VehicleLoanApiClientTest {
  private static final String ACCESS_TOKEN = 'fake-access-token';
  private static final String VEHICLE_RESPONSE = '[{"RegistrationNumber":"7897NV15","Make":"Nissan","Model":"Hardbody x38","YearOfVehicle":"2015"}]';

  @IsTest
  static void getsTokenAndParsesVehiclesWithBearerAuthorization() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, '{"access_token":"' + ACCESS_TOKEN + '"}');
    mock.addVehicleResponse(200, VEHICLE_RESPONSE);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    VehicleLoanApiResponse response = new VehicleLoanApiClient().getVehicles();
    Test.stopTest();

    Assert.areEqual(2, mock.requestCount);
    Assert.areEqual(1, response.vehicles.size());
    Assert.areEqual('7897NV15', response.vehicles[0].RegistrationNumber);
    Assert.areEqual('Nissan', response.vehicles[0].Make);
    Assert.areEqual('Hardbody x38', response.vehicles[0].Model);
    Assert.areEqual('2015', response.vehicles[0].YearOfVehicle);
  }
  @IsTest
  static void rejectsVehicleListWhenServiceReturnsFailureWithoutBody() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, '{"access_token":"' + ACCESS_TOKEN + '"}');
    mock.addVehicleResponse(503, '{"error":"service unavailable"}');
    Test.setMock(HttpCalloutMock.class, mock);

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.isTrue(
      errorMessage != null &&
        errorMessage.contains('HTTP 503') &&
        !errorMessage.contains('service unavailable'),
      'A non-2xx vehicle response should fail'
    );
    Assert.areEqual(2, mock.requestCount);
  }

  @IsTest
  static void postsEncodedRegistrationWithBearerAndAcceptsAny2xxStatus() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, '{"access_token":"' + ACCESS_TOKEN + '"}');
    mock.addVehicleResponse(
      204,
      'callout:TiVitesseNamedCredential/updateVehicle/REG%20123',
      'POST',
      'Bearer ' + ACCESS_TOKEN,
      'not JSON'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    new VehicleLoanApiClient().updateVehicle('REG 123');
    Test.stopTest();

    Assert.areEqual(2, mock.requestCount);
  }

  @IsTest
  static void rejectsReservationWhenServiceReturnsFailure() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, '{"access_token":"' + ACCESS_TOKEN + '"}');
    mock.addVehicleResponse(
      503,
      'callout:TiVitesseNamedCredential/updateVehicle/7897NV15',
      'POST',
      'Bearer ' + ACCESS_TOKEN,
      '{"error":"service unavailable"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    String errorMessage;
    try {
      new VehicleLoanApiClient().updateVehicle('7897NV15');
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.isTrue(
      errorMessage != null &&
        errorMessage.contains('HTTP 503') &&
        !errorMessage.contains('service unavailable'),
      'A non-2xx reservation response should fail'
    );
    Assert.areEqual(2, mock.requestCount);
  }

  @IsTest
  static void reusesOneTokenAcrossVehicleOperationsInTransaction() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, '{"access_token":"' + ACCESS_TOKEN + '"}');
    mock.addVehicleResponse(200, VEHICLE_RESPONSE);
    mock.addVehicleResponse(
      200,
      'callout:TiVitesseNamedCredential/updateVehicle/7897NV15',
      'POST',
      'Bearer ' + ACCESS_TOKEN,
      ''
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    VehicleLoanApiClient client = new VehicleLoanApiClient();
    client.getVehicles();
    client.updateVehicle('7897NV15');
    Test.stopTest();

    Assert.areEqual(
      3,
      mock.requestCount,
      'One token request should be shared by both vehicle requests.'
    );
  }

  @IsTest
  static void rejectsTokenEndpointFailureWithoutExposingResponseBody() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(401, '{"error":"fake client secret"}');
    Test.setMock(HttpCalloutMock.class, mock);

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual('OAuth token request failed with HTTP 401.', errorMessage);
    Assert.isFalse(errorMessage.contains('fake client secret'));
    Assert.areEqual(1, mock.requestCount);
  }

  @IsTest
  static void rejectsMalformedTokenResponseAndDoesNotCallVehicleEndpoint() {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, 'not JSON');
    Test.setMock(HttpCalloutMock.class, mock);

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual('OAuth token response was not valid JSON.', errorMessage);
    Assert.areEqual(1, mock.requestCount);
  }

  @IsTest
  static void rejectsMissingOAuthSettingsBeforeCallout() {
    VehicleLoanApiClient.setTestOAuthSettings(
      '',
      'fake-client-id',
      'fake-client-secret',
      'fake-user',
      'fake-password',
      'fake-security-token'
    );
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual(
      'The TiVitesse_Callout_Setting default record is missing required OAuth settings.',
      errorMessage
    );
  }

  @IsTest
  static void rejectsBlankRegistrationBeforeCallout() {
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String errorMessage;
    try {
      new VehicleLoanApiClient().updateVehicle(' ');
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual(
      'Vehicle request requires a nonblank registration number.',
      errorMessage
    );
  }

  @IsTest
  static void reportsNetworkFailureWhenLoadingVehicles() {
    setFakeOAuthSettings();
    Test.setMock(HttpCalloutMock.class, new NetworkFailureMock(false));

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual('Vehicle request failed.', errorMessage);
  }

  @IsTest
  static void reportsNetworkFailureWhenUpdatingVehicle() {
    setFakeOAuthSettings();
    Test.setMock(HttpCalloutMock.class, new NetworkFailureMock(false));

    String errorMessage;
    try {
      new VehicleLoanApiClient().updateVehicle('7897NV15');
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual('Vehicle update request failed.', errorMessage);
  }

  @IsTest
  static void reportsNetworkFailureWhenRequestingToken() {
    setFakeOAuthSettings();
    Test.setMock(HttpCalloutMock.class, new NetworkFailureMock(true));

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.areEqual('OAuth token request failed.', errorMessage);
  }

  @IsTest
  static void rejectsVehicleResponseThatIsNotJson() {
    String errorMessage = getVehiclesError('not JSON');

    Assert.areEqual(
      'Vehicle response did not contain a valid JSON array.',
      errorMessage
    );
  }

  @IsTest
  static void rejectsVehicleResponseThatIsNotAnArray() {
    String errorMessage = getVehiclesError('{"RegistrationNumber":"7897NV15"}');

    Assert.areEqual(
      'Vehicle response did not contain a valid JSON array.',
      errorMessage
    );
  }

  @IsTest
  static void rejectsVehicleResponseThatIsJsonNull() {
    String errorMessage = getVehiclesError('null');

    Assert.areEqual(
      'Vehicle response did not contain a JSON array.',
      errorMessage
    );
  }

  @IsTest
  static void rejectsTokenResponseThatIsNotAnObject() {
    String errorMessage = getTokenError('[1,2]');

    Assert.areEqual(
      'OAuth token response did not have the expected JSON structure.',
      errorMessage
    );
  }

  @IsTest
  static void rejectsTokenResponseThatIsJsonNull() {
    String errorMessage = getTokenError('null');

    Assert.areEqual(
      'OAuth token response did not contain an access_token.',
      errorMessage
    );
  }

  @IsTest
  static void rejectsTokenResponseWithBlankAccessToken() {
    String errorMessage = getTokenError('{"access_token":"  "}');

    Assert.areEqual(
      'OAuth token response did not contain an access_token.',
      errorMessage
    );
  }

  private static String getVehiclesError(String vehicleResponseBody) {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, '{"access_token":"' + ACCESS_TOKEN + '"}');
    mock.addVehicleResponse(200, vehicleResponseBody);
    Test.setMock(HttpCalloutMock.class, mock);

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }
    return errorMessage;
  }

  private static String getTokenError(String tokenResponseBody) {
    setFakeOAuthSettings();
    SequentialCalloutMock mock = new SequentialCalloutMock();
    mock.addTokenResponse(200, tokenResponseBody);
    Test.setMock(HttpCalloutMock.class, mock);

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }
    return errorMessage;
  }

  private static void setFakeOAuthSettings() {
    VehicleLoanApiClient.setTestOAuthSettings(
      'password',
      'fake client+id',
      'fake client secret',
      'fake user@example.com',
      'fake password',
      'fake security token'
    );
  }

  private class UnexpectedCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      Assert.fail('Invalid input must be rejected before a callout.');
      return new HttpResponse();
    }
  }

  private class NetworkFailureMock implements HttpCalloutMock {
    private Boolean failTokenRequest;

    private NetworkFailureMock(Boolean failTokenRequest) {
      this.failTokenRequest = failTokenRequest;
    }

    public HttpResponse respond(HttpRequest request) {
      Boolean isTokenRequest =
        request.getEndpoint() == 'callout:TiVitesseBearerToken';
      if (isTokenRequest && !failTokenRequest) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody('{"access_token":"' + ACCESS_TOKEN + '"}');
        return response;
      }
      throw new CalloutException('Simulated network failure.');
    }
  }

  private class SequentialCalloutMock implements HttpCalloutMock {
    private List<CalloutStep> steps = new List<CalloutStep>();
    private Integer requestCount = 0;

    private void addTokenResponse(Integer statusCode, String responseBody) {
      CalloutStep step = new CalloutStep(
        'POST',
        'callout:TiVitesseBearerToken',
        statusCode,
        responseBody
      );
      step.expectedContentType = 'application/x-www-form-urlencoded';
      step.expectedBody = expectedTokenRequestBody();
      steps.add(step);
    }

    private void addVehicleResponse(Integer statusCode, String responseBody) {
      addVehicleResponse(
        statusCode,
        'callout:TiVitesseNamedCredential/getVehicles/',
        'GET',
        'Bearer ' + ACCESS_TOKEN,
        responseBody
      );
    }

    private void addVehicleResponse(
      Integer statusCode,
      String endpoint,
      String method,
      String expectedAuthorization,
      String responseBody
    ) {
      CalloutStep step = new CalloutStep(
        method,
        endpoint,
        statusCode,
        responseBody
      );
      step.expectedAuthorization = expectedAuthorization;
      steps.add(step);
    }

    public HttpResponse respond(HttpRequest request) {
      Assert.isTrue(requestCount < steps.size(), 'Unexpected callout.');
      CalloutStep step = steps[requestCount];
      Assert.areEqual(step.expectedEndpoint, request.getEndpoint());
      Assert.areEqual(step.expectedMethod, request.getMethod());
      if (step.expectedContentType != null) {
        Assert.areEqual(
          step.expectedContentType,
          request.getHeader('Content-Type')
        );
      }
      if (step.expectedBody != null) {
        Assert.areEqual(step.expectedBody, request.getBody());
      }
      if (step.expectedAuthorization != null) {
        Assert.areEqual(
          step.expectedAuthorization,
          request.getHeader('Authorization')
        );
      }
      requestCount++;

      HttpResponse response = new HttpResponse();
      response.setStatusCode(step.statusCode);
      response.setBody(step.responseBody);
      return response;
    }
  }

  private class CalloutStep {
    private String expectedMethod;
    private String expectedEndpoint;
    private Integer statusCode;
    private String responseBody;
    private String expectedAuthorization;
    private String expectedContentType;
    private String expectedBody;

    private CalloutStep(
      String expectedMethod,
      String expectedEndpoint,
      Integer statusCode,
      String responseBody
    ) {
      this.expectedMethod = expectedMethod;
      this.expectedEndpoint = expectedEndpoint;
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }
  }

  private static String expectedTokenRequestBody() {
    return 'grant_type=password' +
      '&client_id=' +
      EncodingUtil.urlEncode('fake client+id', 'UTF-8') +
      '&client_secret=' +
      EncodingUtil.urlEncode('fake client secret', 'UTF-8') +
      '&username=' +
      EncodingUtil.urlEncode('fake user@example.com', 'UTF-8') +
      '&password=' +
      EncodingUtil.urlEncode('fake passwordfake security token', 'UTF-8');
  }
}
