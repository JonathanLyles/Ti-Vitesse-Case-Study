/**
 * @description Unit tests for CustomerClaimsController. Claims are read as a Customer
 *              Portal User (Customer Community Clone profile) with the Community Site
 *              and Vehicle Claim Portal Access permission sets, as on the Experience
 *              Cloud site. Only two portal users are created, because the org has few
 *              Customer Community licences; other customers are plain Contacts that
 *              own claims but never log in.
 */
@IsTest
private class CustomerClaimsControllerTest {
  private static final String AGENT_PROFILE = 'Custom - TVI Agents';
  private static final String AGENT_ROLE = 'Agent_West';
  private static final String CUSTOMER_PORTAL_PROFILE = 'Customer Community Clone';
  private static final String VEHICLE_CLAIMS_RECORD_TYPE = 'Vehicle_Claims';
  private static final String DAMAGED_VEHICLE = 'Damaged_Vehicle';
  private static final String LOAN_VEHICLE = 'Loan_Vehicle';
  private static final Set<String> CUSTOMER_PORTAL_PERMISSION_SETS = new Set<String>{
    'Community_Site_Permission_Set',
    'Vehicle_Claim_Portal_Access'
  };
  private static final String AGENT_USERNAME =
    'myclaims.agent@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String ADMIN_USERNAME =
    'myclaims.admin@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String CUSTOMER_USERNAME =
    'myclaims.customer@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String NO_PERMISSIONS_USERNAME =
    'myclaims.nopermissions@' +
    UserInfo.getOrganizationId() +
    '.test';
  private static final String CUSTOMER_LAST_NAME = 'Customer';
  private static final String HOUSEHOLD_LAST_NAME = 'Household Member';
  private static final String OTHER_LAST_NAME = 'Other Customer';

