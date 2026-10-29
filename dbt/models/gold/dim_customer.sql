SELECT
    c.customer_id,
    c.customer_name,
    c.tax_id,
    CASE WHEN c.account_group = 'DELV' THEN 1 ELSE 0 END AS is_delivery_account,
    cr.credit_limit,
    cr.is_credit_blocked,
    cr.risk_class,
    pt.net_days AS payment_terms_days,
    d.district_name,
    e.employee_name AS collector_name
FROM {{ ref('erp_customers') }} c
LEFT JOIN {{ ref('erp_customer_credit') }} cr
    ON c.customer_id = cr.customer_id
LEFT JOIN {{ ref('erp_sales_areas') }} sa
    ON c.customer_id = sa.customer_id
LEFT JOIN {{ ref('erp_payment_terms') }} pt
    ON sa.payment_terms_code = pt.payment_terms_code
LEFT JOIN {{ ref('erp_districts') }} d
    ON sa.district_code = d.district_code
LEFT JOIN {{ ref('erp_customer_partners') }} cp
    ON c.customer_id = cp.customer_id
    AND cp.partner_function = 'CO'
LEFT JOIN {{ ref('erp_employees') }} e
    ON cp.employee_id = e.employee_id
