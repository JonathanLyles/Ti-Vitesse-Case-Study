/**
 * @description Unit and load tests for MonthlyAgentCommissionCalculationBatch.
 *              Each test builds its own data, because the load test uses most of
 *              the 10,000 DML row limit for a single transaction.
 */
@IsTest
private class MonthlyAgentCommissionBatchTest {

    // Batch Apex tests can only run one execute() call, so the load test
    // fills exactly one chunk at the default batch size.
    private static final Integer LOAD_AGENT_COUNT = 200;
    private static final Integer LOAD_INVOICES_PER_AGENT = 45;

    private static final Datetime LAST_MONTH_DATE = middayOn(Date.today().toStartOfMonth().addMonths(-1).addDays(14));
    private static final Datetime THIS_MONTH_DATE = middayOn(Date.today().toStartOfMonth());
    private static final Datetime TWO_MONTHS_AGO_DATE = middayOn(Date.today().toStartOfMonth().addMonths(-2).addDays(14));

    private static Case supportCase;

    /**
     * @description Verifies commission = sum of last month's invoice amounts x commission rate %,
     *              including a fractional rate.
     */
    @IsTest
    static void calculatesCommissionFromLastMonthInvoices() {
        Account agentA = createAgent('Agent A', 10);
        Account agentB = createAgent('Agent B', 2.5);
        insert new List<Account>{ agentA, agentB };
        insert new List<Invoice__c>{
            createInvoice(agentA, 1000, LAST_MONTH_DATE),
            createInvoice(agentA, 500, LAST_MONTH_DATE),
            createInvoice(agentB, 2000, LAST_MONTH_DATE)
        };

        runBatch();

        Assert.areEqual(150, getCommission(agentA.Id), '10% of (1000 + 500) should be 150');
        Assert.areEqual(50, getCommission(agentB.Id), '2.5% of 2000 should be 50');
    }

    /**
     * @description Verifies only invoices dated last month count toward the commission.
     */
    @IsTest
    static void ignoresInvoicesOutsideLastMonth() {
        Account agent = createAgent('Agent', 10);
        insert agent;
        insert new List<Invoice__c>{
            createInvoice(agent, 1000, LAST_MONTH_DATE),
            createInvoice(agent, 5000, THIS_MONTH_DATE),
            createInvoice(agent, 7000, TWO_MONTHS_AGO_DATE)
        };

        runBatch();

        Assert.areEqual(100, getCommission(agent.Id), 'Only the 1000 invoiced last month should count');
    }

    /**
     * @description Verifies an Agent with no commission rate gets a commission of 0.
     */
    @IsTest
    static void treatsMissingRateAsZero() {
        Account agent = createAgent('Agent Without Rate', null);
        insert agent;
        insert createInvoice(agent, 1000, LAST_MONTH_DATE);

        runBatch();

        Assert.areEqual(0, getCommission(agent.Id), 'An Agent with no rate should earn no commission');
    }

    /**
     * @description Verifies Accounts outside the batch scope are not changed: Agents with
     *              no invoices last month, and non-Agent Accounts.
     */
    @IsTest
    static void leavesOutOfScopeAccountsUnchanged() {
        Account inactiveAgent = createAgent('Inactive Agent', 10);
        inactiveAgent.Monthly_Commission__c = 999;
        Account nonAgent = createAgent('Non-Agent', 10);
        nonAgent.Is_Agent__c = false;
        nonAgent.Monthly_Commission__c = 999;
        insert new List<Account>{ inactiveAgent, nonAgent };
        insert new List<Invoice__c>{
            createInvoice(inactiveAgent, 1000, THIS_MONTH_DATE),
            createInvoice(nonAgent, 1000, LAST_MONTH_DATE)
        };

        runBatch();

        Assert.areEqual(999, getCommission(inactiveAgent.Id), 'Agent with no invoices last month should not change');
        Assert.areEqual(999, getCommission(nonAgent.Id), 'Non-Agent Account should not change');
    }

    /**
     * @description Load test: a full chunk of 200 Agents with 45 invoices each (9,000 invoices),
     *              using varied rates and amounts. Verifies every Agent's commission and that the
     *              job completes without errors.
     */
    @IsTest
    static void calculatesCommissionForFullChunkUnderLoad() {
        List<Account> agents = new List<Account>();
        for (Integer i = 0; i < LOAD_AGENT_COUNT; i++) {
            agents.add(createAgent('Load Agent ' + i, Math.mod(i, 20) + 1));
        }
        insert agents;

        Map<Id, Decimal> expectedCommissions = new Map<Id, Decimal>();
        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Account agent : agents) {
            Decimal total = 0;
            for (Integer j = 0; j < LOAD_INVOICES_PER_AGENT; j++) {
                Decimal amount = 100 * (Math.mod(j, 5) + 1);
                invoices.add(createInvoice(agent, amount, LAST_MONTH_DATE));
                total += amount;
            }
            expectedCommissions.put(agent.Id, total * agent.Commission_Rate__c / 100);
        }
        insert invoices;

