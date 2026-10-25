/*
 * Bronze, e-commerce (MariaDB source): a raw copy of each table, written by the Python extractor.
 * Same names and meaning as the source; two metadata columns are added (_loaded_at, _batch_id).
 * Only creates what is missing; never drops or alters.
 */
USE dwh;
GO

IF OBJECT_ID('bronze.ecommerce_orders') IS NULL
CREATE TABLE bronze.ecommerce_orders (
    id            INT           NOT NULL,
    order_number  VARCHAR(20)   NOT NULL,
    customer_ref  VARCHAR(20)   NOT NULL,   -- ERP customer number WITHOUT leading zeros, kept as it arrives
    created_at    DATETIME2(0)  NOT NULL,
    status        VARCHAR(20)   NOT NULL,
    total_amount  DECIMAL(15,2) NOT NULL,
    currency      CHAR(3)       NOT NULL,
    updated_at    DATETIME2(0)  NOT NULL,
    _loaded_at    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    _batch_id     UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_bronze_ecommerce_orders PRIMARY KEY (id));

IF OBJECT_ID('bronze.ecommerce_order_holds') IS NULL
CREATE TABLE bronze.ecommerce_order_holds (
    id            INT          NOT NULL,
    order_id      INT          NOT NULL,
    reason        VARCHAR(30)  NOT NULL,
    held_at       DATETIME2(0) NOT NULL,
    released_at   DATETIME2(0) NULL,
    release_type  VARCHAR(20)  NULL,
    updated_at    DATETIME2(0) NOT NULL,
    _loaded_at    DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME(),
    _batch_id     UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_bronze_ecommerce_order_holds PRIMARY KEY (id));
GO
