/**
 * @description Monthly Batch Apex job that calculates commissions for Agent Accounts
 *              that had invoice activity in the previous calendar month.
 *
 *              The batch runs over Accounts rather than Invoices because commission
 *              is calculated per Account: each Account has one commission rate, while
 *              many invoices may contribute to its commission amount. Processing
 *              Accounts means each Account is handled once, the batch scope matches
 *              the record being updated, the commission rate is already available in
 *              scope, and invoice records are only loaded when they are needed.
 *
 *              Alternatives considered and rejected:
 *              - Querying Invoices first and building a Set of Account Ids: loads
 *                invoice records into heap, needs extra queries, and scales poorly as
 *                invoice volume grows.
 *              - Batching over Invoice records: the same Account can appear in many
 *                chunks, so totals would have to be accumulated across chunks
 *                (e.g. Database.Stateful), which adds complexity and risk of
 *                duplicate processing.
 *              - Using an aggregate query as the batch scope: QueryLocator works with
 *                sObjects rather than aggregate results, aggregate queries are limited
 *                to 2,000 grouped rows, and Account fields would need a separate query.
 *
 *              Expected volumes: several thousand Agent Accounts, with up to about 200
 *              invoices per Account per month.
 */
public with sharing class MonthlyAgentCommissionCalculationBatch implements Database.Batchable<SObject>{

    /**
     * @description Selects Agent Accounts with at least one Invoice dated in the
     *              previous calendar month. The semi-join filters in the database,
     *              so each Account is returned once regardless of how many invoices
     *              it has, and Accounts with no invoice activity are skipped.
     * @param context The batch context provided by the platform.
     * @return A QueryLocator over the Agent Accounts to process, including
     *         Commission_Rate__c.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Commission_Rate__c
            FROM Account
            WHERE Is_Agent__c = true
            AND Id IN (
                SELECT Account__c
                FROM Invoice__c
                WHERE Invoice_Date__c = LAST_MONTH
            )
        ]);
    }

    /**
     * @description Calculates commission for the Agent Accounts in this chunk. An
     *              aggregate query sums Amount_without_VAT__c of the previous month's
     *              Invoices, grouped by Account, for only the Accounts in scope. Each
     *              Account's Commission_Rate__c is then applied to its total.
     * @param context The batch context provided by the platform.
     * @param scope   The chunk of Agent Accounts to process.
     */
    public void execute(Database.BatchableContext context, List<Account> scope) {
        
        Map<Id, Account> accountMap = new Map<Id, Account>(scope);
        List<Account>accountsToUpdate = new List<Account>();

        List<AggregateResult> results = [SELECT Account__c, SUM(Amount_without_VAT__c) total
         FROM Invoice__c
         WHERE Invoice_Date__c = LAST_MONTH
         AND Account__c IN :new Map<Id, Account>(scope).keySet()
         GROUP BY Account__c];


         for(AggregateResult ar : results) {
            Id accId = (Id) ar.get('Account__c');
            Account acc = accountMap.get(accId);
            Decimal total = (Decimal) ar.get('total');
            // Commission_Rate__c is a Percent field: Apex returns 10 for 10%, so divide by 100
            acc.Monthly_Commission__c = total * (acc.Commission_Rate__c == null ? 0 : acc.Commission_Rate__c) / 100;
            accountsToUpdate.add(acc);
    }
        if(!accountsToUpdate.isEmpty()){
            update accountsToUpdate;
        }

    }

    /**
     * @description Runs once after all chunks have been processed. Emails a
     *              confirmation to the user who submitted the job, which for a
     *              scheduled run is the system admin who scheduled it.
     * @param context The batch context provided by the platform.
     */
    public void finish(Database.BatchableContext context) {
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedById
            FROM AsyncApexJob
            WHERE Id = :context.getJobId()
            WITH USER_MODE
        ];
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ buildConfirmationEmail(job) });
    }

    /**
     * @description Builds the job confirmation email. Sending to the submitter's
     *              User Id (rather than an email address) does not count against
     *              the org's daily email limit.
     * @param job The AsyncApexJob record for this batch run.
     * @return The confirmation email addressed to the user who submitted the job.
     */
    @TestVisible
    private static Messaging.SingleEmailMessage buildConfirmationEmail(AsyncApexJob job) {
        String period = Datetime.newInstance(Date.today().addMonths(-1), Time.newInstance(0, 0, 0, 0))
            .format('MMMM yyyy');

        String body = 'The monthly agent commission calculation for ' + period
            + ' finished with status ' + job.Status + '.\n\n'
            + 'Batches processed: ' + job.JobItemsProcessed + ' of ' + job.TotalJobItems + '\n'
            + 'Batches with errors: ' + job.NumberOfErrors;
        if (job.NumberOfErrors > 0) {
            body += '\n\nSome Agent commissions were not updated. See Setup > Apex Jobs for details.';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(job.CreatedById);
        mail.setSaveAsActivity(false);
        mail.setSubject('Monthly Agent Commission Calculation ' + period + ': ' + job.Status);
        mail.setPlainTextBody(body);
        return mail;
    }
}
