import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFloorIntelligence from '@salesforce/apex/SFS_RN_FloorIntelligenceCtrl.getFloorIntelligence';
import createReplacementOpportunity from '@salesforce/apex/SFS_RN_FloorIntelligenceCtrl.createReplacementOpportunity';

export default class SfsRnFloorIntelligence extends LightningElement {
    @api recordId;
    data;
    error;
    isLoading = true;
    isCreatingOpp = false;
    isExpanded = true;
    _wiredResult;

    @wire(getFloorIntelligence, { accountId: '$recordId' })
    wiredData(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.data = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error.body?.message || 'Unable to load asset data';
            this.data = undefined;
        }
    }

    get collapseIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleCollapse() {
        this.isExpanded = !this.isExpanded;
    }

    get hasData() {
        return this.data && this.data.totalEgms > 0;
    }

    get noData() {
        return this.data && this.data.totalEgms === 0;
    }

    get healthDisplay() {
        return this.data?.healthScore != null ? this.data.healthScore : '--';
    }

    get healthClass() {
        const s = this.data?.healthScore;
        if (s == null) return 'stat-card';
        if (s >= 90) return 'stat-card stat-good';
        if (s >= 75) return 'stat-card stat-warn';
        return 'stat-card stat-crit';
    }

    get warrantyClass() {
        const p = this.data?.warrantyCoveragePct;
        if (p == null) return 'stat-card';
        if (p >= 80) return 'stat-card stat-good';
        if (p >= 50) return 'stat-card stat-warn';
        return 'stat-card stat-crit';
    }

    get auditClass() {
        const c = this.data?.overdueCount;
        if (c === 0) return 'stat-card stat-good';
        if (c <= 2) return 'stat-card stat-warn';
        return 'stat-card stat-crit';
    }

    get firmwareClass() {
        const c = this.data?.outdatedCount;
        if (c === 0) return 'stat-card stat-good';
        if (c <= 2) return 'stat-card stat-warn';
        return 'stat-card stat-crit';
    }

    get hasCompetitors() {
        return this.data?.competitorCount > 0;
    }

    get hasReplacementOpp() {
        return this.data?.hasReplacementOpp === true;
    }

    get replacementOppAmount() {
        const amt = this.data?.replacementOppAmount;
        if (amt == null) return '';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(amt);
    }

    get attentionItems() {
        if (!this.data) return [];
        const items = [];
        if (this.data.overdueAudits) {
            this.data.overdueAudits.forEach(a => {
                items.push({
                    key: a.assetId + '-reg',
                    assetId: a.assetId,
                    assetName: a.assetName,
                    icon: 'utility:alert',
                    issue: this._formatAuditDetail(a.detail),
                    badgeClass: 'badge badge-red',
                    badgeLabel: 'Audit'
                });
            });
        }
        if (this.data.outdatedAssets) {
            this.data.outdatedAssets.forEach(a => {
                items.push({
                    key: a.assetId + '-fw',
                    assetId: a.assetId,
                    assetName: a.assetName,
                    icon: 'utility:warning',
                    issue: a.detail,
                    badgeClass: 'badge badge-orange',
                    badgeLabel: 'Firmware'
                });
            });
        }
        return items;
    }

    get hasAttentionItems() {
        return this.attentionItems.length > 0;
    }

    get totalServiceIssues() {
        return (this.data?.openCases || 0) + (this.data?.openWorkOrders || 0);
    }

    get serviceClass() {
        const t = this.totalServiceIssues;
        if (t === 0) return 'stat-card stat-good';
        if (t <= 3) return 'stat-card stat-warn';
        return 'stat-card stat-crit';
    }

    handleCreateOpportunity() {
        this.isCreatingOpp = true;
        createReplacementOpportunity({ accountId: this.recordId })
            .then((oppId) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Replacement Opportunity Created',
                    message: 'Opportunity with line items has been generated.',
                    variant: 'success'
                }));
                window.open('/' + oppId, '_blank');
                return refreshApex(this._wiredResult);
            })
            .catch((err) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: err.body?.message || 'Failed to create opportunity',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isCreatingOpp = false;
            });
    }

    navigateToOpp() {
        if (this.data?.replacementOppId) {
            window.open('/' + this.data.replacementOppId, '_blank');
        }
    }

    _formatAuditDetail(detail) {
        const match = detail?.match(/(\d{4}-\d{2}-\d{2})/);
        if (match) {
            const d = new Date(match[1] + 'T00:00:00');
            const formatted = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
            return 'Last audit: ' + formatted;
        }
        return detail;
    }

    navigateToAsset(event) {
        const assetId = event.currentTarget.dataset.id;
        window.open('/' + assetId, '_blank');
    }
}
