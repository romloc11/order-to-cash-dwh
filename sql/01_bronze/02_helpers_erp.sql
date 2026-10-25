/*
 * Two generic helpers for the ERP load. They build the column lists from the catalog
 * (sys.columns, sys.indexes) so adding a column to a bronze table needs no code change.
 * Naming rule: source table KNA1 in erp_source.dbo  ->  bronze.erp_kna1.
 */
USE dwh;
GO

/* Full reload: empty the bronze table and copy the whole source table. */
CREATE OR ALTER PROCEDURE bronze.reload_full
    @source_table SYSNAME,
    @batch_id     UNIQUEIDENTIFIER,
    @rows         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @target NVARCHAR(300) = N'bronze.erp_' + LOWER(@source_table);
    DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

    SELECT @cols = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@target) AND c.name NOT LIKE N'[_]%';   -- skip _loaded_at, _batch_id

    SET @sql = N'TRUNCATE TABLE ' + @target + N';
                 INSERT INTO ' + @target + N' (' + @cols + N', _batch_id)
                 SELECT ' + @cols + N', @b FROM erp_source.dbo.' + QUOTENAME(@source_table) + N';
                 SET @n = @@ROWCOUNT;';
    EXEC sp_executesql @sql, N'@b UNIQUEIDENTIFIER, @n INT OUTPUT', @b = @batch_id, @n = @rows OUTPUT;
END;
GO

/*
 * Incremental load: MERGE the source rows that match @filter into the bronze table.
 * Matched rows (same primary key) are updated; new rows are inserted. Nothing is deleted.
 */
CREATE OR ALTER PROCEDURE bronze.merge_incremental
    @source_table SYSNAME,
    @filter       NVARCHAR(1000),
    @batch_id     UNIQUEIDENTIFIER,
    @rows         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @target NVARCHAR(300) = N'bronze.erp_' + LOWER(@source_table);
    DECLARE @cols NVARCHAR(MAX), @vals NVARCHAR(MAX), @keys NVARCHAR(MAX), @sets NVARCHAR(MAX), @sql NVARCHAR(MAX);

    -- primary key columns of the target
    DECLARE @pk TABLE (name SYSNAME NOT NULL);
    INSERT @pk
    SELECT c.name
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID(@target) AND i.is_primary_key = 1;

    SELECT @cols = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY c.column_id),
           @vals = STRING_AGG(CAST(N's.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@target) AND c.name NOT LIKE N'[_]%';

    SELECT @keys = STRING_AGG(CAST(N't.' + QUOTENAME(name) + N' = s.' + QUOTENAME(name) AS NVARCHAR(MAX)), N' AND ')
    FROM @pk;

    SELECT @sets = STRING_AGG(CAST(N't.' + QUOTENAME(c.name) + N' = s.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@target) AND c.name NOT LIKE N'[_]%'
      AND c.name NOT IN (SELECT name FROM @pk);

    SET @sql = N'MERGE ' + @target + N' AS t
                 USING (SELECT ' + @cols + N' FROM erp_source.dbo.' + QUOTENAME(@source_table) + N' WHERE ' + @filter + N') AS s
                    ON ' + @keys + N'
                 WHEN MATCHED THEN UPDATE SET ' + @sets + N', t._batch_id = @b, t._loaded_at = SYSUTCDATETIME()
                 WHEN NOT MATCHED THEN INSERT (' + @cols + N', _batch_id) VALUES (' + @vals + N', @b);
                 SET @n = @@ROWCOUNT;';
    EXEC sp_executesql @sql, N'@b UNIQUEIDENTIFIER, @n INT OUTPUT', @b = @batch_id, @n = @rows OUTPUT;
END;
GO
