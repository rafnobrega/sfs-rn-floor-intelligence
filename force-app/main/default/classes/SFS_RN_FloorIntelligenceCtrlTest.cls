@IsTest
private class SFS_RN_FloorIntelligenceCtrlTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Test Casino');
        insert acct;

        Product2 prod = new Product2(Name = 'Test EGM', IsActive = true);
        insert prod;

        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < 5; i++) {
            assets.add(new Asset(
                Name = 'EGM-TEST-' + i,
                AccountId = acct.Id,
                Product2Id = prod.Id,
                Status = 'Installed',
                SerialNumber = 'SN-' + i,
                Cabinet_Model__c = (Math.mod(i, 2) == 0 ? 'Neptune Single' : 'MarsX Upright GEN9'),
                Asset_Class__c = 'Class III',
                Firmware_Version__c = (i == 0 ? '3.1.0' : (Math.mod(i, 2) == 0 ? '4.2.1' : '3.8.5')),
                IsCompetitorProduct = false
            ));
        }

        assets.add(new Asset(
            Name = 'IGT-COMPETITOR-1',
            AccountId = acct.Id,
            Status = 'Installed',
            IsCompetitorProduct = true,
            Description = 'IGT'
        ));
        assets.add(new Asset(
            Name = 'KONAMI-COMPETITOR-1',
            AccountId = acct.Id,
            Status = 'Installed',
            IsCompetitorProduct = true,
            Description = 'Konami'
        ));
        insert assets;

        Asset parentEgm = [SELECT Id FROM Asset WHERE Name = 'EGM-TEST-0' LIMIT 1];
        List<Asset> components = new List<Asset>();
        for (Integer i = 0; i < 3; i++) {
            components.add(new Asset(
                Name = 'Component-' + i,
                AccountId = acct.Id,
                ParentId = parentEgm.Id,
                Status = 'Installed'
            ));
        }
        insert components;
    }

    @IsTest
    static void testGetFloorIntelligence() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Casino' LIMIT 1];

        Test.startTest();
        SFS_RN_FloorIntelligenceCtrl.FloorIntelligence result =
            SFS_RN_FloorIntelligenceCtrl.getFloorIntelligence(acct.Id);
        Test.stopTest();

        System.assertEquals(5, result.totalEgms, 'Should have 5 owned EGMs');
        System.assertEquals(3, result.totalComponents, 'Should have 3 components');
        System.assertEquals(2, result.competitorCount, 'Should have 2 competitor machines');
        System.assert(result.modelBreakdown.size() > 0, 'Should have model breakdown');
        System.assert(result.classBreakdown.size() > 0, 'Should have class breakdown');
        System.assertEquals(1, result.outdatedCount, 'EGM-TEST-0 has outdated firmware');
        System.assertEquals(4, result.currentCount, 'Four EGMs should be current');
        System.assert(result.openCases >= 0, 'Open cases should be non-negative');
        System.assert(result.openWorkOrders >= 0, 'Open WOs should be non-negative');
    }

    @IsTest
    static void testEmptyAccount() {
        Account acct = new Account(Name = 'Empty Casino');
        insert acct;

        Test.startTest();
        SFS_RN_FloorIntelligenceCtrl.FloorIntelligence result =
            SFS_RN_FloorIntelligenceCtrl.getFloorIntelligence(acct.Id);
        Test.stopTest();

        System.assertEquals(0, result.totalEgms);
        System.assertEquals(0, result.competitorCount);
        System.assertEquals(0, result.openCases);
    }

    @IsTest
    static void testCreateReplacementOpportunity() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Casino' LIMIT 1];

        Test.startTest();
        Id oppId = SFS_RN_FloorIntelligenceCtrl.createReplacementOpportunity(acct.Id);
        Test.stopTest();

        System.assertNotEquals(null, oppId, 'Should return an Opportunity Id');
        Opportunity opp = [SELECT Name, StageName, AccountId FROM Opportunity WHERE Id = :oppId];
        System.assertEquals(acct.Id, opp.AccountId);
        System.assert(opp.Name.contains('Competitor Replacement'), 'Name should contain Competitor Replacement');
    }

    @IsTest
    static void testCreateReplacementOpportunityIdempotent() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Casino' LIMIT 1];

        Test.startTest();
        Id firstId = SFS_RN_FloorIntelligenceCtrl.createReplacementOpportunity(acct.Id);
        Id secondId = SFS_RN_FloorIntelligenceCtrl.createReplacementOpportunity(acct.Id);
        Test.stopTest();

        System.assertEquals(firstId, secondId, 'Should return same Opportunity on duplicate call');
    }

    @IsTest
    static void testReplacementOppIndicator() {
        Account acct = [SELECT Id, Name FROM Account WHERE Name = 'Test Casino' LIMIT 1];
        insert new Opportunity(
            AccountId = acct.Id,
            Name = acct.Name + ' - Competitor Replacement',
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(3)
        );

        Test.startTest();
        SFS_RN_FloorIntelligenceCtrl.FloorIntelligence result =
            SFS_RN_FloorIntelligenceCtrl.getFloorIntelligence(acct.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasReplacementOpp, 'Should detect existing replacement opp');
        System.assertNotEquals(null, result.replacementOppId, 'Should have opp Id');
    }
}
