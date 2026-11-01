-- Open customer items (BSID): invoices not yet paid, plus payments not yet applied.
-- DMBTR is always positive; debit_credit tells the direction (S = debit/charge, H = credit/payment).
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
    ZTERM as payment_terms_code
from {{ source('bronze', 'erp_bsid') }}
