# Receivables Medallion Data Warehouse

A SQL Server data warehouse for accounts receivable, built with a **Bronze / Silver / Gold** (medallion) architecture and fed by **three source systems on three different engines**: an ERP (SAP-shaped tables, SQL Server), a CRM (Odoo-shaped tables, PostgreSQL) and an e-commerce database (MariaDB).

Everything here runs locally with Docker and uses **synthetic data only**. The design is a generic, simplified version of a warehouse I built and run in production for a credit & collections team.

> Status: work in progress. The sources and the data generator are done; the warehouse layers are being built.

## What it demonstrates

| Skill | Where |
|---|---|
| Medallion architecture with two heterogeneous sources | `sql/01_bronze` to `sql/03_gold` |
| ERP ingestion in T-SQL (incremental MERGE, backfill) | `sql/01_bronze` |
| CRM ingestion in Python (incremental by `write_date`) | `extractors/` |
| Load framework: step-level log, rollback, source gating | `sql/00_control` |
| Dimensional modeling with SCD Type 2 rebuilt from a change log | `sql/03_gold` |
| Payment-to-invoice matching with explicit reasons for what cannot be matched | `sql/03_gold` |
| Data quality checks and automated tests | `sql/04_dq`, `tests/` |

## The sources

**ERP** (`erp_source` database in SQL Server), SAP-shaped:
`KNA1` customers, `KNVV` sales data, `KNKK` credit, `KNVP` partner functions (collector), `BSID` open items, `BSAD` cleared items, `VBRK` billing, `CDHDR`/`CDPOS` change log.

**CRM** (`crm` database in PostgreSQL), Odoo-shaped:
`res_partner` (customer ref **without** leading zeros), `res_users`, `collection_activity` (calls, emails, promises to pay).

**E-commerce** (`ecommerce` database in MariaDB):
`orders` (web orders) and `order_holds` (the *order pool*: orders held because of an ERP block, an exceeded credit limit or an overdue balance, with the time each one was held and released). Holds are derived from the customer's real credit state on the order date, so the e-commerce data agrees with the ERP data. This lets the warehouse answer: *how much sales value is held back by overdue receivables, and how long does it take to release it?*

### Hard cases injected on purpose

- One payment covering several invoices, and invoices paid in two parts.
- Credit memos netted against invoices.
- Payments cleared weeks after they were received (so *payment date* and *clearing date* differ).
- Payments that never match an invoice.
- Customer attributes that change over time, where roughly 8% of changes are missing from the change log.
- CRM and ERP disagreeing on the account owner for some customers.
- Customer numbers with leading zeros in the ERP and without them in the CRM.

## Run it

```bash
cp .env.example .env          # local throw-away passwords
docker compose up -d --build  # generates data and loads both sources
```

SQL Server listens on `localhost:1433` (user `sa`), PostgreSQL on `localhost:5432` (database `crm`, user `crm`) and MariaDB on `localhost:3306` (database `ecommerce`, user `root`).

To regenerate the data with different settings:

```bash
python -m data_generator.generate --customers 500 --seed 42 --out data_generator/output
```

## Roadmap

- [x] Synthetic data generator (ERP, CRM, e-commerce) and source databases
- [ ] Control layer and Bronze loads (ERP in T-SQL, CRM and e-commerce in Python)
- [ ] Silver
- [ ] Gold: dimensions (SCD2), facts, payment application, analysis views
- [ ] Data quality and tests
- [ ] CI with GitHub Actions