        Id jobId = runBatch();

        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        Assert.areEqual('Completed', job.Status, 'Batch job should complete');
        Assert.areEqual(0, job.NumberOfErrors, 'Batch job should have no errors');

        List<Account> results = [
            SELECT Id, Monthly_Commission__c
            FROM Account
            WHERE Id IN :expectedCommissions.keySet()
        ];
        Assert.areEqual(LOAD_AGENT_COUNT, results.size(), 'All load test Agents should exist');
        for (Account result : results) {
            Assert.areEqual(expectedCommissions.get(result.Id), result.Monthly_Commission__c,
                'Commission should match the expected value for Agent ' + result.Id);
        }
    }

    /**
     * @description Verifies the confirmation email goes to the system admin who submitted the job
     *              and reports the job's outcome.
     */
    @IsTest
    static void sendsConfirmationToSubmittingAdmin() {
        User admin = createSystemAdmin();
        Account agent = createAgent('Agent', 10);
        insert agent;
        insert createInvoice(agent, 1000, LAST_MONTH_DATE);

        Id jobId;
        System.runAs(admin) {
            jobId = runBatch();
        }

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedById
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        Assert.areEqual(admin.Id, job.CreatedById, 'Job should be submitted by the admin');

        Messaging.SingleEmailMessage mail = MonthlyAgentCommissionCalculationBatch.buildConfirmationEmail(job);
        Assert.areEqual(admin.Id, mail.getTargetObjectId(), 'Email should go to the admin who submitted the job');
        Assert.isFalse(mail.getSaveAsActivity(), 'Email to a User must not be saved as an activity');
        Assert.isTrue(mail.getSubject().contains('Completed'), 'Subject should include the job status');
        Assert.isTrue(mail.getPlainTextBody().contains('Batches with errors: 0'), 'Body should report the error count');
    }

    /**
     * @description Verifies the confirmation email warns the admin when some batches failed.
     *              AsyncApexJob fields are read-only, so the failed job is built from JSON.
     */
    @IsTest
    static void confirmationWarnsWhenBatchesFail() {
        AsyncApexJob failedJob = (AsyncApexJob) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Status' => 'Completed',
            'NumberOfErrors' => 2,
            'JobItemsProcessed' => 10,
            'TotalJobItems' => 10,
            'CreatedById' => UserInfo.getUserId()
        }), AsyncApexJob.class);

        Messaging.SingleEmailMessage mail = MonthlyAgentCommissionCalculationBatch.buildConfirmationEmail(failedJob);

        Assert.isTrue(mail.getPlainTextBody().contains('Batches with errors: 2'), 'Body should report the error count');
        Assert.isTrue(mail.getPlainTextBody().contains('were not updated'), 'Body should warn that some commissions were not updated');
    }

    // ---------- Helpers ----------

    private static Id runBatch() {
        Test.startTest();
        Id jobId = Database.executeBatch(new MonthlyAgentCommissionCalculationBatch());
        Test.stopTest();
        return jobId;
    }

    private static Decimal getCommission(Id accountId) {
        return [SELECT Monthly_Commission__c FROM Account WHERE Id = :accountId].Monthly_Commission__c;
    }

    private static Account createAgent(String name, Decimal commissionRate) {
        return new Account(Name = name, Is_Agent__c = true, Commission_Rate__c = commissionRate);
    }

    private static Invoice__c createInvoice(Account agent, Decimal amount, Datetime invoiceDate) {
        Case relatedCase = getSupportCase();
        return new Invoice__c(
            Account__c = agent.Id,
            Case__c = relatedCase.Id,
            Contact__c = relatedCase.ContactId,
            Invoice_Date__c = invoiceDate,
            Amount_without_VAT__c = amount
        );
    }

    /**
     * @description Invoices require a Case and a Contact. One shared Case (and its Contact) is
     *              created per test, on a separate customer Account outside the batch scope.
     */
    private static Case getSupportCase() {
        if (supportCase == null) {
            Account customer = new Account(Name = 'Test Customer', Is_Agent__c = false);
            insert customer;
            Contact contact = new Contact(LastName = 'Test Contact', AccountId = customer.Id);
            insert contact;
            supportCase = new Case(
                AccountId = customer.Id,
                ContactId = contact.Id,
                Date_and_Time_of_Incident__c = System.now().addDays(-1)
            );
            insert supportCase;
        }
        return supportCase;
    }

    private static User createSystemAdmin() {
        User admin;
        // Run as the current user to avoid mixed DML errors between User and other records
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator'];
            String uniqueKey = String.valueOf(Datetime.now().getTime());
            admin = new User(
                ProfileId = adminProfile.Id,
                LastName = 'Commission Admin',
                Alias = 'cadmin',
                Email = 'commission.admin@example.com',
                Username = 'commission.admin.' + uniqueKey + '@example.com',
                TimeZoneSidKey = UserInfo.getTimeZone().getID(),
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            insert admin;
        }
        return admin;
    }

    private static Datetime middayOn(Date day) {
        return Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
    }
}
