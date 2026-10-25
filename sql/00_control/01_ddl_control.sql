/*
 * Control layer: the load log and the source check.
 *
 * Every load writes one row per step to control.load_log (rows, seconds, error).
 * A load also writes a final step called 'total'. control.verify_sources reads
 * those 'total' rows to decide whether the downstream layers may run.
 */
USE dwh;
GO

IF OBJECT_ID('control.load_log') IS NULL
CREATE TABLE control.load_log (
    log_id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id         UNIQUEIDENTIFIER NULL,        -- one value per run of a process
    process_name     SYSNAME          NOT NULL,    -- e.g. bronze.load_erp
    step_name        NVARCHAR(100)    NOT NULL,    -- e.g. bsad, or 'total'
    status           VARCHAR(10)      NOT NULL,    -- OK or ERROR
    start_time       DATETIME2        NOT NULL,
    end_time         DATETIME2        NOT NULL,
    duration_seconds DECIMAL(10,2)    NOT NULL,
    rows_affected    INT              NULL,
    error_message    NVARCHAR(4000)   NULL,
    error_line       INT              NULL
);
GO

/*
 * control.log_step: records one step. It also prints a line while the load runs
 * (RAISERROR ... WITH NOWAIT shows it immediately instead of when the batch ends).
 * Call it AFTER a rollback: a row inserted inside a transaction that is rolled back is lost.
 */
CREATE OR ALTER PROCEDURE control.log_step
    @batch_id      UNIQUEIDENTIFIER,
    @process_name  SYSNAME,
    @step_name     NVARCHAR(100),
    @start_time    DATETIME2,
    @rows_affected INT = NULL,
    @error_message NVARCHAR(4000) = NULL,
    @error_line    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @end DATETIME2 = SYSUTCDATETIME();
    DECLARE @status VARCHAR(10) = CASE WHEN @error_message IS NULL THEN 'OK' ELSE 'ERROR' END;
    DECLARE @seconds DECIMAL(10,2) = DATEDIFF_BIG(MILLISECOND, @start_time, @end) / 1000.0;

    INSERT control.load_log (batch_id, process_name, step_name, status, start_time, end_time,
                             duration_seconds, rows_affected, error_message, error_line)
    VALUES (@batch_id, @process_name, @step_name, @status, @start_time, @end,
            @seconds, @rows_affected, @error_message, @error_line);

    DECLARE @line NVARCHAR(500) = CONCAT(@process_name, ' | ', @step_name, ' | ',
                                         COALESCE(CAST(@rows_affected AS NVARCHAR(20)), '-'), ' rows | ',
                                         @seconds, ' s',
                                         CASE WHEN @error_message IS NULL THEN ''
                                              ELSE CONCAT(' | ERROR line ', @error_line, ': ', @error_message) END);
    RAISERROR(@line, 0, 1) WITH NOWAIT;
END;
GO

/*
 * control.verify_sources: fails (THROW) if any source has no successful 'total' step in the
 * last @max_age_hours. Silver and Gold must not run on yesterday's data without anyone noticing.
 */
CREATE OR ALTER PROCEDURE control.verify_sources
    @max_age_hours INT = 26
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected TABLE (process_name SYSNAME NOT NULL);
    INSERT @expected VALUES (N'bronze.load_erp'), (N'bronze.load_crm'), (N'bronze.load_ecommerce');

    DECLARE @missing NVARCHAR(400) = (
        SELECT STRING_AGG(e.process_name, N', ')
        FROM @expected e
        WHERE NOT EXISTS (SELECT 1 FROM control.load_log l
                          WHERE l.process_name = e.process_name AND l.step_name = N'total' AND l.status = 'OK'
                            AND l.end_time >= DATEADD(HOUR, -@max_age_hours, SYSUTCDATETIME())));

    IF @missing IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(2048) = CONCAT(N'Sources not loaded recently: ', @missing);
        THROW 50001, @msg, 1;
    END;
END;
GO
