/**
 * Loan operations are exposed only through methods that first authorize the
 * running user against the Case Contact. Queries and DML run in system mode so
 * portal users can use this narrowly scoped workflow without direct edit access.
 */
public without sharing class VehicleLoanController {
  private static final String VEHICLE_CLAIMS_RECORD_TYPE = 'Vehicle_Claims';
  private static final String LOAN_VEHICLE_RECORD_TYPE = 'Loan_Vehicle';
  private static final String NOT_AUTHORIZED = 'You are not authorized to access this active vehicle claim.';

  @AuraEnabled
  public static VehicleLoanContext getLoanContext(Id caseId) {
    AuthorizedCase authorizedCase = authorizeCase(caseId);
    VehicleLoanContext context = new VehicleLoanContext();
    List<Vehicle__c> activeLoans = getActiveLoans(authorizedCase.contactId);

    if (!activeLoans.isEmpty()) {
      context.activeLoan = activeLoans[0];
      context.canReturnActiveLoan =
        activeLoans[0].Case__c == authorizedCase.caseRecord.Id;
      return context;
    }

    try {
      for (
        VehicleLoanApiResponse.Vehicle vehicle : new VehicleLoanApiClient()
          .getVehicles()
          .vehicles
      ) {
        context.availableVehicles.add(new VehicleLoanOption(vehicle));
      }
    } catch (CalloutException e) {
      logIntegrationFailure(e);
      throw buildError(
        'Available vehicles could not be loaded. Please try again.'
      );
    } catch (System.JSONException e) {
      logIntegrationFailure(e);
      throw buildError(
        'Available vehicles could not be loaded. Please try again.'
      );
    }
    return context;
  }

  @AuraEnabled
  public static VehicleLoanActionResult reserveVehicle(
    Id caseId,
    String registrationNumber,
    Integer mileage,
    Integer engineCapacity
  ) {
    AuthorizedCase authorizedCase = authorizeCase(caseId);
    if (String.isBlank(registrationNumber)) {
      throw buildError('Select a vehicle before requesting a reservation.');
    }
    if (
      mileage == null ||
      mileage < 0 ||
      mileage > 999999 ||
      engineCapacity == null ||
      engineCapacity < 0 ||
      engineCapacity > 9999
    ) {
      throw buildError('Enter a valid mileage and engine capacity.');
    }
    if (!getActiveLoans(authorizedCase.contactId).isEmpty()) {
      throw buildError('This Contact already has an active vehicle loan.');
    }

    VehicleLoanApiResponse.Vehicle selectedVehicle;
    try {
      for (
        VehicleLoanApiResponse.Vehicle vehicle : new VehicleLoanApiClient()
          .getVehicles()
          .vehicles
      ) {
        if (vehicle.RegistrationNumber == registrationNumber) {
          selectedVehicle = vehicle;
          break;
        }
      }
    } catch (CalloutException e) {
      logIntegrationFailure(e);
      throw buildError(
        'The vehicle reservation could not be completed. Please try again.'
      );
    } catch (System.JSONException e) {
      logIntegrationFailure(e);
      throw buildError(
        'The vehicle reservation could not be completed. Please try again.'
      );
    }

    if (selectedVehicle == null) {
      throw buildError(
        'That vehicle is no longer available. Refresh the list and try again.'
      );
    }

    Vehicle__c loan;
    try {
      loan = selectedVehicle.toVehicleRecord();
      loan.RecordTypeId = getLoanVehicleRecordTypeId();
      loan.Case__c = authorizedCase.caseRecord.Id;
      loan.Contact__c = authorizedCase.contactId;
      loan.Loan_Active__c = true;
      loan.Mileage__c = mileage;
      loan.Engine_Capacity__c = engineCapacity;
      new VehicleLoanApiClient().updateVehicle(registrationNumber);
    } catch (CalloutException e) {
      logIntegrationFailure(e);
      throw buildError(
        'The vehicle reservation could not be completed. Please try again.'
      );
    } catch (IllegalArgumentException e) {
      logIntegrationFailure(e);
      throw buildError(
        'The selected vehicle details are incomplete. Please contact support.'
      );
    }

    try {
      Database.insert(loan, AccessLevel.SYSTEM_MODE);
      return new VehicleLoanActionResult(
        true,
        true,
        'The vehicle has been reserved.'
      );
    } catch (DmlException e) {
      logPersistenceFailure(e);
      return new VehicleLoanActionResult(
        true,
        false,
        'The remote reservation succeeded, but Salesforce could not save the loan record. Contact support before taking further action.'
      );
    }
  }

  @AuraEnabled
  public static VehicleLoanActionResult returnVehicle(
    Id caseId,
    Id loanVehicleId
  ) {
    AuthorizedCase authorizedCase = authorizeCase(caseId);
    if (loanVehicleId == null) {
      throw buildError('Select an active loan before returning a vehicle.');
    }

    List<Vehicle__c> matchingLoans = [
      SELECT Id, Registration_number__c
      FROM Vehicle__c
      WHERE
        Id = :loanVehicleId
        AND Case__c = :authorizedCase.caseRecord.Id
        AND Contact__c = :authorizedCase.contactId
        AND RecordType.DeveloperName = :LOAN_VEHICLE_RECORD_TYPE
        AND Loan_Active__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (matchingLoans.isEmpty()) {
      throw buildError(NOT_AUTHORIZED);
    }

    try {
      new VehicleLoanApiClient()
        .updateVehicle(matchingLoans[0].Registration_number__c);
    } catch (CalloutException e) {
      logIntegrationFailure(e);
      throw buildError('The vehicle could not be returned. Please try again.');
    }

    try {
      Database.update(
        new Vehicle__c(
          Id = matchingLoans[0].Id,
          Loan_Active__c = false,
          Loan_End_Date__c = Date.today()
        ),
        AccessLevel.SYSTEM_MODE
      );
      return new VehicleLoanActionResult(
        true,
        true,
        'The vehicle has been returned.'
      );
    } catch (DmlException e) {
      logPersistenceFailure(e);
      return new VehicleLoanActionResult(
        true,
        false,
        'The remote return succeeded, but Salesforce could not update the loan record. Contact support before taking further action.'
      );
    }
  }

  private static AuthorizedCase authorizeCase(Id caseId) {
    if (caseId == null) {
      throw buildError(NOT_AUTHORIZED);
    }

    List<Case> cases = [
      SELECT Id, ContactId, IsClosed, RecordType.DeveloperName
      FROM Case
      WHERE Id = :caseId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (
      cases.isEmpty() ||
      cases[0].ContactId == null ||
      cases[0].IsClosed ||
      cases[0].RecordType.DeveloperName != VEHICLE_CLAIMS_RECORD_TYPE
    ) {
      throw buildError(NOT_AUTHORIZED);
    }

    User currentUser = [
      SELECT Id, ContactId, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ];
    Boolean isCustomer =
      currentUser.ContactId != null &&
      currentUser.ContactId == cases[0].ContactId;
    Boolean isContactOwnerAgent = false;

    if (currentUser.ContactId == null && currentUser.UserType == 'Standard') {
      Contact caseContact = [
        SELECT OwnerId
        FROM Contact
        WHERE Id = :cases[0].ContactId
        WITH SYSTEM_MODE
      ];
      isContactOwnerAgent = caseContact.OwnerId == currentUser.Id;
    }

    if (!isCustomer && !isContactOwnerAgent) {
      throw buildError(NOT_AUTHORIZED);
    }

    return new AuthorizedCase(cases[0], cases[0].ContactId);
  }

  private static List<Vehicle__c> getActiveLoans(Id contactId) {
    List<Vehicle__c> activeLoans = [
      SELECT
        Id,
        Case__c,
        Contact__c,
        Make__c,
        Model__c,
        Registration_number__c,
        Year_of_Vehicle__c,
        Loan_Active__c,
        Loan_End_Date__c
      FROM Vehicle__c
      WHERE
        Contact__c = :contactId
        AND RecordType.DeveloperName = :LOAN_VEHICLE_RECORD_TYPE
        AND Loan_Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 2
    ];
    if (activeLoans.size() > 1) {
      throw buildError(
        'More than one active loan exists for this Contact. Contact support.'
      );
    }
    return activeLoans;
  }

  private static Id getLoanVehicleRecordTypeId() {
    Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Vehicle__c.getRecordTypeInfosByDeveloperName()
      .get(LOAN_VEHICLE_RECORD_TYPE);
    if (recordTypeInfo == null) {
      throw buildError(
        'Loan Vehicle configuration is missing. Please contact support.'
      );
    }
    return recordTypeInfo.getRecordTypeId();
  }

  private static AuraHandledException buildError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }

  private static void logIntegrationFailure(Exception error) {
    System.debug(
      LoggingLevel.ERROR,
      'Vehicle loan integration failed (' + error.getTypeName() + ').'
    );
  }

  private static void logPersistenceFailure(DmlException error) {
    System.debug(
      LoggingLevel.ERROR,
      'Vehicle loan persistence failed (' + error.getTypeName() + ').'
    );
  }

  private class AuthorizedCase {
    private Case caseRecord;
    private Id contactId;

    private AuthorizedCase(Case caseRecord, Id contactId) {
      this.caseRecord = caseRecord;
      this.contactId = contactId;
    }
  }
}