  /**
   * @description Creates an agent who owns two Accounts, a System Administrator, and
   *              these customers: the portal customer and a household member (Contact
   *              only) on the first Account, another customer (Contact only) on the
   *              second Account, and a second portal user on the first Account who is
   *              not given the Vehicle Claim Portal Access permission set. Setup and
   *              non-setup records are inserted in separate runAs blocks to avoid
   *              mixed DML errors.
   */
  @TestSetup
  static void setup() {
    User agent;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      agent = buildUser(
        [SELECT Id FROM Profile WHERE Name = :AGENT_PROFILE].Id,
        AGENT_USERNAME
      );
      agent.UserRoleId = [
        SELECT Id
        FROM UserRole
        WHERE DeveloperName = :AGENT_ROLE
      ]
      .Id;
      agent.UserPermissionsInteractionUser = true;
      User admin = buildUser(
        [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
        ADMIN_USERNAME
      );
      insert new List<User>{ agent, admin };
    }

    Contact customer;
    Contact noPermissionsCustomer;
    System.runAs(agent) {
      Account household = new Account(Name = 'Claims Household');
      Account otherAccount = new Account(Name = 'Claims Other Account');
      insert new List<Account>{ household, otherAccount };
      customer = new Contact(
        LastName = CUSTOMER_LAST_NAME,
        AccountId = household.Id
      );
      noPermissionsCustomer = new Contact(
        LastName = 'No Permissions',
        AccountId = household.Id
      );
      insert new List<Contact>{
        customer,
        noPermissionsCustomer,
        new Contact(LastName = HOUSEHOLD_LAST_NAME, AccountId = household.Id),
        new Contact(LastName = OTHER_LAST_NAME, AccountId = otherAccount.Id)
      };
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id profileId = [
        SELECT Id
        FROM Profile
        WHERE Name = :CUSTOMER_PORTAL_PROFILE
      ]
      .Id;
      User customerUser = buildUser(profileId, CUSTOMER_USERNAME);
      customerUser.ContactId = customer.Id;
      User noPermissionsUser = buildUser(profileId, NO_PERMISSIONS_USERNAME);
      noPermissionsUser.ContactId = noPermissionsCustomer.Id;
      insert new List<User>{ customerUser, noPermissionsUser };

      Map<String, Id> permissionSetIds = new Map<String, Id>();
      for (PermissionSet permissionSet : [
        SELECT Id, Name
        FROM PermissionSet
        WHERE Name IN :CUSTOMER_PORTAL_PERMISSION_SETS
      ]) {
        permissionSetIds.put(permissionSet.Name, permissionSet.Id);
      }
      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
      for (String name : permissionSetIds.keySet()) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = customerUser.Id,
            PermissionSetId = permissionSetIds.get(name)
          )
        );
      }
      // The second user only gets the site permission set
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = noPermissionsUser.Id,
          PermissionSetId = permissionSetIds.get(
            'Community_Site_Permission_Set'
          )
        )
      );
      insert assignments;
    }
  }

  /**
   * @description Verifies the customer gets their Vehicle Claims Case with the fields
   *              the list and the details show.
   */
  @IsTest
  static void returnsOwnVehicleClaimsWithCaseFields() {
    Datetime incident = System.now().addDays(-2);
    Case claim = insertClaim(
      getContact(CUSTOMER_LAST_NAME),
      'Rear-ended at traffic lights',
      'In progress',
      incident
    );

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      Test.startTest();
      claims = CustomerClaimsController.getMyClaims();
      Test.stopTest();
    }

    Assert.areEqual(1, claims.size(), 'The customer has one claim');
    Case result = claims[0];
    Assert.areEqual(claim.Id, result.Id, 'Should be the customer claim');
    Assert.isNotNull(result.CaseNumber, 'Case Number should be returned');
    Assert.areEqual(
      'Rear-ended at traffic lights',
      result.Subject,
      'Subject should be returned'
    );
    Assert.areEqual('In progress', result.Status, 'Status should be returned');
    Assert.isNotNull(result.CreatedDate, 'Date submitted should be returned');
    Assert.areEqual(
      incident,
      result.Date_and_Time_of_Incident__c,
      'Incident date should be returned'
    );
    Assert.areEqual(
      'Rear bumper dented',
      result.Damage_Detail__c,
      'Damage detail should be returned'
    );
    Assert.areEqual(
      'Hit from behind while stationary',
      result.Description,
      'Description should be returned'
    );
  }

  /**
   * @description Verifies each claim comes with its Damaged Vehicle's details.
   */
  @IsTest
  static void includesDamagedVehicleDetails() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Case claim = insertClaim(customer, 'Claim with vehicle', 'New', null);
    insertVehicle(claim, customer, DAMAGED_VEHICLE, 'Golf');

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(1, claims.size(), 'The customer has one claim');
    Assert.areEqual(
      1,
      claims[0].Vehicles__r.size(),
      'The claim has one vehicle'
    );
    Vehicle__c vehicle = claims[0].Vehicles__r[0];
    Assert.areEqual('Volkswagen', vehicle.Make__c, 'Make should be returned');
    Assert.areEqual('Golf', vehicle.Model__c, 'Model should be returned');
    Assert.areEqual(
      'REG Golf',
      vehicle.Registration_number__c,
      'Registration number should be returned'
    );
    Assert.areEqual(42000, vehicle.Mileage__c, 'Mileage should be returned');
    Assert.areEqual(
      1600,
      vehicle.Engine_Capacity__c,
      'Engine capacity should be returned'
    );
  }

  /**
   * @description Verifies claims come back with the most recently submitted first.
   *              Inserted out of order, with created dates set explicitly because
   *              records inserted in a test share the same timestamp.
   */
  @IsTest
  static void sortsNewestFirst() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Case oldest = insertClaim(customer, 'Oldest', 'New', null);
    Case newest = insertClaim(customer, 'Newest', 'New', null);
    Case middle = insertClaim(customer, 'Middle', 'New', null);
    Datetime now = System.now();
    Test.setCreatedDate(oldest.Id, now.addDays(-3));
    Test.setCreatedDate(newest.Id, now.addDays(-1));
    Test.setCreatedDate(middle.Id, now.addDays(-2));

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(3, claims.size(), 'The customer has three claims');
    Assert.areEqual(
      'Newest',
      claims[0].Subject,
      'Newest claim should be first'
    );
    Assert.areEqual(
      'Middle',
      claims[1].Subject,
      'Middle claim should be second'
    );
    Assert.areEqual('Oldest', claims[2].Subject, 'Oldest claim should be last');
  }

  /**
   * @description Verifies a claim belonging to a customer on another Account is never
   *              returned.
   */
  @IsTest
  static void excludesOtherCustomersClaims() {
    insertClaim(getContact(CUSTOMER_LAST_NAME), 'Mine', 'New', null);
    insertClaim(getContact(OTHER_LAST_NAME), 'Theirs', 'New', null);

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(
      1,
      claims.size(),
      'Only the customer own claim is returned'
    );
    Assert.areEqual('Mine', claims[0].Subject, 'Should be the customer claim');
  }

  /**
   * @description Verifies a customer with no claims gets an empty list, not an error,
   *              even when other customers have claims.
   */
  @IsTest
  static void returnsEmptyListWhenCustomerHasNoClaims() {
    insertClaim(getContact(OTHER_LAST_NAME), 'Theirs', 'New', null);

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.isNotNull(claims, 'The result should not be null');
    Assert.isTrue(claims.isEmpty(), 'A customer with no claims gets no rows');
  }

  /**
   * @description Verifies an internal user, who has no Contact, gets an empty list
   *              rather than every claim in the org.
   */
  @IsTest
  static void returnsEmptyListForInternalUser() {
    insertClaim(getContact(CUSTOMER_LAST_NAME), 'Mine', 'New', null);

    List<Case> claims;
    System.runAs(getUser(ADMIN_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.isNotNull(claims, 'The result should not be null');
    Assert.isTrue(claims.isEmpty(), 'A user without a Contact gets no rows');
  }

  /**
   * @description Verifies a portal user without the Vehicle Claim Portal Access
   *              permission set gets a readable error and no data. The incident date,
   *              damage detail and Vehicle read access come only from that permission
   *              set, so this fails if the query stops running in user mode.
   */
  @IsTest
  static void throwsReadableErrorWithoutClaimPermissions() {
    insertClaim(getContact('No Permissions'), 'Hidden', 'New', null);

    String message;
    List<Case> claims;
    System.runAs(getUser(NO_PERMISSIONS_USERNAME)) {
      try {
        claims = CustomerClaimsController.getMyClaims();
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }

    Assert.isNull(claims, 'No data should be returned');
    Assert.isNotNull(message, 'A user without the permission set is rejected');
    Assert.isTrue(
      message.startsWith('Your claims could not be loaded'),
      'Error should explain the claims could not be loaded: ' + message
    );
  }

  /**
   * @description Verifies a claim without a vehicle (for example one raised by an
   *              agent) is still returned, with no vehicles.
   */
  @IsTest
  static void returnsClaimWithoutVehicle() {
    insertClaim(getContact(CUSTOMER_LAST_NAME), 'No vehicle', 'New', null);

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(1, claims.size(), 'The claim should still be returned');
    Assert.isTrue(
      claims[0].Vehicles__r == null || claims[0].Vehicles__r.isEmpty(),
      'The claim has no vehicles'
    );
  }

  /**
   * @description Verifies another Contact on the same Account (a household or company)
   *              cannot see the customer's claim, and the customer cannot see theirs.
   */
  @IsTest
  static void excludesSameAccountDifferentContact() {
    insertClaim(getContact(CUSTOMER_LAST_NAME), 'Mine', 'New', null);
    insertClaim(getContact(HOUSEHOLD_LAST_NAME), 'Household', 'New', null);

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(
      1,
      claims.size(),
      'Only the customer own claim is returned'
    );
    Assert.areEqual('Mine', claims[0].Subject, 'Should be the customer claim');
  }

  /**
   * @description Verifies claims in every status, including Closed, are returned.
   */
  @IsTest
  static void returnsClaimsInEveryStatus() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Set<String> statuses = new Set<String>{
      'New',
      'On hold',
      'In progress',
      'Payment',
      'Closed'
    };
    for (String status : statuses) {
      insertClaim(customer, 'Claim ' + status, status, null);
    }

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Set<String> returnedStatuses = new Set<String>();
    for (Case claim : claims) {
      returnedStatuses.add(claim.Status);
    }
    Assert.areEqual(5, claims.size(), 'A claim in every status is returned');
    Assert.areEqual(statuses, returnedStatuses, 'Every status should appear');
  }

  /**
   * @description Verifies claims with the same created date come back in a stable
   *              order, newest Case Number first.
   */
  @IsTest
  static void ordersSameSecondClaimsByCaseNumber() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Case first = insertClaim(customer, 'First', 'New', null);
    Case second = insertClaim(customer, 'Second', 'New', null);
    Datetime sameMoment = System.now().addDays(-1);
    Test.setCreatedDate(first.Id, sameMoment);
    Test.setCreatedDate(second.Id, sameMoment);

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(2, claims.size(), 'The customer has two claims');
    Assert.areEqual(
      'Second',
      claims[0].Subject,
      'The higher Case Number should come first'
    );
    Assert.areEqual(
      'First',
      claims[1].Subject,
      'The lower Case Number is last'
    );
  }

  /**
   * @description Verifies a customer with more than 200 claims (the default batch
   *              size of a query) gets every claim with its vehicle.
   */
  @IsTest
  static void returnsAllClaimsWhenCustomerHasMany() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Id recordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
      .get(VEHICLE_CLAIMS_RECORD_TYPE)
      .getRecordTypeId();
    Id damagedVehicleTypeId = Schema.SObjectType.Vehicle__c.getRecordTypeInfosByDeveloperName()
      .get(DAMAGED_VEHICLE)
      .getRecordTypeId();

    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 201; i++) {
      cases.add(
        new Case(
          RecordTypeId = recordTypeId,
          ContactId = customer.Id,
          Subject = 'Bulk claim ' + i,
          Status = 'New'
        )
      );
    }
    insert cases;
    List<Vehicle__c> vehicles = new List<Vehicle__c>();
    for (Integer i = 0; i < cases.size(); i++) {
      vehicles.add(
        buildVehicle(
          cases[i],
          customer,
          damagedVehicleTypeId,
          'Golf',
          'BULK ' + i
        )
      );
    }
    insert vehicles;

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(201, claims.size(), 'Every claim should be returned');
    Integer withVehicle = 0;
    for (Case claim : claims) {
      if (claim.Vehicles__r != null && claim.Vehicles__r.size() == 1) {
        withVehicle++;
      }
    }
    Assert.areEqual(201, withVehicle, 'Every claim should have its vehicle');
  }

  /**
   * @description Verifies a Loan Vehicle linked to the claim is not returned as one of
   *              the claim's damaged vehicles.
   */
  @IsTest
  static void excludesLoanVehicleFromDetails() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Case claim = insertClaim(customer, 'Claim with loan car', 'New', null);
    insertVehicle(claim, customer, DAMAGED_VEHICLE, 'Golf');
    insertVehicle(claim, customer, LOAN_VEHICLE, 'Polo');

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(
      1,
      claims[0].Vehicles__r.size(),
      'Only the damaged vehicle'
    );
    Assert.areEqual(
      'Golf',
      claims[0].Vehicles__r[0].Model__c,
      'The loan vehicle should not be listed'
    );
  }

  /**
   * @description Verifies damaged vehicles added by someone else (an agent or admin,
   *              so not owned by the customer) are visible to the customer through the
   *              Customer Claims Access sharing set, and are listed oldest first.
   */
  @IsTest
  static void showsVehiclesAddedByAgent() {
    Contact customer = getContact(CUSTOMER_LAST_NAME);
    Case claim = insertClaim(customer, 'Claim with two vehicles', 'New', null);
    Vehicle__c first = insertVehicle(claim, customer, DAMAGED_VEHICLE, 'Golf');
    Vehicle__c second = insertVehicle(
      claim,
      customer,
      DAMAGED_VEHICLE,
      'Passat'
    );
    Datetime now = System.now();
    Test.setCreatedDate(first.Id, now.addDays(-2));
    Test.setCreatedDate(second.Id, now.addDays(-1));

    List<Case> claims;
    System.runAs(getUser(CUSTOMER_USERNAME)) {
      claims = CustomerClaimsController.getMyClaims();
    }

    Assert.areEqual(1, claims.size(), 'The customer has one claim');
    Assert.areEqual(
      2,
      claims[0].Vehicles__r.size(),
      'Both vehicles are visible'
    );
    Assert.areEqual('Golf', claims[0].Vehicles__r[0].Model__c, 'Oldest first');
    Assert.areEqual('Passat', claims[0].Vehicles__r[1].Model__c, 'Newest last');
  }

  // ---------- Helpers ----------

  private static User getUser(String username) {
    return [SELECT Id FROM User WHERE Username = :username];
  }

  private static Contact getContact(String lastName) {
    return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName];
  }

  /**
   * @description Inserts a Vehicle Claims Case for the Contact as the test runner (the
   *              agent profile cannot edit the incident fields); the Case assignment
   *              flow gives it to the Account owner, the agent. Details are filled in
   *              so the tests can check them.
   */
  private static Case insertClaim(
    Contact contact,
    String subject,
    String status,
    Datetime incident
  ) {
    Case claim = new Case(
      RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get(VEHICLE_CLAIMS_RECORD_TYPE)
        .getRecordTypeId(),
      ContactId = contact.Id,
      Subject = subject,
      Status = status,
      Date_and_Time_of_Incident__c = incident,
      Damage_Detail__c = 'Rear bumper dented',
      Description = 'Hit from behind while stationary'
    );
    insert claim;
    return claim;
  }

  /**
   * @description Inserts a Vehicle of the given record type as the test runner, so it
   *              is not owned by the customer. The registration number is derived
   *              from the model, because it must be unique.
   */
  private static Vehicle__c insertVehicle(
    Case claim,
    Contact contact,
    String recordTypeDeveloperName,
    String model
  ) {
    Vehicle__c vehicle = buildVehicle(
      claim,
      contact,
      Schema.SObjectType.Vehicle__c.getRecordTypeInfosByDeveloperName()
        .get(recordTypeDeveloperName)
        .getRecordTypeId(),
      model,
      'REG ' + model
    );
    insert vehicle;
    return vehicle;
  }

  private static Vehicle__c buildVehicle(
    Case claim,
    Contact contact,
    Id recordTypeId,
    String model,
    String registration
  ) {
    return new Vehicle__c(
      RecordTypeId = recordTypeId,
      Case__c = claim.Id,
      Contact__c = contact.Id,
      Make__c = 'Volkswagen',
      Model__c = model,
      Registration_number__c = registration,
      Mileage__c = 42000,
      Engine_Capacity__c = 1600
    );
  }

  private static User buildUser(Id profileId, String username) {
    return new User(
      ProfileId = profileId,
      Username = username,
      Email = 'myclaims.test@example.com',
      LastName = 'My Claims Test',
      Alias = 'myclm',
      TimeZoneSidKey = UserInfo.getTimeZone().getID(),
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
}
