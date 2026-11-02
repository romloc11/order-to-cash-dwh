# Data lineage

Two views of how data flows through the warehouse. The first one shows the layers, the second one shows how the Gold tables depend on each other.

The generated dbt documentation site (`dbt docs generate`) is the source of truth for lineage; these diagrams are a readable summary of it.

## Layers

```mermaid
flowchart LR
    subgraph SRC["Source systems"]
        ERP[("ERP<br/>SQL Server")]
        CRM[("CRM<br/>PostgreSQL")]
        ECOM[("E-commerce<br/>MariaDB")]
    end

    subgraph BRONZE["Bronze: raw copies"]
        B1["erp_* tables"]
        B2["crm_* tables"]
        B3["ecommerce_* tables"]
    end

    subgraph SILVER["Silver: cleaned views"]
        S1["erp_* models"]
        S2["crm_* models"]
        S3["ecommerce_* models"]
    end

    subgraph GOLD["Gold: dimensions and facts"]
        G1["dim_customer<br/>dim_customer_credit_history<br/>dim_date"]
        G2["fact_invoice<br/>fact_payment<br/>fact_credit_memo<br/>bridge_payment_application"]
        G3["fact_ar_snapshot<br/>fact_web_order"]
    end

    ERP --> B1 --> S1
    CRM --> B2 --> S2
    ECOM --> B3 --> S3

    S1 --> G1
    S1 --> G2
    G1 --> G3
    G2 --> G3
    S3 --> G3
```

## Gold models

```mermaid
flowchart LR
    OPEN["erp_open_items<br/>erp_cleared_items"]
    MASTER["erp customer master<br/>customers, credit, sales areas,<br/>payment terms, districts,<br/>partners, employees"]
    CHANGES["erp_change_headers<br/>erp_change_items<br/>erp_customer_credit"]
    WEB["ecommerce_orders<br/>ecommerce_order_holds"]

    OPEN --> fact_payment
    OPEN --> fact_credit_memo
    OPEN --> bridge_payment_application
    OPEN --> fact_invoice
    fact_credit_memo --> bridge_payment_application
    bridge_payment_application --> fact_invoice

    MASTER --> dim_customer
    CHANGES --> dim_customer_credit_history

    dim_date --> fact_ar_snapshot
    dim_customer --> fact_ar_snapshot
    dim_customer_credit_history --> fact_ar_snapshot
    fact_invoice --> fact_ar_snapshot
    fact_payment --> fact_ar_snapshot
    fact_credit_memo --> fact_ar_snapshot

    fact_ar_snapshot --> fact_web_order
    WEB --> fact_web_order

    classDef silver fill:#e3f2fd,stroke:#1e88e5,color:#0d47a1
    classDef gold fill:#fff8e1,stroke:#f9a825,color:#5d4037
    class OPEN,MASTER,CHANGES,WEB silver
    class dim_customer,dim_customer_credit_history,dim_date,fact_invoice,fact_payment,fact_credit_memo,bridge_payment_application,fact_ar_snapshot,fact_web_order gold
```

Reading it from the bottom up: `fact_web_order` needs the customer's receivables position on the order date (`fact_ar_snapshot`), which in turn needs every invoice, payment and credit memo, the credit limit in force on that day (`dim_customer_credit_history`) and the calendar (`dim_date`).
