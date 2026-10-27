-- Cleared customer items (BSAD): documents already matched against each other.
-- Same shape as erp_open_items plus the clearing date and the clearing document.
-- Several documents share the same clearing document: that is how a payment is tied to invoices.
select
    BUKRS as company_code,
    try_cast(KUNNR as int) as customer_id,
    GJAHR as fiscal_year,
    BELNR as document_number,
    BUZEI as line_item,
    try_convert(date, BUDAT, 112) as posting_date,
    try_convert(date, BLDAT, 112) as document_date,
    BLART as document_type,
    SHKZG as debit_credit,
    DMBTR as amount,
    WAERS as currency,
    try_convert(date, ZFBDT, 112) as baseline_date,
    ZBD1T as payment_days,
    nullif(ltrim(rtrim(XBLNR)), '') as reference,
    nullif(ltrim(rtrim(VBELN)), '') as billing_doc,
    ZTERM as payment_terms_code,
    try_convert(date, AUGDT, 112) as clearing_date,
    AUGBL as clearing_document
from {{ source('bronze', 'erp_bsad') }}
