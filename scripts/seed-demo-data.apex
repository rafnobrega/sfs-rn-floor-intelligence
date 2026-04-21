// Floor Intelligence - Demo Data Seed Script
// Run with: sf apex run -f scripts/seed-demo-data.apex -o <your-org-alias>
//
// Prerequisites:
//   1. Deploy the metadata first (custom fields, Apex, LWC)
//   2. Have at least one Account in the org
//   3. Have Products with codes EGM-NEPT-S, EGM-MARX-U9, EGM-HLX-XT, EGM-NEPT-D in the standard pricebook
//
// What this creates:
//   - 4 owned EGMs (parent assets) with health metrics, firmware, and child components
//   - 7 competitor machines across 4 brands
//   - AssetAttribute records for Last_Regulatory_Audit (2 overdue, 2 compliant)
//   - WarrantyTerm + AssetWarranty records (3 covered, 1 uncovered)

// --- CONFIG: Set your target Account name here ---
String accountName = 'CHANGE_ME';

List<Account> accts = [SELECT Id, Name FROM Account WHERE Name = :accountName LIMIT 1];
if (accts.isEmpty()) {
    System.debug('ERROR: Account "' + accountName + '" not found. Update the accountName variable.');
    return;
}
Account acct = accts[0];
System.debug('Seeding data for Account: ' + acct.Name + ' (' + acct.Id + ')');

// Clean up existing demo assets for this account
delete [SELECT Id FROM Asset WHERE AccountId = :acct.Id AND (Name LIKE 'EGM-%' OR Name LIKE 'COMP-%')];

// --- Owned EGMs (parent assets) ---
List<Asset> egms = new List<Asset>();
egms.add(new Asset(
    Name = 'EGM-1001', AccountId = acct.Id, SerialNumber = 'SN-EGM-1001', Status = 'Installed',
    InstallDate = Date.today().addYears(-2), IsCompetitorProduct = false,
    Cabinet_Model__c = 'Neptune Single', Asset_Class__c = 'Class III',
    Firmware_Version__c = '4.2.1', Software_Version__c = '8.1.0',
    Asset_Availability__c = 98.5, Asset_Reliability__c = 97.2,
    Location_on_Floor__c = 'Zone A - Row 3'
));
egms.add(new Asset(
    Name = 'EGM-1002', AccountId = acct.Id, SerialNumber = 'SN-EGM-1002', Status = 'Installed',
    InstallDate = Date.today().addYears(-1), IsCompetitorProduct = false,
    Cabinet_Model__c = 'Neptune Dual', Asset_Class__c = 'Class III',
    Firmware_Version__c = '4.1.0', Software_Version__c = '8.0.5',
    Asset_Availability__c = 95.0, Asset_Reliability__c = 93.8,
    Location_on_Floor__c = 'Zone A - Row 5'
));
egms.add(new Asset(
    Name = 'EGM-1003', AccountId = acct.Id, SerialNumber = 'SN-EGM-1003', Status = 'Installed',
    InstallDate = Date.today().addMonths(-18), IsCompetitorProduct = false,
    Cabinet_Model__c = 'MarsX Upright GEN9', Asset_Class__c = 'Class II',
    Firmware_Version__c = '3.8.5', Software_Version__c = '7.4.2',
    Asset_Availability__c = 97.0, Asset_Reliability__c = 96.5,
    Location_on_Floor__c = 'Zone B - Row 1'
));
egms.add(new Asset(
    Name = 'EGM-1004', AccountId = acct.Id, SerialNumber = 'SN-EGM-1004', Status = 'Installed',
    InstallDate = Date.today().addYears(-3), IsCompetitorProduct = false,
    Cabinet_Model__c = 'Helix XT', Asset_Class__c = 'Class III',
    Firmware_Version__c = '4.9.0', Software_Version__c = '6.2.1',
    Asset_Availability__c = 92.0, Asset_Reliability__c = 90.5,
    Location_on_Floor__c = 'Zone C - Row 2'
));
insert egms;
System.debug('Created ' + egms.size() + ' owned EGMs');

// --- Child components (3 per EGM = 12 total) ---
List<Asset> components = new List<Asset>();
String[] compTypes = new String[]{ 'Monitor', 'Bill Acceptor', 'Printer' };
Integer compNum = 1;
for (Asset egm : egms) {
    for (String compType : compTypes) {
        components.add(new Asset(
            Name = egm.Name + '-' + compType.replace(' ', ''),
            AccountId = acct.Id,
            ParentId = egm.Id,
            Status = 'Installed',
            IsCompetitorProduct = false
        ));
        compNum++;
    }
}
insert components;
System.debug('Created ' + components.size() + ' child components');

