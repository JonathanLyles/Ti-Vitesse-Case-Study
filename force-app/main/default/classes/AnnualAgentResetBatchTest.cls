/**
 * @description Unit tests for AnnualAgentResetBatch.
 */
@IsTest
private class AnnualAgentResetBatchTest {

    private static final Integer AGENT_COUNT = 50;
    private static final Integer NON_AGENT_COUNT = 10;
    private static final Decimal STARTING_TOTAL = 7;

    /**
     * @description Creates agent and non-agent Accounts with a non-zero yearly total.
     */
    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < AGENT_COUNT; i++) {
            accounts.add(new Account(
                Name = 'Agent ' + i,
                Is_Agent__c = true,
                Total_Loss_Vehicles_Yearly__c = STARTING_TOTAL
            ));
        }
        for (Integer i = 0; i < NON_AGENT_COUNT; i++) {
            accounts.add(new Account(
                Name = 'Non-Agent ' + i,
                Is_Agent__c = false,
                Total_Loss_Vehicles_Yearly__c = STARTING_TOTAL
            ));
        }
        insert accounts;
    }

    /**
     * @description Verifies every agent Account's yearly total is reset to zero.
     */
    @IsTest
    static void resetsAgentTotalsToZero() {
        Test.startTest();
        Database.executeBatch(new AnnualAgentResetBatch());
        Test.stopTest();

        List<Account> agents = [
            SELECT Total_Loss_Vehicles_Yearly__c
            FROM Account
            WHERE Is_Agent__c = true
        ];
        Assert.areEqual(AGENT_COUNT, agents.size(), 'All agent accounts should still exist');
        for (Account agent : agents) {
            Assert.areEqual(0, agent.Total_Loss_Vehicles_Yearly__c, 'Agent yearly total should be reset to 0');
        }
    }

    /**
     * @description Verifies non-agent Accounts are left unchanged.
     */
    @IsTest
    static void leavesNonAgentsUnchanged() {
        Test.startTest();
        Database.executeBatch(new AnnualAgentResetBatch());
        Test.stopTest();

        List<Account> nonAgents = [
            SELECT Total_Loss_Vehicles_Yearly__c
            FROM Account
            WHERE Is_Agent__c = false
        ];
        Assert.areEqual(NON_AGENT_COUNT, nonAgents.size(), 'All non-agent accounts should still exist');
        for (Account nonAgent : nonAgents) {
            Assert.areEqual(STARTING_TOTAL, nonAgent.Total_Loss_Vehicles_Yearly__c, 'Non-agent yearly total should not change');
        }
    }

    /**
     * @description Verifies the job completes without errors, which also exercises finish().
     */
    @IsTest
    static void jobCompletesWithoutErrors() {
        Test.startTest();
        Id jobId = Database.executeBatch(new AnnualAgentResetBatch());
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        Assert.areEqual('Completed', job.Status, 'Batch job should complete');
        Assert.areEqual(0, job.NumberOfErrors, 'Batch job should have no errors');
    }

    /**
     * @description Verifies the batch runs cleanly when there are no agent Accounts.
     */
    @IsTest
    static void handlesNoAgents() {
        delete [SELECT Id FROM Account WHERE Is_Agent__c = true];

        Test.startTest();
        Id jobId = Database.executeBatch(new AnnualAgentResetBatch());
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        Assert.areEqual('Completed', job.Status, 'Batch job should complete with no agents');
        Assert.areEqual(0, job.NumberOfErrors, 'Batch job should have no errors');
    }
}
