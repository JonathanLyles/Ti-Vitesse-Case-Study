/**
 * @description Annual batch job that resets the yearly total loss vehicle count
 *              (Total_Loss_Vehicles_Yearly__c) to zero on all agent Accounts.
 *              Implements Database.RaisesPlatformEvents so unhandled exceptions
 *              publish BatchApexErrorEvent for monitoring.
 */
public with sharing class AnnualAgentResetBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {

    /**
     * @description Collects all Accounts flagged as agents (Is_Agent__c = true).
     * @param context The batch context provided by the platform.
     * @return A QueryLocator over the agent Accounts to be reset.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        
        return Database.getQueryLocator('SELECT Id FROM Account WHERE Is_Agent__c = true', AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Sets Total_Loss_Vehicles_Yearly__c to 0 for each agent Account
     *              in the current chunk and updates the records.
     * @param context The batch context provided by the platform.
     * @param scope   The chunk of agent Accounts to process.
     */
    public void execute(Database.BatchableContext context, List<Account> scope) {
        List<Account>accountsToUpdate = new List<Account>();
        for(Account acc : scope){
            acc.Total_Loss_Vehicles_Yearly__c = 0;
            accountsToUpdate.add(acc);
        }
        if(!accountsToUpdate.isEmpty()){
            update accountsToUpdate;
        }

    }

    /**
     * @description Runs once after all chunks complete. Looks up the job's
     *              AsyncApexJob record and emails the submitter a summary of
     *              batches processed and failures.
     * @param context The batch context provided by the platform.
     */
    public void finish(Database.BatchableContext context) {
        // Get the ID of the AsyncApexJob representing this batch job
        // from Database.BatchableContext.
        // Query the AsyncApexJob object to retrieve the current job's information.
        AsyncApexJob a = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed,
            TotalJobItems, CreatedBy.Email
            FROM AsyncApexJob WHERE Id =
            :context.getJobId() WITH USER_MODE];
        // Send an email to the Apex job's submitter notifying of job completion.
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        String[] toAddresses = new String[] {a.CreatedBy.Email};
        mail.setToAddresses(toAddresses);
        mail.setSubject('Annual Agent Reset ' + a.Status);
        mail.setPlainTextBody
        ('The batch Apex job processed ' + a.TotalJobItems +
        ' batches with '+ a.NumberOfErrors + ' failures.');
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}
