/* ============================================================================
   Script Name     : data_quality_checks_bronze.sql
   Description     : Data quality / validation checks against the Bronze
                      layer, run prior to building the Bronze -> Silver
                      transformation logic. Each query surfaces a specific
                      data quality issue (nulls, duplicates, untrimmed
                      whitespace, invalid codes, business-rule violations)
                      on a per-column basis so transformation rules can be
                      designed around confirmed, observed issues rather than
                      assumptions.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : SELECT on schema [bronze]
   ----------------------------------------------------------------------------
   Revision History
   Date        Author              Version   Description
   ----------  ------------------  --------  ---------------------------------
   2026-10-05  Mohammed Abuteir    1.0.0     Initial documented version;
                                              corrected crm_prd_info duplicate-
                                              id check (see note below).
   ============================================================================ */

SET NOCOUNT ON;
GO

/* ----------------------------------------------------------------------------
   These are read-only diagnostic queries (SELECT only, no DML/DDL). Run them
   individually in SSMS -- each is intended to return its own result grid, so
   a zero-row result means that check passed cleanly.
   ---------------------------------------------------------------------------- */

--------------------------------------------------------------------------------
-- Table: bronze.crm_cust_info
--------------------------------------------------------------------------------

-- Duplicate or NULL primary key
SELECT
    cst_id,
    COUNT(*) AS occurrence_count
FROM bronze.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;

-- Untrimmed / NULL cst_key
SELECT cst_key FROM bronze.crm_cust_info WHERE cst_key != TRIM(cst_key);
SELECT cst_key FROM bronze.crm_cust_info WHERE cst_key IS NULL;

-- Untrimmed cst_firstname
SELECT cst_firstname FROM bronze.crm_cust_info WHERE cst_firstname != TRIM(cst_firstname);

-- Untrimmed / NULL cst_lastname
SELECT cst_lastname FROM bronze.crm_cust_info WHERE cst_lastname != TRIM(cst_lastname);
SELECT cst_lastname FROM bronze.crm_cust_info WHERE cst_lastname IS NULL;

-- Distinct values + NULLs, to define the standardization mapping in Silver
SELECT DISTINCT cst_marital_status FROM bronze.crm_cust_info;
SELECT cst_marital_status FROM bronze.crm_cust_info WHERE cst_marital_status IS NULL;

SELECT DISTINCT cst_gndr FROM bronze.crm_cust_info;
SELECT cst_gndr FROM bronze.crm_cust_info WHERE cst_gndr IS NULL;

--------------------------------------------------------------------------------
-- Table: bronze.crm_prd_info
--------------------------------------------------------------------------------

-- Duplicate or NULL primary key
-- NOTE: corrected from the original "COUNT(*) = 1" (which would flag every
-- *non*-duplicate row instead of finding duplicates) to "> 1", mirroring the
-- crm_cust_info check above.
SELECT
    prd_id,
    COUNT(*) AS occurrence_count
FROM bronze.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL;

-- Untrimmed / NULL prd_key
SELECT prd_key FROM bronze.crm_prd_info WHERE prd_key != TRIM(prd_key);
SELECT prd_key FROM bronze.crm_prd_info WHERE prd_key IS NULL;

-- Untrimmed / NULL prd_nm
SELECT prd_nm FROM bronze.crm_prd_info WHERE prd_nm != TRIM(prd_nm);
SELECT prd_nm FROM bronze.crm_prd_info WHERE prd_nm IS NULL;

-- Untrimmed / NULL / distinct prd_line
SELECT prd_line FROM bronze.crm_prd_info WHERE prd_line != TRIM(prd_line);
SELECT prd_line FROM bronze.crm_prd_info WHERE prd_line IS NULL;
SELECT DISTINCT prd_line FROM bronze.crm_prd_info;

-- NULL start/end dates
SELECT prd_start_dt FROM bronze.crm_prd_info WHERE prd_start_dt IS NULL;
SELECT prd_end_dt   FROM bronze.crm_prd_info WHERE prd_end_dt   IS NULL;

-- Invalid date range: end date before start date
SELECT
    prd_key,
    prd_start_dt,
    prd_end_dt
FROM bronze.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

