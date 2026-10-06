@IsTest
private class VehicleLoanApiClientTest {
  @IsTest
  static void returnsAccessTokenAndEncodesFormValues() {
    Test.setMock(
      HttpCalloutMock.class,
      new OAuthCalloutMock(
        200,
        '{"access_token":"test-access-token","token_type":"Bearer"}',
        'grant_type=password&client_id=client%2Bid%261&client_secret=sec%26ret&username=api%2Btest%40example.com&password=pw%26%3Dtok%2B'
      )
    );

    Test.startTest();
    String accessToken = new VehicleLoanApiClient()
      .getAccessToken(
        'password',
        'client+id&1',
        'sec&ret',
        'api+test@example.com',
        'pw&=',
        'tok+'
      );
    Test.stopTest();

    Assert.areEqual(
      'test-access-token',
      accessToken,
      'The access token should be returned from a successful response'
    );
  }

  @IsTest
  static void throwsUsefulErrorForOAuthFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new OAuthCalloutMock(
        400,
        '{"error":"invalid_grant","error_description":"authentication failed"}',
        null
      )
    );

    String errorMessage;
    Test.startTest();
    try {
      new VehicleLoanApiClient()
        .getAccessToken(
          'password',
          'client-id',
          'client-secret',
          'api@example.com',
          'password',
          'token'
        );
    } catch (CalloutException e) {
      errorMessage = e.getMessage();
    }
    Test.stopTest();

    Assert.isTrue(
      errorMessage != null &&
        errorMessage.contains('HTTP 400') &&
        errorMessage.contains('invalid_grant'),
      'The OAuth error and status should be surfaced'
    );
  }

  @IsTest
  static void rejectsSuccessfulResponseWithoutAccessToken() {
    Test.setMock(
      HttpCalloutMock.class,
      new OAuthCalloutMock(200, '{"token_type":"Bearer"}', null)
    );

    String errorMessage;
    try {
      new VehicleLoanApiClient()
        .getAccessToken(
          'password',
          'client-id',
          'client-secret',
          'api@example.com',
          'password',
          ''
        );
    } catch (CalloutException e) {
      errorMessage = e.getMessage();
    }

    Assert.areEqual(
      'OAuth token response did not contain an access_token.',
      errorMessage,
      'A response without a token should fail explicitly'
    );
  }

  @IsTest
  static void parsesVehicleResponseAndMapsSavableRecordFields() {
    Test.setMock(
      HttpCalloutMock.class,
      new VehicleCalloutMock(
        200,
        '[{"RegistrationNumber":"7897NV15","Make":"Nissan","Model":"Hardbody x38","YearOfVehicle":"2015"},{"RegistrationNumber":"11000DC17","Make":"Renault","Model":"kwid climber","YearOfVehicle":"2017"}]'
      )
    );

    Test.startTest();
    VehicleLoanApiResponse response = new VehicleLoanApiClient()
      .getVehicles('test-access-token');
    Test.stopTest();

    Assert.areEqual(2, response.vehicles.size(), 'Both vehicles should parse');
    VehicleLoanApiResponse.Vehicle returnedVehicle = response.vehicles[0];
    Assert.areEqual('7897NV15', returnedVehicle.RegistrationNumber);
    Assert.areEqual('Nissan', returnedVehicle.Make);
    Assert.areEqual('Hardbody x38', returnedVehicle.Model);
    Assert.areEqual('2015', returnedVehicle.YearOfVehicle);

    Vehicle__c vehicle = returnedVehicle.toVehicleRecord();
    Assert.areEqual('7897NV15', vehicle.Registration_number__c);
    Assert.areEqual('Nissan', vehicle.Make__c);
    Assert.areEqual('Hardbody x38', vehicle.Model__c);
    Assert.areEqual('2015', vehicle.Year_of_Vehicle__c);

    Account account = new Account(Name = 'API Vehicle Test Customer');
    insert account;
    Contact contact = new Contact(
      LastName = 'API Vehicle Test',
      AccountId = account.Id
    );
    insert contact;
    Case vehicleCase = new Case(
      AccountId = account.Id,
      ContactId = contact.Id,
      Status = 'New',
      Origin = 'Web',
      Subject = 'API vehicle test'
    );
    insert vehicleCase;

    vehicle.Case__c = vehicleCase.Id;
    vehicle.Contact__c = contact.Id;
    vehicle.Mileage__c = 10000;
    vehicle.Engine_Capacity__c = 1600;
    vehicle.RecordTypeId = Schema.SObjectType.Vehicle__c.getRecordTypeInfosByDeveloperName()
      .get('Loan_Vehicle')
      .getRecordTypeId();
    insert vehicle;

    Vehicle__c savedVehicle = [
      SELECT
        Registration_number__c,
        Make__c,
        Model__c,
        Year_of_Vehicle__c,
        Case__c,
        Contact__c,
        Mileage__c,
        Engine_Capacity__c
      FROM Vehicle__c
      WHERE Id = :vehicle.Id
    ];
    Assert.areEqual('7897NV15', savedVehicle.Registration_number__c);
    Assert.areEqual('Nissan', savedVehicle.Make__c);
    Assert.areEqual('Hardbody x38', savedVehicle.Model__c);
    Assert.areEqual('2015', savedVehicle.Year_of_Vehicle__c);
    Assert.areEqual(vehicleCase.Id, savedVehicle.Case__c);
    Assert.areEqual(contact.Id, savedVehicle.Contact__c);
    Assert.areEqual(10000, savedVehicle.Mileage__c);
    Assert.areEqual(1600, savedVehicle.Engine_Capacity__c);
  }

  @IsTest
  static void throwsUsefulErrorForVehicleCalloutFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new VehicleCalloutMock(503, '{"error":"service unavailable"}')
    );

    String errorMessage;
    try {
      new VehicleLoanApiClient().getVehicles('test-access-token');
    } catch (CalloutException e) {
      errorMessage = e.getMessage();
    }

    Assert.isTrue(
      errorMessage != null &&
        errorMessage.contains('HTTP 503') &&
        errorMessage.contains('service unavailable'),
      'The vehicle API failure and status should be surfaced'
    );
  }

  private class OAuthCalloutMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;
    private String expectedRequestBody;

    private OAuthCalloutMock(
      Integer statusCode,
      String responseBody,
      String expectedRequestBody
    ) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
      this.expectedRequestBody = expectedRequestBody;
    }

    public HttpResponse respond(HttpRequest request) {
      Assert.areEqual(
        'callout:TiVitesseBearerToken',
        request.getEndpoint(),
        'The configured token Named Credential should be used'
      );
      Assert.areEqual('POST', request.getMethod());
      Assert.areEqual(
        'application/x-www-form-urlencoded',
        request.getHeader('Content-Type')
      );
      if (expectedRequestBody != null) {
        Assert.areEqual(expectedRequestBody, request.getBody());
      }

      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      return response;
    }
  }

  private class VehicleCalloutMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    private VehicleCalloutMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      Assert.areEqual(
        'callout:TiVitesseNamedCredential/getVehicles/',
        request.getEndpoint(),
        'The vehicle API Named Credential should be used'
      );
      Assert.areEqual('GET', request.getMethod());
      Assert.areEqual(
        'Bearer test-access-token',
        request.getHeader('Authorization')
      );

      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      return response;
    }
  }
}
