{# Converts an SAP date (text, YYYYMMDD) to a date. Returns NULL if it cannot be converted. #}
{% macro sap_date(column) -%}
    try_convert(date, {{ column }}, 112)
{%- endmacro %}

{# Trims leading and trailing spaces; empty text becomes NULL. #}
{% macro clean_text(column) -%}
    nullif(ltrim(rtrim({{ column }})), '')
{%- endmacro %}