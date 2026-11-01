-- Cleared customer items (BSAD): documents already matched against each other.
-- Same shape as erp_open_items plus the clearing date and the clearing document.
-- Several documents share the same clearing document: that is how a payment is tied to invoices.
select
    BUKRS as company_code,
    try_cast(KUNNR as int) as customer_id,
    GJAHR as fiscal_year,
    BELNR as document_number,
    BUZEI as line_item,
    {{ sap_date('BUDAT') }} as posting_date,
    {{ sap_date('BLDAT') }} as document_date,
    BLART as document_type,
    SHKZG as debit_credit,
    DMBTR as amount,
    WAERS as currency,
    {{ sap_date('ZFBDT') }} as baseline_date,
    ZBD1T as payment_days,
    {{ clean_text('XBLNR') }} as reference,
    {{ clean_text('VBELN') }} as billing_doc,
    ZTERM as payment_terms_code,
    {{ sap_date('AUGDT') }} as clearing_date,
    AUGBL as clearing_document
from {{ source('bronze', 'erp_bsad') }}