--------------------------------------------------------------------------------
-- Table: bronze.crm_sales_details
--------------------------------------------------------------------------------

-- Untrimmed / NULL sls_ord_num
SELECT sls_ord_num FROM bronze.crm_sales_details WHERE sls_ord_num != TRIM(sls_ord_num);
SELECT sls_ord_num FROM bronze.crm_sales_details WHERE sls_ord_num IS NULL;

-- Untrimmed / NULL sls_prd_key
SELECT sls_prd_key FROM bronze.crm_sales_details WHERE sls_prd_key != TRIM(sls_prd_key);
SELECT sls_prd_key FROM bronze.crm_sales_details WHERE sls_prd_key IS NULL;

-- NULL customer id
SELECT sls_cust_id FROM bronze.crm_sales_details WHERE sls_cust_id IS NULL;

-- Invalid sales / price / quantity (NULL, zero, or negative)
SELECT sls_sales    FROM bronze.crm_sales_details WHERE sls_sales    IS NULL OR sls_sales    <= 0;
SELECT sls_price    FROM bronze.crm_sales_details WHERE sls_price    IS NULL OR sls_price    <= 0;
SELECT sls_quantity FROM bronze.crm_sales_details WHERE sls_quantity IS NULL OR sls_quantity <= 0;

-- Business rule violation: sales should equal quantity * |price|
SELECT *
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * ABS(sls_price);

-- Invalid raw date integers (expected 8-digit YYYYMMDD format)
SELECT sls_order_dt FROM bronze.crm_sales_details WHERE sls_order_dt = 0 OR LEN(sls_order_dt) != 8;
SELECT sls_ship_dt  FROM bronze.crm_sales_details WHERE sls_ship_dt  = 0 OR LEN(sls_ship_dt)  != 8;
SELECT sls_due_dt   FROM bronze.crm_sales_details WHERE sls_due_dt   = 0 OR LEN(sls_due_dt)   != 8;

--------------------------------------------------------------------------------
-- Table: bronze.erp_cust_az12
--------------------------------------------------------------------------------

-- Duplicate CID
SELECT
    cid,
    COUNT(*) AS occurrence_count
FROM bronze.erp_cust_az12
GROUP BY cid
HAVING COUNT(*) > 1;

-- CIDs that don't match the expected 'NASA' prefix pattern
SELECT cid FROM bronze.erp_cust_az12 WHERE cid NOT LIKE 'NASA%';

-- Untrimmed / NULL CID
SELECT cid FROM bronze.erp_cust_az12 WHERE cid != TRIM(cid);
SELECT cid FROM bronze.erp_cust_az12 WHERE cid IS NULL;

-- Future-dated birth dates (invalid)
SELECT bdate FROM bronze.erp_cust_az12 WHERE bdate > GETDATE();

-- Distinct values, to define the standardization mapping in Silver
SELECT DISTINCT gen FROM bronze.erp_cust_az12;

--------------------------------------------------------------------------------
-- Table: bronze.erp_loc_a101
--------------------------------------------------------------------------------

-- Untrimmed / NULL CID
SELECT cid FROM bronze.erp_loc_a101 WHERE cid != TRIM(cid);
SELECT cid FROM bronze.erp_loc_a101 WHERE cid IS NULL;

-- CIDs that don't match the expected '<2 chars>-<...>' pattern
SELECT cid FROM bronze.erp_loc_a101 WHERE cid NOT LIKE '__-%';

-- Untrimmed / distinct country values
SELECT cntry FROM bronze.erp_loc_a101 WHERE cntry != TRIM(cntry);
SELECT DISTINCT cntry FROM bronze.erp_loc_a101;

--------------------------------------------------------------------------------
-- Table: bronze.erp_px_cat_g1v2
--------------------------------------------------------------------------------

-- Distinct maintenance flag values, to confirm expected domain
SELECT DISTINCT maintenance FROM bronze.erp_px_cat_g1v2;

-- Untrimmed category / subcategory
SELECT cat    FROM bronze.erp_px_cat_g1v2 WHERE cat    != TRIM(cat);
SELECT subcat FROM bronze.erp_px_cat_g1v2 WHERE subcat != TRIM(subcat);