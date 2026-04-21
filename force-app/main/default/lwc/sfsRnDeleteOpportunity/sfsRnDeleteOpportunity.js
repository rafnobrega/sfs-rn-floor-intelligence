import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { deleteRecord, getRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

const FIELDS = ['Opportunity.AccountId'];

export default class SfsRnDeleteOpportunity extends NavigationMixin(LightningElement) {
    @api recordId;
    accountId;
    isDeleting = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredOpp({ data }) {
        if (data) {
            this.accountId = data.fields.AccountId.value;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleDelete() {
        this.isDeleting = true;
        deleteRecord(this.recordId)
            .then(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
                if (this.accountId) {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: this.accountId,
                            objectApiName: 'Account',
                            actionName: 'view'
                        }
                    });
                }
            })
            .catch(() => {
                this.isDeleting = false;
            });
    }
}
