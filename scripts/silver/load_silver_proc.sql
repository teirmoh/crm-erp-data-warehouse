/* ============================================================================
   Script Name     : load_silver_proc.sql
   Description     : Creates (or alters) the stored procedure that performs
                      the Bronze -> Silver transformation: cleansing,
                      standardizing, deriving, and loading data from Bronze
                      staging tables into Silver tables. Full-refresh
                      pattern (TRUNCATE + INSERT per table), not incremental.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : SELECT on [bronze]; ALTER, INSERT, SELECT, TRUNCATE on
                      [silver]; CREATE PROCEDURE on [silver]
   ----------------------------------------------------------------------------
   Revision History
   Date        Author              Version   Description
   ----------  ------------------  --------  ---------------------------------
   2026-10-05  Mohammed Abuteir    1.0.0     Initial documented version;
                                              added per-table error handling,
                                              timing, and load logging
                                              (mirrors bronze.load_bronze).
                                              REQUIRES silver.crm_prd_info to
                                              have a prd_cat column -- see
                                              DDL note above this script.
   ============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ============================================================================
   CAUTION: DESTRUCTIVE OPERATION
   This procedure TRUNCATEs every Silver table before reloading it from
   Bronze. All rows currently in each Silver table are PERMANENTLY REMOVED
   before the corresponding INSERT runs. This is a full-refresh pattern by
   design, matching bronze.load_bronze.
   ============================================================================ */

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @batch_start_time   DATETIME2 = SYSDATETIME();
    DECLARE @table_start_time   DATETIME2;
    DECLARE @current_table      SYSNAME;
    DECLARE @error_message      NVARCHAR(4000);

    BEGIN TRY

        PRINT '================================================================';
        PRINT ' Silver Layer Load Started: ' + CONVERT(VARCHAR(19), @batch_start_time, 120);
        PRINT '================================================================';

        --------------------------------------------------------------------
        -- silver.crm_cust_info
        -- Dedupe on cst_id (keep most recent by cst_create_date), trim text
        -- columns, standardize marital status and gender codes.
        --------------------------------------------------------------------
        SET @current_table    = 'silver.crm_cust_info';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE silver.crm_cust_info;

        INSERT INTO silver.crm_cust_info
        (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        SELECT
            cst_id,
            TRIM(cst_key)       AS cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname)  AS cst_lastname,
            CASE UPPER(TRIM(cst_marital_status))
                WHEN 'S' THEN 'Single'
                WHEN 'M' THEN 'Married'
                ELSE 'n/a'
            END                 AS cst_marital_status,
            CASE UPPER(TRIM(cst_gndr))
                WHEN 'M' THEN 'Male'
                WHEN 'F' THEN 'Female'
                ELSE 'n/a'
            END                 AS cst_gndr,
            cst_create_date
        FROM
        (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS rn
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        ) t
        WHERE t.rn = 1;

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- silver.crm_prd_info
        -- Split prd_key into category code (prd_cat) and product key, default
        -- NULL cost to 0, expand prd_line codes, derive prd_end_dt as the day
        -- before the next record's start date for the same product.
        --------------------------------------------------------------------
        SET @current_table    = 'silver.crm_prd_info';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE silver.crm_prd_info;

        INSERT INTO silver.crm_prd_info
        (
            prd_id,
            prd_cat,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')   AS prd_cat,
            SUBSTRING(prd_key, 7, LEN(prd_key))            AS prd_key,
            prd_nm,
            COALESCE(prd_cost, 0)                          AS prd_cost,
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'n/a'
            END                                             AS prd_line,
            prd_start_dt,
            LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1 AS prd_end_dt
        FROM bronze.crm_prd_info;

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- silver.crm_sales_details
        -- Trim keys, cast raw 8-digit date integers to DATE (NULL if
        -- invalid), and correct sales/quantity/price where the raw values
        -- are missing, non-positive, or mutually inconsistent.
        --------------------------------------------------------------------
        SET @current_table    = 'silver.crm_sales_details';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE silver.crm_sales_details;

        INSERT INTO silver.crm_sales_details
        (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            TRIM(sls_ord_num) AS sls_ord_num,
            TRIM(sls_prd_key) AS sls_prd_key,
            sls_cust_id,
            CASE
                WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
            END AS sls_order_dt,
            CASE
                WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
            END AS sls_ship_dt,
            CASE
                WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
            END AS sls_due_dt,
            CASE
                WHEN sls_sales IS NULL OR sls_sales <= 0
                     OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,
            CASE
                WHEN sls_quantity IS NULL OR sls_quantity <= 0
                    THEN ABS(sls_sales) / NULLIF(ABS(sls_price), 0)
                ELSE sls_quantity
            END AS sls_quantity,
            CASE
                WHEN sls_price IS NULL OR sls_price <= 0
                    THEN ABS(sls_sales) / NULLIF(ABS(sls_quantity), 0)
                ELSE sls_price
            END AS sls_price
        FROM bronze.crm_sales_details;

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- silver.erp_cust_az12
        -- Strip 'NAS' prefix from cid where present, null out future-dated
        -- birth dates, standardize gender values.
        --------------------------------------------------------------------
        SET @current_table    = 'silver.erp_cust_az12';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE silver.erp_cust_az12;

        INSERT INTO silver.erp_cust_az12
        (
            cid,
            bdate,
            gen
        )
        SELECT
            CASE
                WHEN TRIM(cid) LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
                ELSE TRIM(cid)
            END AS cid,
            CASE
                WHEN bdate > GETDATE() THEN NULL
                ELSE bdate
            END AS bdate,
            CASE
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                ELSE 'n/a'
            END AS gen
        FROM bronze.erp_cust_az12;

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- silver.erp_loc_a101
        -- Remove hyphens from cid to align key format, standardize country
        -- names and blank/NULL values.
        --------------------------------------------------------------------
        SET @current_table    = 'silver.erp_loc_a101';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE silver.erp_loc_a101;

        INSERT INTO silver.erp_loc_a101
        (
            cid,
            cntry
        )
        SELECT
            REPLACE(TRIM(cid), '-', '') AS cid,
            CASE
                WHEN TRIM(cntry) = 'DE'                THEN 'Germany'
                WHEN TRIM(cntry) IN ('USA', 'US')       THEN 'United States'
                WHEN TRIM(cntry) IS NULL OR TRIM(cntry) = '' THEN 'n/a'
                ELSE TRIM(cntry)
            END AS cntry
        FROM bronze.erp_loc_a101;

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        --------------------------------------------------------------------
        -- silver.erp_px_cat_g1v2
        -- Trim category/subcategory/maintenance text columns.
        --------------------------------------------------------------------
        SET @current_table    = 'silver.erp_px_cat_g1v2';
        SET @table_start_time = SYSDATETIME();

        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        INSERT INTO silver.erp_px_cat_g1v2
        (
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT
            id,
            TRIM(cat)         AS cat,
            TRIM(subcat)      AS subcat,
            TRIM(maintenance) AS maintenance
        FROM bronze.erp_px_cat_g1v2;

        PRINT @current_table + ' loaded in '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' ms';

        PRINT '================================================================';
        PRINT ' Silver Layer Load Completed Successfully. Total duration: '
            + CAST(DATEDIFF(SECOND, @batch_start_time, SYSDATETIME()) AS VARCHAR(20)) + ' sec';
        PRINT '================================================================';

    END TRY
    BEGIN CATCH

        SET @error_message =
              'Silver load FAILED while processing ' + ISNULL(@current_table, '<unknown table>')
            + '. Error ' + CAST(ERROR_NUMBER() AS VARCHAR(20))
            + ', Line ' + CAST(ERROR_LINE() AS VARCHAR(20))
            + ': ' + ERROR_MESSAGE();

        PRINT '================================================================';
        PRINT ' ' + @error_message;
        PRINT '================================================================';

        THROW;

    END CATCH
END
GO