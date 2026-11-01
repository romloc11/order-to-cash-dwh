
{% snapshot customers_snapshot %}
{{
    config(
        target_schema='snapshots',
        unique_key='customer_id',
        strategy='check',
        check_cols=['customer_name', 'tax_id', 'account_group']
    )
}}
SELECT
    customer_id,
    customer_name,
    tax_id,
    account_group
FROM {{ ref('erp_customers') }}
{% endsnapshot %}