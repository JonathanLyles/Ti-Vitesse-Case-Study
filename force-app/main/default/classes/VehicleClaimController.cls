/**
 * @description Server-side controller for the createVehicleClaim LWC. Creates a
 *              Vehicle Claims Case and its Vehicle in one transaction for the
 *              logged-in Experience Cloud customer.
 */
public with sharing class VehicleClaimController {
  private static final String VEHICLE_CLAIMS_RECORD_TYPE = 'Vehicle_Claims';
  private static final String DAMAGED_VEHICLE_RECORD_TYPE = 'Damaged_Vehicle';
  private static final String NEW_STATUS = 'New';

  /**
   * @description Returns the Damaged Vehicle record type Id, so the form can load the
   *              Make values for the record type claim vehicles are saved with.
   * @return The Vehicle__c Damaged_Vehicle record type Id.
   */
  @AuraEnabled(cacheable=true)
  public static Id getVehicleRecordTypeId() {
    return Schema.SObjectType.Vehicle__c.getRecordTypeInfosByDeveloperName()
      .get(DAMAGED_VEHICLE_RECORD_TYPE)
      .getRecordTypeId();
  }

  /**
   * @description Creates a Case (record type Vehicle Claims, Status New) for the
   *              current user's Contact and Account, and a Damaged Vehicle linked to
   *              that Case. Only the fields shown on the claim form are copied from
   *              the inputs. Both records are saved, or neither is.
   * @param claim   Case values from the form: Date_and_Time_of_Incident__c,
   *                Subject, Damage_Detail__c, Description.
   * @param vehicle Vehicle values from the form: Make__c, Model__c,
   *                Registration_number__c, Mileage__c, Engine_Capacity__c.
   * @return The Id of the new Case.
   */
  @AuraEnabled
  public static Id createClaim(Case claim, Vehicle__c vehicle) {
    if (claim == null || vehicle == null) {
      throw buildError('Please complete the claim form.');
    }

    User currentUser = [
      SELECT ContactId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    if (currentUser.ContactId == null) {
      throw buildError('A claim must be submitted for a customer.');
    }

    // Mirrors the Incident_Date_and_Time validation rule with a clearer message
    if (
      claim.Date_and_Time_of_Incident__c != null &&
      claim.Date_and_Time_of_Incident__c > System.now()
    ) {
      throw buildError(
        'The date and time of the incident cannot be in the future.'
      );
    }

    Case newCase = new Case(
      RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get(VEHICLE_CLAIMS_RECORD_TYPE)
        .getRecordTypeId(),
      Status = NEW_STATUS,
      ContactId = currentUser.ContactId,
      Date_and_Time_of_Incident__c = claim.Date_and_Time_of_Incident__c,
      Subject = claim.Subject,
      Damage_Detail__c = claim.Damage_Detail__c,
      Description = claim.Description
    );

    Savepoint savepoint = Database.setSavepoint();
    try {
      insert as user newCase;

      insert as user new Vehicle__c(
        RecordTypeId = getVehicleRecordTypeId(),
        Case__c = newCase.Id,
        Contact__c = currentUser.ContactId,
        Make__c = vehicle.Make__c,
        Model__c = vehicle.Model__c,
        Registration_number__c = vehicle.Registration_number__c,
        Mileage__c = vehicle.Mileage__c,
        Engine_Capacity__c = vehicle.Engine_Capacity__c
      );
    } catch (Exception e) {
      Database.rollback(savepoint);
      String message = e instanceof DmlException
        ? ((DmlException) e).getDmlMessage(0)
        : e.getMessage();
      throw buildError('Your claim could not be submitted: ' + message);
    }

    return newCase.Id;
  }

  /**
   * @description Builds an AuraHandledException whose message is readable both in
   *              the LWC and in Apex tests.
   * @param message The message to show the user.
   * @return The exception to throw.
   */
  private static AuraHandledException buildError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
