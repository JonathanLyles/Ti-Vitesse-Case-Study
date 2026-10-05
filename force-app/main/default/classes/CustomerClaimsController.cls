/**
 * @description Server-side controller for the myVehicleClaims LWC. Returns the
 *              Vehicle Claims Cases of the logged-in Experience Cloud customer,
 *              with their Damaged Vehicles.
 */
public with sharing class CustomerClaimsController {
  private static final String VEHICLE_CLAIMS_RECORD_TYPE = 'Vehicle_Claims';
  private static final String DAMAGED_VEHICLE_RECORD_TYPE = 'Damaged_Vehicle';

  /**
   * @description Returns the Vehicle Claims Cases raised for the current user's
   *              Contact, newest first, each with its Damaged Vehicles (oldest
   *              first). Loan Vehicles are left out. The query runs in user mode, so
   *              only records and fields the customer may read are returned.
   * @return The customer's claims, or an empty list when the user has no Contact
   *         (for example an internal user) or no claims.
   */
  @AuraEnabled
  public static List<Case> getMyClaims() {
    Id contactId = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ]
    .ContactId;
    if (contactId == null) {
      return new List<Case>();
    }

    try {
      return [
        SELECT
          Id,
          CaseNumber,
          Subject,
          Status,
          CreatedDate,
          Date_and_Time_of_Incident__c,
          Damage_Detail__c,
          Description,
          (
            SELECT
              Id,
              Make__c,
              Model__c,
              Registration_number__c,
              Mileage__c,
              Engine_Capacity__c
            FROM Vehicles__r
            WHERE RecordType.DeveloperName = :DAMAGED_VEHICLE_RECORD_TYPE
            ORDER BY CreatedDate
          )
        FROM Case
        WHERE
          ContactId = :contactId
          AND RecordType.DeveloperName = :VEHICLE_CLAIMS_RECORD_TYPE
        WITH USER_MODE
        ORDER BY CreatedDate DESC, CaseNumber DESC
      ];
    } catch (Exception e) {
      throw buildError('Your claims could not be loaded: ' + e.getMessage());
    }
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
