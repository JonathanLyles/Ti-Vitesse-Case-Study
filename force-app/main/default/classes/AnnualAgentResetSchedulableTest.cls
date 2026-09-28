/**
 * @description Unit tests for AnnualAgentResetSchedulable.
 */
@IsTest
private class AnnualAgentResetSchedulableTest {

    // Midnight on January 1st every year
    private static final String CRON_EXPRESSION = '0 0 0 1 1 ?';

    /**
     * @description Verifies the job schedules with the expected cron expression.
     */
    @IsTest
    static void schedulesJob() {
        Test.startTest();
        Id jobId = System.schedule('Annual Agent Reset Test', CRON_EXPRESSION, new AnnualAgentResetSchedulable());
        Test.stopTest();

        CronTrigger cronJob = [
            SELECT CronExpression, TimesTriggered
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        Assert.areEqual(CRON_EXPRESSION, cronJob.CronExpression, 'Job should use the scheduled cron expression');
        Assert.areEqual(0, cronJob.TimesTriggered, 'Job should not have fired yet');
    }

    /**
     * @description Verifies execute() enqueues AnnualAgentResetBatch.
     */
    @IsTest
    static void executeEnqueuesBatch() {
        Test.startTest();
        new AnnualAgentResetSchedulable().execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Status
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'AnnualAgentResetBatch'
        ];
        Assert.areEqual(1, jobs.size(), 'execute() should enqueue one AnnualAgentResetBatch job');
        Assert.areEqual('Completed', jobs[0].Status, 'Batch job should complete');
    }
}
