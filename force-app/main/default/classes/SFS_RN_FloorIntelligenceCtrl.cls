public with sharing class SFS_RN_FloorIntelligenceCtrl {

    private static final Map<String, String> CURRENT_FIRMWARE = new Map<String, String>{
        'Neptune Single' => '4.2.1',
        'Neptune Dual' => '4.2.1',
        'MarsX Upright GEN9' => '3.8.5',
        'Helix XT' => '5.0.2'
    };

    private static final Integer AUDIT_OVERDUE_MONTHS = 12;

    private static final Map<String, String> BRAND_TO_PRODUCT = new Map<String, String>{
        'IGT' => 'EGM-NEPT-S',
        'Light & Wonder' => 'EGM-MARX-U9',
        'Konami' => 'EGM-HLX-XT',
        'Everi' => 'EGM-NEPT-D',
        'AGS' => 'EGM-NEPT-S'
    };

    @AuraEnabled(cacheable=true)
    public static FloorIntelligence getFloorIntelligence(Id accountId) {
        FloorIntelligence result = new FloorIntelligence();
        Date today = Date.today();

        List<Asset> ownedAssets = [
            SELECT Id, Name, SerialNumber, Cabinet_Model__c, Asset_Class__c,
                   Firmware_Version__c, Software_Version__c, Status, InstallDate,
                   Asset_Availability__c, Asset_Reliability__c, AverageUptimePerDay
            FROM Asset
            WHERE AccountId = :accountId
            AND ParentId = null
            AND IsCompetitorProduct = false
            ORDER BY Name
        ];

        result.totalEgms = ownedAssets.size();
        result.totalComponents = [
            SELECT COUNT() FROM Asset
            WHERE AccountId = :accountId AND ParentId != null
        ];

        Map<String, Integer> modelMap = new Map<String, Integer>();
        Map<String, Integer> classMap = new Map<String, Integer>();
        Decimal sumAvail = 0, sumReliab = 0, sumUptime = 0;
        Integer healthN = 0;

        for (Asset a : ownedAssets) {
            String model = a.Cabinet_Model__c != null ? a.Cabinet_Model__c : 'Other';
            modelMap.put(model, (modelMap.get(model) != null ? modelMap.get(model) : 0) + 1);

            String cls = a.Asset_Class__c != null ? a.Asset_Class__c : 'Unclassified';
            classMap.put(cls, (classMap.get(cls) != null ? classMap.get(cls) : 0) + 1);

            if (a.Asset_Availability__c != null) {
                sumAvail += a.Asset_Availability__c;
                sumReliab += (a.Asset_Reliability__c != null ? a.Asset_Reliability__c : 0);
                sumUptime += (a.AverageUptimePerDay != null ? a.AverageUptimePerDay : 0);
                healthN++;
            }

            if (a.Firmware_Version__c != null && CURRENT_FIRMWARE.containsKey(model)) {
                if (a.Firmware_Version__c != CURRENT_FIRMWARE.get(model)) {
                    AssetFlag flag = new AssetFlag();
                    flag.assetId = a.Id;
                    flag.assetName = a.Name;
                    flag.flagType = 'Firmware';
                    flag.detail = 'v' + a.Firmware_Version__c + ' - current is v' + CURRENT_FIRMWARE.get(model);
                    result.outdatedAssets.add(flag);
                }
            }
        }

        result.modelBreakdown = toBreakdown(modelMap);
        result.classBreakdown = toBreakdown(classMap);
        result.outdatedCount = result.outdatedAssets.size();
        result.currentCount = result.totalEgms - result.outdatedCount;

        if (healthN > 0) {
            result.avgAvailability = (sumAvail / healthN).setScale(1, RoundingMode.HALF_UP);
            result.avgReliability = (sumReliab / healthN).setScale(1, RoundingMode.HALF_UP);
            Decimal uptimeNorm = (sumUptime / healthN / 24) * 100;
            result.healthScore = (
                (result.avgAvailability * 0.4) +
                (result.avgReliability * 0.4) +
                (uptimeNorm * 0.2)
            ).setScale(1, RoundingMode.HALF_UP);
        }

        Map<String, Integer> competitorMap = new Map<String, Integer>();
        for (Asset a : [
            SELECT Id, Description
            FROM Asset
            WHERE AccountId = :accountId AND ParentId = null AND IsCompetitorProduct = true
        ]) {
            String brand = a.Description != null ? a.Description : 'Unknown';
            competitorMap.put(brand, (competitorMap.get(brand) != null ? competitorMap.get(brand) : 0) + 1);
            result.competitorCount++;
        }
        result.competitorBreakdown = toBreakdown(competitorMap);

        Set<Id> coveredIds = new Set<Id>();
        for (AssetWarranty w : [
            SELECT AssetId, EndDate
            FROM AssetWarranty
            WHERE Asset.AccountId = :accountId AND Asset.ParentId = null AND EndDate >= :today
        ]) {
            coveredIds.add(w.AssetId);
            Integer daysLeft = today.daysBetween(w.EndDate);
            if (daysLeft <= 30) result.warrantyExp30++;
            else if (daysLeft <= 60) result.warrantyExp60++;
            else if (daysLeft <= 90) result.warrantyExp90++;
        }
        result.warrantyCovered = coveredIds.size();
        result.warrantyUncovered = result.totalEgms - result.warrantyCovered;
        result.warrantyCoveragePct = result.totalEgms > 0
            ? ((Decimal) result.warrantyCovered / result.totalEgms * 100).setScale(0, RoundingMode.HALF_UP)
            : 0;

        Date overdueDate = today.addMonths(-AUDIT_OVERDUE_MONTHS);
        for (AssetAttribute attr : [
            SELECT AssetId, Asset.Name, AttributeValue
            FROM AssetAttribute
            WHERE Asset.AccountId = :accountId
            AND Asset.ParentId = null
            AND AttributeDefinition.Name = 'Last_Regulatory_Audit'
        ]) {
            try {
                Date auditDate = Date.valueOf(attr.AttributeValue);
                if (auditDate < overdueDate) {
                    AssetFlag flag = new AssetFlag();
                    flag.assetId = attr.AssetId;
                    flag.assetName = attr.Asset.Name;
                    flag.flagType = 'Regulatory';
                    flag.detail = 'Last audit: ' + attr.AttributeValue;
                    result.overdueAudits.add(flag);
                } else {
                    result.compliantCount++;
                }
            } catch (Exception e) {
                // skip malformed dates
            }
        }
        result.overdueCount = result.overdueAudits.size();

        for (AggregateResult ar : [
            SELECT Priority, COUNT(Id) cnt
            FROM Case
            WHERE AccountId = :accountId AND IsClosed = false
            GROUP BY Priority
        ]) {
            BreakdownItem item = new BreakdownItem();
            item.label = (String) ar.get('Priority');
            item.count = (Integer) ar.get('cnt');
            result.openCases += item.count;
            result.casePriority.add(item);
        }

        for (AggregateResult ar : [
            SELECT Priority, COUNT(Id) cnt
            FROM WorkOrder
            WHERE AccountId = :accountId
            AND Status != 'Closed' AND Status != 'Completed' AND Status != 'Canceled'
            GROUP BY Priority
        ]) {
            BreakdownItem item = new BreakdownItem();
            item.label = (String) ar.get('Priority');
            item.count = (Integer) ar.get('cnt');
            result.openWorkOrders += item.count;
            result.woPriority.add(item);
        }

        List<Opportunity> existingOpps = [
            SELECT Id, Name, Amount, StageName
            FROM Opportunity
            WHERE AccountId = :accountId
            AND Name LIKE '%Competitor Replacement%'
            AND IsClosed = false
            LIMIT 1
        ];
        if (!existingOpps.isEmpty()) {
            result.hasReplacementOpp = true;
            result.replacementOppId = existingOpps[0].Id;
            result.replacementOppStage = existingOpps[0].StageName;
            result.replacementOppAmount = existingOpps[0].Amount;
        }

        return result;
    }

    @AuraEnabled
    public static Id createReplacementOpportunity(Id accountId) {
        Account acct = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];

        List<Opportunity> existing = [
            SELECT Id FROM Opportunity
            WHERE AccountId = :accountId
            AND Name LIKE '%Competitor Replacement%'
            AND IsClosed = false
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        List<Asset> competitors = [
            SELECT Id, Name, Description
            FROM Asset
            WHERE AccountId = :accountId AND ParentId = null AND IsCompetitorProduct = true
        ];

        List<Pricebook2> stdPbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        Id stdPbId = !stdPbs.isEmpty() ? stdPbs[0].Id : Test.isRunningTest() ? Test.getStandardPricebookId() : null;

        Map<String, PricebookEntry> pbeByCode = new Map<String, PricebookEntry>();
        if (stdPbId != null) {
            for (PricebookEntry pbe : [
                SELECT Id, Product2.Name, Product2.ProductCode, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :stdPbId AND IsActive = true
                AND Product2.ProductCode LIKE 'EGM-%'
            ]) {
                pbeByCode.put(pbe.Product2.ProductCode, pbe);
            }
        }

        Opportunity opp = new Opportunity(
            AccountId = accountId,
            Name = acct.Name + ' - Competitor Replacement',
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(3),
            Description = competitors.size() + ' competitor machines identified for replacement.'
        );
        if (stdPbId != null) {
            opp.Pricebook2Id = stdPbId;
        }
        insert opp;

        List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
        for (Asset comp : competitors) {
            String brand = comp.Description != null ? comp.Description : 'Unknown';
            String productCode = BRAND_TO_PRODUCT.get(brand);
            if (productCode != null && pbeByCode.containsKey(productCode)) {
                PricebookEntry pbe = pbeByCode.get(productCode);
                lineItems.add(new OpportunityLineItem(
                    OpportunityId = opp.Id,
                    PricebookEntryId = pbe.Id,
                    Quantity = 1,
                    UnitPrice = pbe.UnitPrice,
                    Description = 'Replace ' + comp.Name + ' (' + brand + ') with ' + pbe.Product2.Name
                ));
            }
        }

        if (!lineItems.isEmpty()) {
            insert lineItems;
        }

        return opp.Id;
    }

    private static List<BreakdownItem> toBreakdown(Map<String, Integer> counts) {
        List<BreakdownItem> items = new List<BreakdownItem>();
        for (String key : counts.keySet()) {
            BreakdownItem item = new BreakdownItem();
            item.label = key;
            item.count = counts.get(key);
            items.add(item);
        }
        items.sort();
        return items;
    }

    public class FloorIntelligence {
        @AuraEnabled public Integer totalEgms = 0;
        @AuraEnabled public Integer totalComponents = 0;
        @AuraEnabled public List<BreakdownItem> modelBreakdown = new List<BreakdownItem>();
        @AuraEnabled public List<BreakdownItem> classBreakdown = new List<BreakdownItem>();

        @AuraEnabled public Decimal healthScore;
        @AuraEnabled public Decimal avgAvailability;
        @AuraEnabled public Decimal avgReliability;

        @AuraEnabled public Integer warrantyCovered = 0;
        @AuraEnabled public Integer warrantyUncovered = 0;
        @AuraEnabled public Decimal warrantyCoveragePct = 0;
        @AuraEnabled public Integer warrantyExp30 = 0;
        @AuraEnabled public Integer warrantyExp60 = 0;
        @AuraEnabled public Integer warrantyExp90 = 0;

        @AuraEnabled public Integer overdueCount = 0;
        @AuraEnabled public Integer compliantCount = 0;
        @AuraEnabled public List<AssetFlag> overdueAudits = new List<AssetFlag>();

        @AuraEnabled public Integer outdatedCount = 0;
        @AuraEnabled public Integer currentCount = 0;
        @AuraEnabled public List<AssetFlag> outdatedAssets = new List<AssetFlag>();

        @AuraEnabled public Integer competitorCount = 0;
        @AuraEnabled public List<BreakdownItem> competitorBreakdown = new List<BreakdownItem>();
        @AuraEnabled public Boolean hasReplacementOpp = false;
        @AuraEnabled public Id replacementOppId;
        @AuraEnabled public String replacementOppStage;
        @AuraEnabled public Decimal replacementOppAmount;

        @AuraEnabled public Integer openCases = 0;
        @AuraEnabled public Integer openWorkOrders = 0;
        @AuraEnabled public List<BreakdownItem> casePriority = new List<BreakdownItem>();
        @AuraEnabled public List<BreakdownItem> woPriority = new List<BreakdownItem>();
    }

    public class BreakdownItem implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        public Integer compareTo(Object other) {
            return ((BreakdownItem) other).count - this.count;
        }
    }

    public class AssetFlag {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String flagType;
        @AuraEnabled public String detail;
    }
}
