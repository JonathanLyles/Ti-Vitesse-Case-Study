@IsTest
private class VehicleLoanControllerTest {
  private static final String AGENT_USERNAME =
    'vehicle.loan.agent@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String ADMIN_WITHOUT_MANAGE_ALL_USERNAME =
    'vehicle.loan.admin.nomanageall@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String ADMIN_WITH_MANAGE_ALL_USERNAME =
    'vehicle.loan.admin.manageall@' +
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
      User adminWithoutManageAll = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
        ADMIN_WITHOUT_MANAGE_ALL_USERNAME
      );
      User adminWithManageAll = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
        ADMIN_WITH_MANAGE_ALL_USERNAME
      );
      insert new List<User>{ agent, adminWithoutManageAll, adminWithManageAll };
      Id internalAccessId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Vehicle_Loan_Internal_Access'
      ]
      .Id;
      insert new List<PermissionSetAssignment>{
        new PermissionSetAssignment(
          AssigneeId = agent.Id,
          PermissionSetId = internalAccessId
        ),
        new PermissionSetAssignment(
          AssigneeId = adminWithManageAll.Id,
          PermissionSetId = internalAccessId
        ),
        new PermissionSetAssignment(
          AssigneeId = adminWithManageAll.Id,
          PermissionSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Vehicle_Loan_Manage_All'
          ]
          .Id
        )
      };
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
    Assert.areEqual(0, context.availableVehicles.size());
  }

  @IsTest
  static void customerCanReturnLoanFromAnotherOpenClaim() {
    User customer = getCustomer();
    Case reservedOnCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(reservedOnCase, customer.ContactId);
    Case otherOpenCase = insertVehicleClaim(reservedOnCase, 'New');
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanContext context;
    VehicleLoanActionResult result;
    System.runAs(customer) {
      Test.startTest();
      context = VehicleLoanController.getLoanContext(otherOpenCase.Id);
      result = VehicleLoanController.returnVehicle(otherOpenCase.Id, loan.Id);
      Test.stopTest();
    }

    Assert.areEqual(loan.Id, context.activeLoan.Id);
    Assert.isTrue(result.remoteSucceeded);
    Assert.isTrue(result.recordSaved, result.message);
    Vehicle__c returnedLoan = [
      SELECT Case__c, Loan_Active__c, Loan_End_Date__c
      FROM Vehicle__c
      WHERE Id = :loan.Id
    ];
    Assert.isFalse(returnedLoan.Loan_Active__c);
    Assert.areEqual(Date.today(), returnedLoan.Loan_End_Date__c);
    Assert.areEqual(
      reservedOnCase.Id,
      returnedLoan.Case__c,
      'The loan keeps the Case it was reserved on'
    );
  }

  @IsTest
  static void rejectsReturnOfAnotherContactsLoanBeforeCallout() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Contact otherContact = new Contact(LastName = 'Other Loan Customer');
    insert otherContact;
    Vehicle__c otherLoan = createActiveLoan(vehicleCase, otherContact.Id);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.returnVehicle(vehicleCase.Id, otherLoan.Id);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'You are not authorized to access this active vehicle claim.',
      message
    );
    Assert.isTrue(
      [SELECT Loan_Active__c FROM Vehicle__c WHERE Id = :otherLoan.Id]
      .Loan_Active__c
    );
  }

  @IsTest
  static void customerCanReturnLoanAfterAllTheirClaimsAreClosed() {
    User customer = getCustomer();
    Case reservedOnCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(reservedOnCase, customer.ContactId);
    closeCase(reservedOnCase);
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanContext context;
    VehicleLoanActionResult result;
    System.runAs(customer) {
      Test.startTest();
      context = VehicleLoanController.getLoanContext(null);
      result = VehicleLoanController.returnVehicle(null, loan.Id);
      Test.stopTest();
    }

    Assert.areEqual(loan.Id, context.activeLoan.Id);
    Assert.isTrue(result.recordSaved, result.message);
    Assert.isFalse(
      [SELECT Loan_Active__c FROM Vehicle__c WHERE Id = :loan.Id].Loan_Active__c
    );
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
  static void customerWithOnlyClosedClaimsSeesNoVehiclesAndNoCallout() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    closeCase(vehicleCase);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    VehicleLoanContext context;
    System.runAs(customer) {
      context = VehicleLoanController.getLoanContext(vehicleCase.Id);
    }

    Assert.isFalse(context.hasOpenClaim);
    Assert.isNull(context.activeLoan);
    Assert.areEqual(0, context.availableVehicles.size());
  }

  @IsTest
  static void rejectsUserWithoutContactOwnershipOrManageAllPermissionBeforeCallout() {
    User adminWithoutManageAll = [
      SELECT Id
      FROM User
      WHERE Username = :ADMIN_WITHOUT_MANAGE_ALL_USERNAME
    ];
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(adminWithoutManageAll) {
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
  static void loadsAvailableVehiclesForAdminWithManageAllWhoDoesNotOwnContact() {
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanContext context;
    System.runAs(getAdminWithManageAll()) {
      Test.startTest();
      context = VehicleLoanController.getLoanContext(vehicleCase.Id);
      Test.stopTest();
    }

    Assert.areEqual(1, context.availableVehicles.size());
    Assert.areEqual('REG 123', context.availableVehicles[0].registrationNumber);
    Assert.isNull(context.activeLoan);
  }

  @IsTest
  static void adminWithManageAllCanReserveForContactTheyDoNotOwn() {
    Case vehicleCase = getActiveCase();
    LoanApiMock mock = new LoanApiMock(204);
    Test.setMock(HttpCalloutMock.class, mock);

    VehicleLoanActionResult result;
    System.runAs(getAdminWithManageAll()) {
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
      SELECT Case__c, Contact__c, Loan_Active__c
      FROM Vehicle__c
      WHERE Contact__c = :vehicleCase.ContactId
    ];
    Assert.areEqual(vehicleCase.Id, savedLoan.Case__c);
    Assert.isTrue(savedLoan.Loan_Active__c);
  }

  @IsTest
  static void adminWithManageAllCanReturnLoanForContactTheyDoNotOwn() {
    Case vehicleCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(vehicleCase, vehicleCase.ContactId);
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanActionResult result;
    System.runAs(getAdminWithManageAll()) {
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
  }

  @IsTest
  static void adminViewingAClosedClaimSeesTheContactsLatestOpenClaim() {
    Case activeCase = getActiveCase();
    Case closedCase = insertVehicleClaim(activeCase, 'Closed');
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanContext context;
    System.runAs(getAdminWithManageAll()) {
      Test.startTest();
      context = VehicleLoanController.getLoanContext(closedCase.Id);
      Test.stopTest();
    }

    Assert.isTrue(context.hasOpenClaim);
    Assert.areEqual(
      [SELECT CaseNumber FROM Case WHERE Id = :activeCase.Id].CaseNumber,
      context.claimCaseNumber
    );
    Assert.areEqual(1, context.availableVehicles.size());
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

  @IsTest
  static void reportsFriendlyErrorWhenAvailableVehiclesCannotBeLoaded() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new VehicleServiceDownMock());

    String message;
    System.runAs(customer) {
      Test.startTest();
      try {
        VehicleLoanController.getLoanContext(vehicleCase.Id);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      'Available vehicles could not be loaded. Please try again.',
      message
    );
  }

  @IsTest
  static void reservationFailsGracefullyWhenVehicleListIsUnavailable() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new VehicleServiceDownMock());

    String message;
    System.runAs(customer) {
      Test.startTest();
      try {
        VehicleLoanController.reserveVehicle(
          vehicleCase.Id,
          'REG 123',
          42000,
          1600
        );
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      'The vehicle reservation could not be completed. Please try again.',
      message
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Vehicle__c WHERE Contact__c = :customer.ContactId]
    );
  }

  @IsTest
  static void reservationFailsGracefullyWhenReserveCallIsRejected() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    LoanApiMock mock = new LoanApiMock(503);
    Test.setMock(HttpCalloutMock.class, mock);

    String message;
    System.runAs(customer) {
      Test.startTest();
      try {
        VehicleLoanController.reserveVehicle(
          vehicleCase.Id,
          'REG 123',
          42000,
          1600
        );
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      'The vehicle reservation could not be completed. Please try again.',
      message
    );
    Assert.areEqual(1, mock.reservationCount);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Vehicle__c WHERE Contact__c = :customer.ContactId],
      'No local loan record may exist when the remote reservation fails'
    );
  }

  @IsTest
  static void rejectsReservationWithoutASelectedVehicle() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.reserveVehicle(vehicleCase.Id, ' ', 42000, 1600);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'Select a vehicle before requesting a reservation.',
      message
    );
  }

  @IsTest
  static void rejectsReturnWithoutASelectedLoan() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.returnVehicle(vehicleCase.Id, null);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'Select an active loan before returning a vehicle.',
      message
    );
  }

  @IsTest
  static void rejectsReturnOfALoanThatIsNoLongerActive() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Vehicle__c loan = createActiveLoan(vehicleCase, customer.ContactId);
    loan.Loan_Active__c = false;
    Database.update(loan, AccessLevel.SYSTEM_MODE);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.returnVehicle(vehicleCase.Id, loan.Id);
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
  static void rejectsInternalUserWithoutACaseIdBeforeCallout() {
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(getAgent()) {
      try {
        VehicleLoanController.getLoanContext(null);
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
  static void customerLoadsVehiclesOnAPageWithoutACase() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200));

    VehicleLoanContext context;
    System.runAs(customer) {
      Test.startTest();
      context = VehicleLoanController.getLoanContext(null);
      Test.stopTest();
    }

    Assert.isTrue(context.hasOpenClaim);
    Assert.areEqual(
      [SELECT CaseNumber FROM Case WHERE Id = :vehicleCase.Id].CaseNumber,
      context.claimCaseNumber
    );
    Assert.areEqual(1, context.availableVehicles.size());
  }

  @IsTest
  static void reservationIsLinkedToTheMostRecentOpenClaim() {
    User customer = getCustomer();
    Case olderCase = getActiveCase();
    Case newerCase = insertVehicleClaim(olderCase, 'New');
    Test.setCreatedDate(olderCase.Id, Datetime.now().addDays(-2));
    Test.setCreatedDate(newerCase.Id, Datetime.now().addDays(-1));
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(204));

    VehicleLoanActionResult result;
    System.runAs(customer) {
      Test.startTest();
      // Started from the older claim's page: the loan still goes to the newest
      result = VehicleLoanController.reserveVehicle(
        olderCase.Id,
        'REG 123',
        42000,
        1600
      );
      Test.stopTest();
    }

    Assert.isTrue(result.recordSaved, result.message);
    Assert.areEqual(
      newerCase.Id,
      [SELECT Case__c FROM Vehicle__c WHERE Contact__c = :customer.ContactId]
      .Case__c
    );
  }

  @IsTest
  static void rejectsReservationWithoutAnOpenClaimBeforeCallout() {
    User customer = getCustomer();
    closeCase(getActiveCase());
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.reserveVehicle(null, 'REG 123', 42000, 1600);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'You need an open vehicle claim to loan a vehicle.',
      message
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Vehicle__c WHERE Contact__c = :customer.ContactId]
    );
  }

  @IsTest
  static void rejectsContextWhenContactHasMoreThanOneActiveLoan() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Vehicle__c firstLoan = createActiveLoan(vehicleCase, customer.ContactId);
    Vehicle__c secondLoan = firstLoan.clone(false, true, false, false);
    secondLoan.Registration_number__c = 'REG 456';
    Database.insert(secondLoan, AccessLevel.SYSTEM_MODE);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());

    String message;
    System.runAs(customer) {
      try {
        VehicleLoanController.getLoanContext(vehicleCase.Id);
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
    }

    Assert.areEqual(
      'More than one active loan exists for this Contact. Contact support.',
      message
    );
  }

  @IsTest
  static void reservationReportsIncompleteVehicleDetailsFromTheService() {
    User customer = getCustomer();
    Case vehicleCase = getActiveCase();
    Test.setMock(HttpCalloutMock.class, new LoanApiMock(200, ''));

    String message;
    System.runAs(customer) {
      Test.startTest();
      try {
        VehicleLoanController.reserveVehicle(
          vehicleCase.Id,
          'REG 123',
          42000,
          1600
        );
      } catch (AuraHandledException error) {
        message = error.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      'The selected vehicle details are incomplete. Please contact support.',
      message
    );
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

  private static User getAdminWithManageAll() {
    return [
      SELECT Id
      FROM User
      WHERE Username = :ADMIN_WITH_MANAGE_ALL_USERNAME
    ];
  }

  private static void closeCase(Case vehicleCase) {
    update new Case(Id = vehicleCase.Id, Status = 'Closed');
  }

  // Another Vehicle Claims Case for the same Contact and Account as the given one
  private static Case insertVehicleClaim(Case sameContactCase, String status) {
    Case claim = new Case(
      AccountId = [
        SELECT AccountId
        FROM Case
        WHERE Id = :sameContactCase.Id
      ]
      .AccountId,
      ContactId = sameContactCase.ContactId,
      RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get('Vehicle_Claims')
        .getRecordTypeId(),
      Status = status,
      Origin = 'Web',
      Subject = 'Second vehicle claim'
    );
    insert claim;
    return claim;
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

  private class VehicleServiceDownMock implements HttpCalloutMock {
    private VehicleServiceDownMock() {
      VehicleLoanApiClient.setTestOAuthSettings(
        'password',
        'test-client-id',
        'test-client-secret',
        'test-user',
        'test-password',
        'test-token'
      );
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      if (request.getEndpoint() == 'callout:TiVitesseBearerToken') {
        response.setStatusCode(200);
        response.setBody('{"access_token":"test-access-token"}');
      } else {
        response.setStatusCode(500);
        response.setBody('service unavailable');
      }
      return response;
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
      VehicleLoanApiClient.setTestOAuthSettings(
        'password',
        'test-client-id',
        'test-client-secret',
        'test-user',
        'test-password',
        'test-token'
      );
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      if (request.getEndpoint() == 'callout:TiVitesseBearerToken') {
        response.setStatusCode(200);
        response.setBody('{"access_token":"test-access-token"}');
        return response;
      }
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
