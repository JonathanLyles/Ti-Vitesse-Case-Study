public with sharing class AnnualAgentResetSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        AnnualAgentResetBatch batch = new AnnualAgentResetBatch();
        Database.executeBatch(batch);
    }
}
