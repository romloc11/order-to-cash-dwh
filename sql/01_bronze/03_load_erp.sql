/*
 * bronze.load_erp: the daily ERP load.
 *
 *   Small tables and open items (BSID)  -> full reload. An open item leaves BSID when it is
 *                                          cleared, so the only safe way to copy it is to copy it all.
 *   Big, growing tables                 -> incremental MERGE on a date column (the "watermark"):
 *        BSAD  cleared items   by clearing date  (AUGDT)
 *        VBRK  billing         by billing date   (FKDAT)
 *        CDHDR change headers  by change date    (UDATE)
 *        CDPOS change items    by the headers loaded in this run
 *
 * Watermark = the latest date already in bronze minus @lookback_days. Re-reading a few days
 * guards against late-arriving changes; the MERGE makes the re-read harmless.
 * The very first run (empty bronze tables) loads everything, because the watermark is '00000000'.
 *
 * @full_reload = 1 ignores the watermark and reloads everything (use for recovery).
 */
USE dwh;
GO

CREATE OR ALTER PROCEDURE bronze.load_erp
    @full_reload   BIT = 0,
    @lookback_days INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @process SYSNAME = N'bronze.load_erp';
    DECLARE @batch UNIQUEIDENTIFIER = NEWID();
    DECLARE @t_total DATETIME2 = SYSUTCDATETIME(), @t DATETIME2, @rows INT, @total_rows INT = 0;
    DECLARE @table SYSNAME, @mark CHAR(8), @filter NVARCHAR(1000);

    BEGIN TRY
        -- 1. Full reloads ------------------------------------------------------------------
        DECLARE full_tables CURSOR LOCAL FAST_FORWARD FOR
            SELECT v FROM (VALUES (N'KNA1'), (N'KNVV'), (N'KNKK'), (N'KNVP'),
                                  (N'PA0001'), (N'T052'), (N'T171T'), (N'BSID')) AS x(v);
        OPEN full_tables;
        FETCH NEXT FROM full_tables INTO @table;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @t = SYSUTCDATETIME();
            BEGIN TRAN;
                EXEC bronze.reload_full @table, @batch, @rows OUTPUT;
            COMMIT;
            SET @total_rows += @rows;
            EXEC control.log_step @batch, @process, @table, @t, @rows;
            FETCH NEXT FROM full_tables INTO @table;
        END;
        CLOSE full_tables; DEALLOCATE full_tables;

        -- 2. Incremental loads -------------------------------------------------------------
        -- Each block: compute the watermark, then MERGE everything on or after it.
        SET @t = SYSUTCDATETIME();
        SET @mark = CASE WHEN @full_reload = 1 THEN '00000000' ELSE
            COALESCE((SELECT CONVERT(CHAR(8), DATEADD(DAY, -@lookback_days, CONVERT(DATE, MAX(AUGDT), 112)), 112)
                      FROM bronze.erp_bsad), '00000000') END;
        SET @filter = N'AUGDT >= ''' + @mark + N'''';
        BEGIN TRAN;
            EXEC bronze.merge_incremental N'BSAD', @filter, @batch, @rows OUTPUT;
        COMMIT;
        SET @total_rows += @rows;
        EXEC control.log_step @batch, @process, N'BSAD', @t, @rows;

        SET @t = SYSUTCDATETIME();
        SET @mark = CASE WHEN @full_reload = 1 THEN '00000000' ELSE
            COALESCE((SELECT CONVERT(CHAR(8), DATEADD(DAY, -@lookback_days, CONVERT(DATE, MAX(FKDAT), 112)), 112)
                      FROM bronze.erp_vbrk), '00000000') END;
        SET @filter = N'FKDAT >= ''' + @mark + N'''';
        BEGIN TRAN;
            EXEC bronze.merge_incremental N'VBRK', @filter, @batch, @rows OUTPUT;
        COMMIT;
        SET @total_rows += @rows;
        EXEC control.log_step @batch, @process, N'VBRK', @t, @rows;

        SET @t = SYSUTCDATETIME();
        SET @mark = CASE WHEN @full_reload = 1 THEN '00000000' ELSE
            COALESCE((SELECT CONVERT(CHAR(8), DATEADD(DAY, -@lookback_days, CONVERT(DATE, MAX(UDATE), 112)), 112)
                      FROM bronze.erp_cdhdr), '00000000') END;
        SET @filter = N'UDATE >= ''' + @mark + N'''';
        BEGIN TRAN;
            EXEC bronze.merge_incremental N'CDHDR', @filter, @batch, @rows OUTPUT;
        COMMIT;
        SET @total_rows += @rows;
        EXEC control.log_step @batch, @process, N'CDHDR', @t, @rows;

        -- change items: only for the headers this run just touched
        SET @t = SYSUTCDATETIME();
        SET @filter = N'CHANGENR IN (SELECT CHANGENR FROM bronze.erp_cdhdr WHERE _batch_id = '''
                      + CONVERT(NVARCHAR(36), @batch) + N''')';
        BEGIN TRAN;
            EXEC bronze.merge_incremental N'CDPOS', @filter, @batch, @rows OUTPUT;
        COMMIT;
        SET @total_rows += @rows;
        EXEC control.log_step @batch, @process, N'CDPOS', @t, @rows;

        -- 3. Done: the 'total' step is what control.verify_sources looks for ----------------
        EXEC control.log_step @batch, @process, N'total', @t_total, @total_rows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;                       -- undo first, then log (see control.log_step)
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE(), @line INT = ERROR_LINE();
        EXEC control.log_step @batch, @process, N'total', @t_total, NULL, @msg, @line;
        THROW;                                             -- the caller (a job, Airflow) must see the failure
    END CATCH;
END;
GO
