/**
 * @description Unit tests for VehicleClaimController. Claims are submitted as a
 *              Customer Portal User (Customer Community Clone profile) with the
 *              Community Site and Vehicle Claim Portal Access permission sets, as
 *              on the Experience Cloud site.
 */
@IsTest
private class VehicleClaimControllerTest {
  private static final String AGENT_PROFILE = 'Custom - TVI Agents';
  private static final String AGENT_ROLE = 'Agent_West';
  private static final String CUSTOMER_PORTAL_PROFILE = 'Customer Community Clone';
  private static final Set<String> CUSTOMER_PORTAL_PERMISSION_SETS = new Set<String>{
    'Community_Site_Permission_Set',
    'Vehicle_Claim_Portal_Access'
  };
  private static final String AGENT_USERNAME =
    'claims.agent@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String ADMIN_USERNAME =
    'claims.admin@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String CUSTOMER_PORTAL_USERNAME =
    'claims.customer.portal.user@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String UNASSIGNED_CUSTOMER_USERNAME =
    'claims.unassigned.customer@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String SUBJECT = 'Rear-ended at traffic lights';

  /**
   * @description Creates a customer: an agent who owns the Account and Contact (TVI
   *              Agents profile, Agent - West role, Flow User), and a Customer Portal
   *              User for the Contact with the portal permission sets. Also creates a
   *              System Administrator for the internal-user tests. Setup and
   *              non-setup records are inserted in separate runAs blocks to avoid
   *              mixed DML errors.
   */
  @TestSetup
  static void setup() {
    User owner;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      owner = buildUser(
        [SELECT Id FROM Profile WHERE Name = :AGENT_PROFILE].Id,
        AGENT_USERNAME
      );
      owner.UserRoleId = [
        SELECT Id
        FROM UserRole
        WHERE DeveloperName = :AGENT_ROLE
      ]
      .Id;
      owner.UserPermissionsInteractionUser = true;
      User admin = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
        ADMIN_USERNAME
      );
      insert new List<User>{ owner, admin };
    }

    Contact customer;
    System.runAs(owner) {
      Account account = new Account(Name = 'Claims Test Customer');
      insert account;
      customer = new Contact(LastName = 'Customer', AccountId = account.Id);
      insert customer;
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      User customerPortalUser = buildUser(
        [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PORTAL_PROFILE].Id,
        CUSTOMER_PORTAL_USERNAME
      );
      customerPortalUser.ContactId = customer.Id;
      insert customerPortalUser;

      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
      for (PermissionSet permissionSet : [
        SELECT Id
        FROM PermissionSet
        WHERE Name IN :CUSTOMER_PORTAL_PERMISSION_SETS
      ]) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = customerPortalUser.Id,
            PermissionSetId = permissionSet.Id
          )
        );
      }
      insert assignments;
    }
  }

  /**
   * @description Verifies a claim creates a New Vehicle Claims Case for the customer's
   *              Contact and Account, assigned to the customer's agent (the Account
   *              owner), and a Vehicle linked to that Case and Contact.
   */
  @IsTest
  static void createsCaseAndVehicleForCustomer() {
    User customerPortalUser = getCustomerPortalUser();
    Datetime incidentDate = System.now().addDays(-1);

    Id caseId;
    System.runAs(customerPortalUser) {
      Test.startTest();
      caseId = VehicleClaimController.createClaim(
        buildClaim(incidentDate),
        buildVehicle('Golf')
      );
      Test.stopTest();
    }

    Case newCase = [
      SELECT
        Status,
        RecordType.DeveloperName,
        ContactId,
        AccountId,
        OwnerId,
        Date_and_Time_of_Incident__c,
        Subject,
        Damage_Detail__c,
        Description
      FROM Case
      WHERE Id = :caseId
    ];
    Assert.areEqual('New', newCase.Status, 'Claim should be created as New');
    Assert.areEqual(
      'Vehicle_Claims',
      newCase.RecordType.DeveloperName,
      'Claim should use the Vehicle Claims record type'
    );
    Assert.areEqual(
      customerPortalUser.ContactId,
      newCase.ContactId,
      'Claim should belong to the customer\'s Contact'
    );
    Assert.areEqual(
      customerPortalUser.Contact.AccountId,
      newCase.AccountId,
      'Claim should belong to the customer\'s Account'
    );
    Assert.areEqual(
      [SELECT Id FROM User WHERE Username = :AGENT_USERNAME].Id,
      newCase.OwnerId,
      'Claim should be assigned to the customer\'s agent'
    );
    Assert.areEqual(
      incidentDate,
      newCase.Date_and_Time_of_Incident__c,
      'Incident date should be saved'
    );
    Assert.areEqual(SUBJECT, newCase.Subject, 'Subject should be saved');
    Assert.areEqual(
      'Rear bumper dented',
      newCase.Damage_Detail__c,
      'Damage detail should be saved'
    );
    Assert.areEqual(
      'Hit from behind while stationary',
      newCase.Description,
      'Description should be saved'
    );

    Vehicle__c vehicle = [
      SELECT
        RecordType.DeveloperName,
        Case__c,
        Contact__c,
        Make__c,
        Model__c,
        Registration_number__c,
        Mileage__c,
        Engine_Capacity__c
      FROM Vehicle__c
      WHERE Case__c = :caseId
    ];
    Assert.areEqual(
      customerPortalUser.ContactId,
      vehicle.Contact__c,
      'Vehicle should belong to the customer\'s Contact'
    );
    Assert.areEqual(
      'Damaged_Vehicle',
      vehicle.RecordType.DeveloperName,
      'Claim vehicle should use the Damaged Vehicle record type'
    );
    Assert.areEqual('Volkswagen', vehicle.Make__c, 'Make should be saved');
    Assert.areEqual('Golf', vehicle.Model__c, 'Model should be saved');
    Assert.areEqual(
      'AB12 CDE',
      vehicle.Registration_number__c,
      'Registration number should be saved'
    );
    Assert.areEqual(42000, vehicle.Mileage__c, 'Mileage should be saved');
    Assert.areEqual(
      1600,
      vehicle.Engine_Capacity__c,
      'Engine capacity should be saved'
    );
  }

  /**
   * @description Verifies an incident date in the future is rejected and nothing is saved.
   */
  @IsTest
  static void rejectsFutureIncidentDate() {
    String message;
    System.runAs(getCustomerPortalUser()) {
      try {
        VehicleClaimController.createClaim(
          buildClaim(System.now().addDays(1)),
          buildVehicle('Golf')
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }

    Assert.areEqual(
      'The date and time of the incident cannot be in the future.',
      message,
      'Future dates should be rejected'
    );
    assertNothingSaved();
  }

  /**
   * @description Verifies an incident date only a minute in the future is still rejected.
   */
  @IsTest
  static void rejectsIncidentDateJustInFuture() {
    String message;
    System.runAs(getCustomerPortalUser()) {
      try {
        VehicleClaimController.createClaim(
          buildClaim(System.now().addMinutes(1)),
          buildVehicle('Golf')
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }

    Assert.areEqual(
      'The date and time of the incident cannot be in the future.',
      message,
      'A date just in the future should be rejected'
    );
    assertNothingSaved();
  }

  /**
   * @description Verifies an incident date only a minute in the past is accepted.
   */
  @IsTest
  static void acceptsIncidentDateJustInPast() {
    Id caseId;
    System.runAs(getCustomerPortalUser()) {
      caseId = VehicleClaimController.createClaim(
        buildClaim(System.now().addMinutes(-1)),
        buildVehicle('Golf')
      );
    }

    Assert.isNotNull(caseId, 'A date just in the past should be accepted');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Case WHERE Id = :caseId],
      'The Case should be saved'
    );
  }

  /**
   * @description Verifies fields the form doesn't send (Status, owner, another customer's
   *              Contact) are ignored, so a caller can't file a claim against someone else
   *              or change how it is assigned.
   */
  @IsTest
  static void ignoresFieldsNotOnTheForm() {
    User customerPortalUser = getCustomerPortalUser();
    Account otherAccount = new Account(Name = 'Other Customer Account');
    insert otherAccount;
    Contact otherContact = new Contact(
      LastName = 'Other Customer',
      AccountId = otherAccount.Id
    );
    insert otherContact;

    Case claim = buildClaim(System.now().addDays(-1));
    claim.Status = 'Closed';
    claim.ContactId = otherContact.Id;
    claim.OwnerId = customerPortalUser.Id;
    Vehicle__c vehicle = buildVehicle('Golf');
    vehicle.Contact__c = otherContact.Id;

    Id caseId;
    System.runAs(customerPortalUser) {
      caseId = VehicleClaimController.createClaim(claim, vehicle);
    }

    Case newCase = [
      SELECT Status, ContactId, AccountId, OwnerId
      FROM Case
      WHERE Id = :caseId
    ];
    Assert.areEqual(
      'New',
      newCase.Status,
      'Status from the caller should be ignored'
    );
    Assert.areEqual(
      customerPortalUser.ContactId,
      newCase.ContactId,
      'Contact from the caller should be ignored'
    );
    Assert.areEqual(
      customerPortalUser.Contact.AccountId,
      newCase.AccountId,
      'Claim should stay on the customer\'s Account'
    );
    Assert.areEqual(
      getUser(AGENT_USERNAME).Id,
      newCase.OwnerId,
      'Owner from the caller should be ignored'
    );
    Assert.areEqual(
      customerPortalUser.ContactId,
      [SELECT Contact__c FROM Vehicle__c WHERE Case__c = :caseId].Contact__c,
      'Vehicle Contact from the caller should be ignored'
    );
  }

  /**
   * @description Verifies a customer without the portal permission sets cannot submit a
   *              claim, and nothing is saved.
   */
  @IsTest
  static void rejectsCustomerWithoutPermissionSets() {
    Contact unassignedCustomer = new Contact(
      LastName = 'Unassigned Customer',
      AccountId = getCustomerPortalUser().Contact.AccountId
    );
    System.runAs(getUser(AGENT_USERNAME)) {
      insert unassignedCustomer;
    }

    User unassignedUser;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      unassignedUser = buildUser(
        [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PORTAL_PROFILE].Id,
        UNASSIGNED_CUSTOMER_USERNAME
      );
      unassignedUser.ContactId = unassignedCustomer.Id;
      insert unassignedUser;
    }

    String message;
    System.runAs(unassignedUser) {
      try {
        VehicleClaimController.createClaim(
          buildClaim(System.now().addDays(-1)),
          buildVehicle('Golf')
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }

    Assert.isNotNull(
      message,
      'A customer without the permission sets should be rejected'
    );
    Assert.isTrue(
      message.startsWith('Your claim could not be submitted'),
      'Error should explain the claim was not submitted: ' + message
    );
    assertNothingSaved();
  }

  /**
   * @description Verifies that if the Vehicle cannot be saved (Model is required), the
   *              Case is rolled back too.
   */
  @IsTest
  static void rollsBackCaseWhenVehicleFails() {
    String message;
    System.runAs(getCustomerPortalUser()) {
      try {
        VehicleClaimController.createClaim(
          buildClaim(System.now().addDays(-1)),
          buildVehicle(null)
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }

    Assert.isNotNull(message, 'A failed Vehicle insert should raise an error');
    Assert.isTrue(
      message.startsWith('Your claim could not be submitted'),
      'Error should explain the claim was not submitted'
    );
    Assert.isTrue(
      message.contains('Model'),
      'Claim should fail because Model is missing: ' + message
    );
    assertNothingSaved();
  }

  /**
   * @description Verifies a claim with no customer is rejected, for both roles that will
   *              later be able to submit on a customer's behalf (agent and System
   *              Administrator). Neither has a Contact of their own.
   */
  @IsTest
  static void rejectsClaimWithoutCustomer() {
    for (String username : new List<String>{ AGENT_USERNAME, ADMIN_USERNAME }) {
      String message;
      System.runAs(getUser(username)) {
        message = captureError(
          buildClaim(System.now().addDays(-1)),
          buildVehicle('Golf')
        );
      }
      Assert.areEqual(
        'A claim must be submitted for a customer.',
        message,
        'A claim without a customer should be rejected for ' + username
      );
    }
    assertNothingSaved();
  }

  /**
   * @description Verifies the claim is rejected when either part of the form (the claim
   *              or the vehicle) is missing.
   */
  @IsTest
  static void rejectsMissingFormData() {
    Map<String, List<SObject>> incompleteForms = new Map<String, List<SObject>>{
      'claim and vehicle missing' => new List<SObject>{ null, null },
      'vehicle missing' => new List<SObject>{
        buildClaim(System.now().addDays(-1)),
        null
      },
      'claim missing' => new List<SObject>{ null, buildVehicle('Golf') }
    };

    System.runAs(getCustomerPortalUser()) {
      for (String scenario : incompleteForms.keySet()) {
        List<SObject> form = incompleteForms.get(scenario);
        String message = captureError((Case) form[0], (Vehicle__c) form[1]);
        Assert.areEqual(
          'Please complete the claim form.',
          message,
          'Should be rejected when ' + scenario
        );
      }
    }
    assertNothingSaved();
  }

  // ---------- Helpers ----------

  private static User getUser(String username) {
    return [SELECT Id FROM User WHERE Username = :username];
  }

  /**
   * @description Submits a claim and returns the error message, or null if it was saved.
   */
  private static String captureError(Case claim, Vehicle__c vehicle) {
    try {
      VehicleClaimController.createClaim(claim, vehicle);
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
    return null;
  }

  private static User getCustomerPortalUser() {
    return [
      SELECT Id, ContactId, Contact.AccountId
      FROM User
      WHERE Username = :CUSTOMER_PORTAL_USERNAME
    ];
  }

  private static Case buildClaim(Datetime incidentDate) {
    return new Case(
      Date_and_Time_of_Incident__c = incidentDate,
      Subject = SUBJECT,
      Damage_Detail__c = 'Rear bumper dented',
      Description = 'Hit from behind while stationary'
    );
  }

  private static Vehicle__c buildVehicle(String model) {
    return new Vehicle__c(
      Make__c = 'Volkswagen',
      Model__c = model,
      Registration_number__c = 'AB12 CDE',
      Mileage__c = 42000,
      Engine_Capacity__c = 1600
    );
  }

  private static void assertNothingSaved() {
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Case WHERE Subject = :SUBJECT],
      'No Case should be saved'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Vehicle__c
        WHERE Registration_number__c = 'AB12 CDE'
      ],
      'No Vehicle should be saved'
    );
  }

  private static User buildUser(Id profileId, String username) {
    return new User(
      ProfileId = profileId,
      Username = username,
      Email = 'claims.test@example.com',
      LastName = 'Claims Test',
      Alias = 'clmtest',
      TimeZoneSidKey = UserInfo.getTimeZone().getID(),
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
}
