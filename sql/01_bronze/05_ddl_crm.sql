/*
 * Bronze, CRM (PostgreSQL source): a raw copy of each table, written by the Python extractor.
 * Same names and meaning as the source; two metadata columns are added (_loaded_at, _batch_id).
 * `ref` keeps the ERP customer number WITHOUT leading zeros, exactly as the CRM stores it.
 * Only creates what is missing; never drops or alters.
 */
USE dwh;
GO

IF OBJECT_ID('bronze.crm_res_users') IS NULL
CREATE TABLE bronze.crm_res_users (
    id           INT           NOT NULL,
    login        NVARCHAR(200) NOT NULL,
    name         NVARCHAR(200) NOT NULL,
    active       BIT           NOT NULL,
    create_date  DATETIME2(0)  NOT NULL,
    write_date   DATETIME2(0)  NOT NULL,
    _loaded_at   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    _batch_id    UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_bronze_crm_res_users PRIMARY KEY (id));

IF OBJECT_ID('bronze.crm_res_partner') IS NULL
CREATE TABLE bronze.crm_res_partner (
    id           INT           NOT NULL,
    name         NVARCHAR(300) NOT NULL,
    ref          VARCHAR(50)   NULL,
    vat          VARCHAR(50)   NULL,
    parent_id    INT           NULL,
    user_id      INT           NULL,
    active       BIT           NOT NULL,
    type         VARCHAR(30)   NULL,
    create_date  DATETIME2(0)  NOT NULL,
    write_date   DATETIME2(0)  NOT NULL,
    _loaded_at   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    _batch_id    UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_bronze_crm_res_partner PRIMARY KEY (id));

IF OBJECT_ID('bronze.crm_collection_activity') IS NULL
CREATE TABLE bronze.crm_collection_activity (
    id               INT           NOT NULL,
    partner_id       INT           NOT NULL,
    invoice_ref      VARCHAR(20)   NULL,
    activity_type    VARCHAR(20)   NOT NULL,
    outcome          VARCHAR(20)   NOT NULL,
    promised_date    DATE          NULL,
    promised_amount  DECIMAL(15,2) NULL,
    note             NVARCHAR(500) NULL,
    user_id          INT           NULL,
    create_date      DATETIME2(0)  NOT NULL,
    write_date       DATETIME2(0)  NOT NULL,
    _loaded_at       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    _batch_id        UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_bronze_crm_collection_activity PRIMARY KEY (id));
GO
