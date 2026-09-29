/* ============================================================================
   Script Name     : 02_load_bronze_proc.sql
   Description     : Creates (or alters) the stored procedure that performs a
                      full-refresh load of the Bronze layer staging tables via
                      BULK INSERT from flat-file CRM and ERP source extracts.
                      Pattern: TRUNCATE + BULK INSERT per table (full reload,
                      not incremental/delta).
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : ALTER ANY SCHEMA / CREATE PROCEDURE on [bronze];
                      ADMINISTER BULK OPERATIONS (or bulkadmin role);
                      read access on the source file paths for the SQL
                      Server service account.
   ----------------------------------------------------------------------------
   Revision History
   Date        Author              Version   Description
   ----------  ------------------  --------  ---------------------------------
   2026-09-23  Mohammed Abuteir    1.0.0     Initial documented version;
                                              added per-table error handling,
                                              timing, and load logging.
   ============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ============================================================================
   CAUTION: DESTRUCTIVE OPERATION
   This procedure TRUNCATEs every Bronze table before reloading it. All rows
   currently in each table are PERMANENTLY REMOVED before the corresponding
   BULK INSERT runs. This is a full-refresh pattern by design -- do not call
   this procedure if an incremental/delta load is required instead.
   ============================================================================ */

CREATE OR ALTER PROCEDURE bronze.load_bronze
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @batch_start_time   DATETIME2 = SYSDATETIME();
    DECLARE @table_start_time   DATETIME2;
    DECLARE @current_table      SYSNAME;
    DECLARE @error_message      NVARCHAR(4000);

    BEGIN TRY

        PRINT '================================================================';
        PRINT ' Bronze Layer Load Started: ' + CONVERT(VARCHAR(19), @batch_start_time, 120);
        PRINT '================================================================';

        --------------------------------------------------------------------
        -- CRM Source: crm_cust_info
        --------------------------------------------------------------------
        SET @current_table    = 'bronze.crm_cust_info';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE bronze.crm_cust_info;

        BULK INSERT bronze.crm_cust_info
        FROM 'C:\dwh_project\datasets\source_crm\cust_info.csv'
        WITH
        (
            FIRSTROW      = 2,
            FIELDTERMINATOR = ',',
            ROWTERMINATOR = '\n',
            TABLOCK
        );

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- CRM Source: crm_prd_info
        --------------------------------------------------------------------
        SET @current_table    = 'bronze.crm_prd_info';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE bronze.crm_prd_info;

        BULK INSERT bronze.crm_prd_info
        FROM 'C:\dwh_project\datasets\source_crm\prd_info.csv'
        WITH
        (
            FIRSTROW      = 2,
            FIELDTERMINATOR = ',',
            ROWTERMINATOR = '\n',
            TABLOCK
        );

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- CRM Source: crm_sales_details
        --------------------------------------------------------------------
        SET @current_table    = 'bronze.crm_sales_details';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE bronze.crm_sales_details;

        BULK INSERT bronze.crm_sales_details
        FROM 'C:\dwh_project\datasets\source_crm\sales_details.csv'
        WITH
        (
            FIRSTROW      = 2,
            FIELDTERMINATOR = ',',
            ROWTERMINATOR = '\n',
            TABLOCK
        );

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- ERP Source: erp_cust_az12
        --------------------------------------------------------------------
        SET @current_table    = 'bronze.erp_cust_az12';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE bronze.erp_cust_az12;

        BULK INSERT bronze.erp_cust_az12
        FROM 'C:\dwh_project\datasets\source_erp\cust_az12.csv'
        WITH
        (
            FIRSTROW      = 2,
            FIELDTERMINATOR = ',',
            ROWTERMINATOR = '\n',
            TABLOCK
        );

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- ERP Source: erp_loc_a101
        --------------------------------------------------------------------
        SET @current_table    = 'bronze.erp_loc_a101';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE bronze.erp_loc_a101;

        BULK INSERT bronze.erp_loc_a101
        FROM 'C:\dwh_project\datasets\source_erp\loc_a101.csv'
        WITH
        (
            FIRSTROW      = 2,
            FIELDTERMINATOR = ',',
            ROWTERMINATOR = '\n',
            TABLOCK
        );

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- ERP Source: erp_px_cat_g1v2
        --------------------------------------------------------------------
        SET @current_table    = 'bronze.erp_px_cat_g1v2';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE bronze.erp_px_cat_g1v2;

        BULK INSERT bronze.erp_px_cat_g1v2
        FROM 'C:\dwh_project\datasets\source_erp\px_cat_g1v2.csv'
        WITH
        (
            FIRSTROW      = 2,
            FIELDTERMINATOR = ',',
            ROWTERMINATOR = '\n',
            TABLOCK
        );

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        PRINT '================================================================';
        PRINT ' Bronze Layer Load Completed Successfully. Total duration: '
            + CAST(DATEDIFF(SECOND, @batch_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' sec';
        PRINT '================================================================';

    END TRY
    BEGIN CATCH

        SET @error_message =
              'Bronze load FAILED while processing ' + ISNULL(@current_table, '<unknown table>')
            + '. Error ' + CAST(ERROR_NUMBER() AS VARCHAR(20))
            + ', Line ' + CAST(ERROR_LINE() AS VARCHAR(20))
            + ': ' + ERROR_MESSAGE();

        PRINT '================================================================';
        PRINT ' ' + @error_message;
        PRINT '================================================================';

        -- Re-throw so the calling job/pipeline (e.g. SQL Agent, Orchestrator)
        -- observes the failure and does not silently continue downstream.
        THROW;

    END CATCH
END
GO