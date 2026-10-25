-- CRM source (Odoo-shaped), simulated in PostgreSQL.
-- Runs once, the first time the postgres container starts with an empty data volume.
-- `ref` holds the ERP customer number WITHOUT leading zeros, as CRMs usually do;
-- the warehouse has to normalise it to join with the ERP.

CREATE TABLE res_users (
    id          integer PRIMARY KEY,
    login       text NOT NULL,
    name        text NOT NULL,
    active      boolean NOT NULL,
    create_date timestamp NOT NULL,
    write_date  timestamp NOT NULL
);

CREATE TABLE res_partner (
    id          integer PRIMARY KEY,
    name        text NOT NULL,
    ref         text,                 -- ERP customer number, no leading zeros
    vat         text,
    parent_id   integer REFERENCES res_partner (id),
    user_id     integer REFERENCES res_users (id),   -- account owner (collector)
    active      boolean NOT NULL,
    type        text,
    create_date timestamp NOT NULL,
    write_date  timestamp NOT NULL
);
CREATE INDEX ix_res_partner_write_date ON res_partner (write_date);

CREATE TABLE collection_activity (
    id               integer PRIMARY KEY,
    partner_id       integer NOT NULL REFERENCES res_partner (id),
    invoice_ref      text,             -- ERP billing document number
    activity_type    text NOT NULL,    -- call, email, visit, whatsapp
    outcome          text NOT NULL,    -- promise, no_answer, dispute, info_sent
    promised_date    date,
    promised_amount  numeric(15,2),
    note             text,
    user_id          integer REFERENCES res_users (id),
    create_date      timestamp NOT NULL,
    write_date       timestamp NOT NULL
);
CREATE INDEX ix_collection_activity_write_date ON collection_activity (write_date);

-- Server-side COPY: the generator output is mounted read-only at /seed.
COPY res_users           FROM '/seed/crm/res_users.csv'           WITH (FORMAT csv, HEADER true);
COPY res_partner         FROM '/seed/crm/res_partner.csv'         WITH (FORMAT csv, HEADER true);
COPY collection_activity FROM '/seed/crm/collection_activity.csv' WITH (FORMAT csv, HEADER true);
