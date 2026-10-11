@IsTest
private class VehicleLoanControllerTest {
  private static final String AGENT_USERNAME =
    'vehicle.loan.agent@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String ADMIN_USERNAME =
    'vehicle.loan.admin@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String CUSTOMER_USERNAME =
    'vehicle.loan.customer@' +
    UserInfo.getOrganizationId() +
    '.test';

  @TestSetup
  static void setup() {
    User agent;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      agent = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'Custom - TVI Agents'].Id,
        AGENT_USERNAME
      );
      agent.UserRoleId = [
        SELECT Id
        FROM UserRole
        WHERE DeveloperName = 'Agent_West'
      ]
      .Id;
      agent.UserPermissionsInteractionUser = true;
      User administrator = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
        ADMIN_USERNAME
      );
      insert new List<User>{ agent, administrator };
    }

    Contact contact;
    Account account;
    System.runAs(agent) {
      account = new Account(Name = 'Vehicle Loan Test Customer');
      insert account;
      contact = new Contact(
        LastName = 'Vehicle Loan Customer',
        AccountId = account.Id
      );
      insert contact;
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new Case(
        AccountId = account.Id,
        ContactId = contact.Id,
        RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
          .get('Vehicle_Claims')
          .getRecordTypeId(),
        Status = 'New',
        Origin = 'Web',
        Subject = 'Vehicle loan test'
      );
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      User customer = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'Customer Community Clone'].Id,
        CUSTOMER_USERNAME
      );
      customer.ContactId = contact.Id;
      insert customer;

      insert new PermissionSetAssignment(
        AssigneeId = customer.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'Vehicle_Claim_Portal_Access'
        ]
        .Id
      );
    }
  }

  @IsTest
  static void loadsAvailableVehiclesForContactOwnerAgent() {
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanContext context;
    System.runAs(getAgent()) {
      Test.startTest();
      context = VehicleLoanController.getLoanContext(vehicleCase.Id);
      Test.stopTest();
    }

    Assert.areEqual(1, context.availableVehicles.size());
    Assert.areEqual('REG 123', context.availableVehicles[0].registrationNumber);
    Assert.areEqual('Volkswagen', context.availableVehicles[0].make);
    Assert.areEqual('Golf', context.availableVehicles[0].model);
    Assert.areEqual('2024', context.availableVehicles[0].yearOfVehicle);
    Assert.isNull(context.activeLoan);
  }

  @IsTest
  static void customerViewsExistingLoanWithoutLoadingAvailability() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(vehicleCase, customer.ContactId);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    VehicleLoanContext context;
    System.runAs(customer) {
      context = VehicleLoanController.getLoanContext(vehicleCase.Id);
    }

    Assert.areEqual(loan.Id, context.activeLoan.Id);
    Assert.isTrue(context.canReturnActiveLoan);
    Assert.areEqual(0, context.availableVehicles.size());
  }

  @IsTest
  static void customerCanReserveAndRecordIsLinkedToCaseAndContact() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    LoanApiMock mock = new LoanApiMock(204);
    Test.setMock(HttpCalloutMock.class, mock);

    VehicleLoanActionResult result;
    System.runAs(customer) {
      Test.startTest();
      result = VehicleLoanController.reserveVehicle(
        vehicleCase.Id,
        'REG 123',
        42000,
        1600
      );
      Test.stopTest();
    }

    Assert.isTrue(result.remoteSucceeded);
    Assert.isTrue(result.recordSaved, result.message);
    Assert.areEqual(1, mock.reservationCount);

    Vehicle__c savedLoan = [
      SELECT
        RecordType.DeveloperName,
        Case__c,
        Contact__c,
        Registration_number__c,
        Make__c,
        Model__c,
        Year_of_Vehicle__c,
        Mileage__c,
        Engine_Capacity__c,
        Loan_Active__c
      FROM Vehicle__c
      WHERE Contact__c = :customer.ContactId
    ];
    Assert.areEqual('Loan_Vehicle', savedLoan.RecordType.DeveloperName);
    Assert.areEqual(vehicleCase.Id, savedLoan.Case__c);
    Assert.areEqual(customer.ContactId, savedLoan.Contact__c);
    Assert.areEqual('REG 123', savedLoan.Registration_number__c);
    Assert.areEqual('Volkswagen', savedLoan.Make__c);
    Assert.areEqual('Golf', savedLoan.Model__c);
    Assert.areEqual('2024', savedLoan.Year_of_Vehicle__c);
    Assert.areEqual(42000, savedLoan.Mileage__c);
    Assert.areEqual(1600, savedLoan.Engine_Capacity__c);
    Assert.isTrue(savedLoan.Loan_Active__c);
  }

  @IsTest
  static void customerCanReturnLoanAndHistoryIsPreserved() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(vehicleCase, customer.ContactId);
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanActionResult result;
    System.runAs(customer) {
      Test.startTest();
      result = VehicleLoanController.returnVehicle(vehicleCase.Id, loan.Id);
      Test.stopTest();
    }

    Assert.isTrue(result.remoteSucceeded);
    Assert.isTrue(result.recordSaved);
    Vehicle__c returnedLoan = [
      SELECT Loan_Active__c, Loan_End_Date__c
      FROM Vehicle__c
      WHERE Id = :loan.Id
    ];
    Assert.isFalse(returnedLoan.Loan_Active__c);
    Assert.areEqual(Date.today(), returnedLoan.Loan_End_Date__c);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Vehicle__c WHERE Id = :loan.Id],
      'The returned record remains available for history'
    );
  }

  @IsTest
  static void returnCalloutFailureLeavesLoanUnchanged() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(vehicleCase, customer.ContactId);
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(503));

    String message;
    System.runAs(customer) {
      Test.startTest();
      try {
        VehicleLoanController.returnVehicle(vehicleCase.Id, loan.Id);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      'The vehicle could not be returned. Please try again.',
      message
    );
    Vehicle__c unchangedLoan = [
      SELECT Loan_Active__c, Loan_End_Date__c
      FROM Vehicle__c
      WHERE Id = :loan.Id
    ];
    Assert.isTrue(unchangedLoan.Loan_Active__c);
    Assert.isNull(unchangedLoan.Loan_End_Date__c);
  }

  @IsTest
  static void rejectsCustomerForClosedCaseBeforeCallout() {
    User customer = getCustomer();
    Case activeCase = getActiveCase();
    Case closedCase = activeCase.clone(false, true, false, false);
    closedCase.Status = 'Closed';
    insert closedCase;
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.getLoanContext(closedCase.Id);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'You are not authorized to access this active vehicle claim.',
      message
    );
  }

  @IsTest
  static void rejectsUserWhoDoesNotOwnCaseContactBeforeCallout() {
    User administrator = [
      SELECT Id
      FROM User
      WHERE Username = :ADMIN_USERNAME
    ];
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(administrator) {
      try {
        VehicleLoanController.getLoanContext(vehicleCase.Id);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'You are not authorized to access this active vehicle claim.',
      message
    );
  }

  @IsTest
  static void rejectsReservationWhenContactAlreadyHasActiveLoan() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    createActiveLoan(vehicleCase, customer.ContactId);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.reserveVehicle(
          vehicleCase.Id,
          'REG 456',
          42000,
          1600
        );
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'This Contact already has an active vehicle loan.',
      message
    );
  }

  @IsTest
  static void rejectsReservationWhenRequiredVehicleDetailsAreInvalid() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.reserveVehicle(
          vehicleCase.Id,
          'REG 123',
          null,
          1600
        );
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual('Enter a valid mileage and engine capacity.', message);
  }

  @IsTest
  static void rejectsRegistrationNotReturnedByVehicleService() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    LoanApiMock mock = new LoanApiMock(200);
    Test.setMock(HttpCalloutMock.class, mock);

    String message;
    System.runAs(customer) {
      Test.startTest();
      try {
        VehicleLoanController.reserveVehicle(
          vehicleCase.Id,
          'TAMPERED',
          42000,
          1600
        );
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      'That vehicle is no longer available. Refresh the list and try again.',
      message
    );
    Assert.areEqual(0, mock.reservationCount);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Vehicle__c WHERE Contact__c = :customer.ContactId]
    );
  }

  @IsTest
  static void reportsRemoteReservationWhenLocalInsertFails() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Integer maximumModelLength = Vehicle__c.Model__c.getDescribe().getLength();
    String tooLongModel = '';
    for (Integer i = 0; i <= maximumModelLength; i++) {
      tooLongModel += 'x';
    }
    LoanApiMock mock = new LoanApiMock(200, tooLongModel);
    Test.setMock(HttpCalloutMock.class, mock);

    VehicleLoanActionResult result;
    System.runAs(customer) {
      Test.startTest();
      result = VehicleLoanController.reserveVehicle(
        vehicleCase.Id,
        'REG 123',
        42000,
        1600
      );
      Test.stopTest();
    }

    Assert.isTrue(result.remoteSucceeded);
    Assert.isFalse(result.recordSaved);
    Assert.isTrue(result.message.contains('remote reservation succeeded'));
    Assert.areEqual(1, mock.reservationCount);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Vehicle__c WHERE Contact__c = :customer.ContactId]
    );
  }

  private static Case getActiveCase() {
    return [
      SELECT Id, ContactId
      FROM Case
      WHERE Subject = 'Vehicle loan test'
      LIMIT 1
    ];
  }

  private static User getCustomer() {
    return [
      SELECT Id, ContactId
      FROM User
      WHERE Username = :CUSTOMER_USERNAME
    ];
  }

  private static User getAgent() {
    return [
      SELECT Id
      FROM User
      WHERE Username = :AGENT_USERNAME
    ];
  }

  private static Vehicle__c createActiveLoan(Case vehicleCase, Id contactId) {
    Vehicle__c loan = new Vehicle__c(
      RecordTypeId = Schema.SObjectType.Vehicle__c.getRecordTypeInfosByDeveloperName()
        .get('Loan_Vehicle')
        .getRecordTypeId(),
      Case__c = vehicleCase.Id,
      Contact__c = contactId,
      Registration_number__c = 'REG 123',
      Make__c = 'Volkswagen',
      Model__c = 'Golf',
      Year_of_Vehicle__c = '2024',
      Mileage__c = 42000,
      Engine_Capacity__c = 1600,
      Loan_Active__c = true
    );
    Database.insert(loan, AccessLevel.SYSTEM_MODE);
    return loan;
  }

  private static User buildUser(Id profileId, String username) {
    return new User(
      ProfileId = profileId,
      Username = username,
      Email = 'vehicle.loan.test@example.com',
      LastName = 'Vehicle Loan Test',
      Alias = 'vloantst',
      TimeZoneSidKey = UserInfo.getTimeZone().getID(),
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }

  private class UnexpectedCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      Assert.fail('The unauthorized operation must not make a callout.');
      return new HttpResponse();
    }
  }

  private class LoanApiMock implements HttpCalloutMock {
    private Integer reservationStatus;
    private Integer reservationCount = 0;
    private String model;

    private LoanApiMock(Integer reservationStatus) {
      this(reservationStatus, 'Golf');
    }

    private LoanApiMock(Integer reservationStatus, String model) {
      this.reservationStatus = reservationStatus;
      this.model = model;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      if (request.getMethod() == 'GET') {
        Assert.areEqual(
          'callout:TiVitesseNamedCredential/getVehicles/',
          request.getEndpoint()
        );
        response.setStatusCode(200);
        response.setBody(
          JSON.serialize(
            new List<Object>{
              new Map<String, String>{
                'RegistrationNumber' => 'REG 123',
                'Make' => 'Volkswagen',
                'Model' => model,
                'YearOfVehicle' => '2024'
              }
            }
          )
        );
        return response;
      }

      Assert.areEqual('POST', request.getMethod());
      Assert.areEqual(
        'callout:TiVitesseNamedCredential/updateVehicle/REG%20123',
        request.getEndpoint()
      );
      Assert.areEqual('', request.getBody());
      reservationCount++;
      response.setStatusCode(reservationStatus);
      response.setBody('not parsed');
      return response;
    }
  }
}