// --- Competitor machines ---
List<Asset> competitors = new List<Asset>();
competitors.add(new Asset(Name = 'COMP-2001', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'IGT', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 1'));
competitors.add(new Asset(Name = 'COMP-2002', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'IGT', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 1'));
competitors.add(new Asset(Name = 'COMP-2003', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'Light & Wonder', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 2'));
competitors.add(new Asset(Name = 'COMP-2004', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'Light & Wonder', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 2'));
competitors.add(new Asset(Name = 'COMP-2005', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'Konami', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 3'));
competitors.add(new Asset(Name = 'COMP-2006', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'Everi', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 3'));
competitors.add(new Asset(Name = 'COMP-2007', AccountId = acct.Id, IsCompetitorProduct = true, Description = 'AGS', Status = 'Installed', Location_on_Floor__c = 'Zone D - Row 4'));
insert competitors;
System.debug('Created ' + competitors.size() + ' competitor machines');

// --- Regulatory audit attributes ---
// Need AttributeDefinition for Last_Regulatory_Audit
List<AttributeDefinition> attrDefs = [SELECT Id FROM AttributeDefinition WHERE DeveloperName = 'Last_Regulatory_Audit' LIMIT 1];
if (attrDefs.isEmpty()) {
    System.debug('WARNING: AttributeDefinition "Last_Regulatory_Audit" not found. Create it manually:');
    System.debug('  Setup > Asset Attributes > New Definition > DeveloperName = Last_Regulatory_Audit, DataType = Date');
} else {
    Id attrDefId = attrDefs[0].Id;
    List<AssetAttribute> attrs = new List<AssetAttribute>();
    // EGM-1001 & 1002: overdue (18+ months ago)
    attrs.add(new AssetAttribute(AssetId = egms[0].Id, AttributeDefinitionId = attrDefId, AttributeValue = String.valueOf(Date.today().addMonths(-20))));
    attrs.add(new AssetAttribute(AssetId = egms[1].Id, AttributeDefinitionId = attrDefId, AttributeValue = String.valueOf(Date.today().addMonths(-15))));
    // EGM-1003 & 1004: compliant (recent)
    attrs.add(new AssetAttribute(AssetId = egms[2].Id, AttributeDefinitionId = attrDefId, AttributeValue = String.valueOf(Date.today().addMonths(-3))));
    attrs.add(new AssetAttribute(AssetId = egms[3].Id, AttributeDefinitionId = attrDefId, AttributeValue = String.valueOf(Date.today().addMonths(-6))));
    Database.updateImmediate(attrs);
    System.debug('Created ' + attrs.size() + ' regulatory audit attributes');
}

// --- Warranty coverage ---
// Create a WarrantyTerm first
WarrantyTerm wt = new WarrantyTerm(
    WarrantyTermName = 'Floor Intelligence Demo Warranty',
    IsActive = true,
    WarrantyDuration = 36,
    WarrantyUnitOfTime = 'Months',
    LaborCovered = true,
    PartsCovered = true,
    ExpensesCovered = false,
    Code = 'FI-DEMO-WT'
);
insert wt;

List<AssetWarranty> warranties = new List<AssetWarranty>();
// EGM-1001: warranty expiring in 25 days (triggers 30-day warning)
warranties.add(new AssetWarranty(AssetId = egms[0].Id, WarrantyTermId = wt.Id, StartDate = Date.today().addYears(-3), EndDate = Date.today().addDays(25)));
// EGM-1002: warranty expiring in 50 days (triggers 60-day warning)
warranties.add(new AssetWarranty(AssetId = egms[1].Id, WarrantyTermId = wt.Id, StartDate = Date.today().addYears(-2), EndDate = Date.today().addDays(50)));
// EGM-1003: warranty good for another year
warranties.add(new AssetWarranty(AssetId = egms[2].Id, WarrantyTermId = wt.Id, StartDate = Date.today().addYears(-1), EndDate = Date.today().addYears(1)));
// EGM-1004: no warranty (uncovered)
insert warranties;
System.debug('Created ' + warranties.size() + ' warranties (EGM-1004 intentionally uncovered)');

System.debug('=== SEED COMPLETE ===');
System.debug('  Owned EGMs: ' + egms.size());
System.debug('  Components: ' + components.size());
System.debug('  Competitors: ' + competitors.size());
System.debug('  Expected health score: ~96.1%');
System.debug('  Warranty coverage: 75% (3/4)');
System.debug('  Overdue audits: 2');
System.debug('  Outdated firmware: 2 (EGM-1002 Neptune Dual v4.1.0, EGM-1004 Helix XT v4.9.0)');
