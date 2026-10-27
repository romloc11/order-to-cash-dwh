{#
  By default dbt builds the schema name as <target schema>_<custom schema>, e.g. dbo_silver.
  We want the medallion layers to be called exactly `silver` and `gold`, so this macro
  overrides that rule: when a model asks for a custom schema, use it as it is.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
