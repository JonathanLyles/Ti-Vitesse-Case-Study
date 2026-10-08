@IsTest
private class VehicleLoanApiClientTest {
  @IsTest
  static void parsesVehiclesFromNamedCredential() {
    Test.setMock(
      HttpCalloutMock.class,
      new VehicleCalloutMock(
        'GET',
        'callout:TiVitesseNamedCredential/getVehicles/',
        200,
        '[{"RegistrationNumber":"7897NV15","Make":"Nissan","Model":"Hardbody x38","YearOfVehicle":"2015"}]'
      )
    );

    Test.startTest();
    VehicleLoanApiResponse response = new VehicleLoanApiClient().getVehicles();
    Test.stopTest();

    Assert.areEqual(1, response.vehicles.size());
    Assert.areEqual('7897NV15', response.vehicles[0].RegistrationNumber);
    Assert.areEqual('Nissan', response.vehicles[0].Make);
    Assert.areEqual('Hardbody x38', response.vehicles[0].Model);
    Assert.areEqual('2015', response.vehicles[0].YearOfVehicle);
  }

  @IsTest
  static void rejectsVehicleListWhenServiceReturnsFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new VehicleCalloutMock(
        'GET',
        'callout:TiVitesseNamedCredential/getVehicles/',
        503,
        '{"error":"service unavailable"}'
      )
    );

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles();
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.isTrue(
      errorMessage != null && errorMessage.contains('HTTP 503'),
      'A non-2xx vehicle response should fail'
    );
  }

  @IsTest
  static void postsEncodedRegistrationAndAcceptsAny2xxStatus() {
    Test.setMock(
      HttpCalloutMock.class,
      new VehicleCalloutMock(
        'POST',
        'callout:TiVitesseNamedCredential/updateVehicle/REG%20123',
        204,
        'not JSON'
      )
    );

    Test.startTest();
    new VehicleLoanApiClient().updateVehicle('REG 123');
    Test.stopTest();
  }

  @IsTest
  static void rejectsReservationWhenServiceReturnsFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new VehicleCalloutMock(
        'POST',
        'callout:TiVitesseNamedCredential/updateVehicle/7897NV15',
        503,
        '{"error":"service unavailable"}'
      )
    );

    String errorMessage;
    try {
      new VehicleLoanApiClient().updateVehicle('7897NV15');
    } catch (CalloutException error) {
      errorMessage = error.getMessage();
    }

    Assert.isTrue(
      errorMessage != null && errorMessage.contains('HTTP 503'),
      'A non-2xx reservation response should fail'
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

  private class UnexpectedCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      Assert.fail('Invalid input must be rejected before a callout.');
      return new HttpResponse();
    }
  }

  private class VehicleCalloutMock implements HttpCalloutMock {
    private String expectedMethod;
    private String expectedEndpoint;
    private Integer statusCode;
    private String responseBody;

    private VehicleCalloutMock(
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

    public HttpResponse respond(HttpRequest request) {
      Assert.areEqual(expectedEndpoint, request.getEndpoint());
      Assert.areEqual(expectedMethod, request.getMethod());
      if (expectedMethod == 'POST') {
        Assert.areEqual('', request.getBody());
      }

      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      return response;
    }
  }
}
