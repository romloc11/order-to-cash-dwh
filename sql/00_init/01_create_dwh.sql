/*
 * The warehouse database and its schemas, one per layer.
 * Re-runnable: creates only what is missing and never drops anything.
 */
IF DB_ID('dwh') IS NULL
    CREATE DATABASE dwh;
GO
USE dwh;
GO
IF SCHEMA_ID('control') IS NULL EXEC('CREATE SCHEMA control');
IF SCHEMA_ID('bronze')  IS NULL EXEC('CREATE SCHEMA bronze');
IF SCHEMA_ID('silver')  IS NULL EXEC('CREATE SCHEMA silver');
IF SCHEMA_ID('gold')    IS NULL EXEC('CREATE SCHEMA gold');
IF SCHEMA_ID('dq')      IS NULL EXEC('CREATE SCHEMA dq');
GO
