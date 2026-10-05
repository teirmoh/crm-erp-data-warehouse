/* ============================================================================
   Script Name     : data_quality_checks_silver.sql
   Description     : Post-transformation data quality checks against the
                      Silver layer, validated directly against the actual
                      transformation rules implemented in
                      silver.load_silver. Each check reflects what that
                      procedure's logic actually guarantees -- not a guess.
                      Checks are grouped as:
                        (a) invariants the transformation guarantees (should
                            always return zero rows), and
                        (b) known edge cases the transformation does NOT
                            fully guarantee (flagged explicitly, with the
                            reason why), so a nonzero result there is
                            expected to be reviewed, not treated as a bug.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : SELECT on schema [silver]
   ----------------------------------------------------------------------------
   Revision History
   Date        Author              Version   Description
   ----------  ------------------  --------  ---------------------------------
   2026-10-05  Mohammed Abuteir    1.0.0     Initial documented version
   ============================================================================ */

SET NOCOUNT ON;
GO

--------------------------------------------------------------------------------
-- Table: silver.crm_cust_info
--------------------------------------------------------------------------------

SELECT
    cst_id,
    COUNT(*) AS occurrence_count
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;

SELECT cst_key       FROM silver.crm_cust_info WHERE cst_key       != TRIM(cst_key);
SELECT cst_firstname FROM silver.crm_cust_info WHERE cst_firstname != TRIM(cst_firstname);
SELECT cst_lastname  FROM silver.crm_cust_info WHERE cst_lastname  != TRIM(cst_lastname);

SELECT DISTINCT cst_marital_status
FROM silver.crm_cust_info
WHERE cst_marital_status NOT IN ('Single', 'Married', 'n/a');

SELECT DISTINCT cst_gndr
FROM silver.crm_cust_info
WHERE cst_gndr NOT IN ('Male', 'Female', 'n/a');

--------------------------------------------------------------------------------
-- Table: silver.crm_prd_info
--------------------------------------------------------------------------------

-- NOTE: no dedup on prd_id in the transformation -- loads straight from
-- Bronze, so a nonzero result is a source data issue, not a Silver defect.
SELECT
    prd_id,
    COUNT(*) AS occurrence_count
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL;

SELECT prd_cat FROM silver.crm_prd_info WHERE prd_cat != TRIM(prd_cat);
SELECT prd_key FROM silver.crm_prd_info WHERE prd_key != TRIM(prd_key);

-- NOTE: prd_nm is NOT trimmed by the transformation -- a nonzero result is
-- a real, uncorrected gap.
SELECT prd_nm FROM silver.crm_prd_info WHERE prd_nm != TRIM(prd_nm);

SELECT DISTINCT prd_line
FROM silver.crm_prd_info
WHERE prd_line NOT IN ('Mountain', 'Road', 'Other Sales', 'Touring', 'n/a');

SELECT
    prd_key,
    prd_start_dt,
    prd_end_dt
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

-- NOTE: NULL prd_end_dt is expected for each product's current record
-- (LEAD() has no next row). Informational count, not a failure check.
SELECT COUNT(*) AS current_product_records
FROM silver.crm_prd_info
WHERE prd_end_dt IS NULL;

--------------------------------------------------------------------------------
-- Table: silver.crm_sales_details
--------------------------------------------------------------------------------

SELECT sls_ord_num FROM silver.crm_sales_details WHERE sls_ord_num != TRIM(sls_ord_num);
SELECT sls_prd_key FROM silver.crm_sales_details WHERE sls_prd_key != TRIM(sls_prd_key);
SELECT sls_cust_id FROM silver.crm_sales_details WHERE sls_cust_id IS NULL;

-- NOTE: NULL dates here mean the raw Bronze value was unparseable (0 or not
-- 8 digits) -- intentional, not a bug. Informational count only.
SELECT
    SUM(CASE WHEN sls_order_dt IS NULL THEN 1 ELSE 0 END) AS null_order_dt_count,
    SUM(CASE WHEN sls_ship_dt  IS NULL THEN 1 ELSE 0 END) AS null_ship_dt_count,
    SUM(CASE WHEN sls_due_dt   IS NULL THEN 1 ELSE 0 END) AS null_due_dt_count
FROM silver.crm_sales_details;

-- Logical date order is not enforced by the transformation -- a genuine
-- business-rule check, nonzero results are real.
SELECT *
FROM silver.crm_sales_details
WHERE sls_order_dt > sls_ship_dt OR sls_ship_dt > sls_due_dt;

-- NOTE: the three correction CASE blocks each reference the ORIGINAL Bronze
-- values independently, not each other's corrected output -- a row with
-- more than one field invalid in Bronze simultaneously can still fail these
-- checks after transformation. Real, currently-unhandled edge case.
SELECT sls_sales    FROM silver.crm_sales_details WHERE sls_sales    IS NULL OR sls_sales    <= 0;
SELECT sls_quantity FROM silver.crm_sales_details WHERE sls_quantity IS NULL OR sls_quantity <= 0;
SELECT sls_price    FROM silver.crm_sales_details WHERE sls_price    IS NULL OR sls_price    <= 0;

SELECT *
FROM silver.crm_sales_details
WHERE sls_sales != sls_quantity * ABS(sls_price)
   OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL;

--------------------------------------------------------------------------------
-- Table: silver.erp_cust_az12
--------------------------------------------------------------------------------

SELECT
    cid,
    COUNT(*) AS occurrence_count
FROM silver.erp_cust_az12
GROUP BY cid
HAVING COUNT(*) > 1;

SELECT cid FROM silver.erp_cust_az12 WHERE cid LIKE 'NAS%';
SELECT cid FROM silver.erp_cust_az12 WHERE cid != TRIM(cid);
SELECT bdate FROM silver.erp_cust_az12 WHERE bdate > GETDATE();

SELECT DISTINCT gen
FROM silver.erp_cust_az12
WHERE gen NOT IN ('Male', 'Female', 'n/a');

--------------------------------------------------------------------------------
-- Table: silver.erp_loc_a101
--------------------------------------------------------------------------------

-- NOTE: transformation only strips '-' from cid, never applies TRIM() to
-- it -- a nonzero result on the second check is a real, uncorrected gap.
SELECT cid FROM silver.erp_loc_a101 WHERE cid LIKE '%-%';
SELECT cid FROM silver.erp_loc_a101 WHERE cid != TRIM(cid);

SELECT cntry FROM silver.erp_loc_a101 WHERE cntry IS NULL OR cntry = '';
SELECT cntry FROM silver.erp_loc_a101 WHERE cntry IN ('DE', 'USA', 'US');
SELECT cntry FROM silver.erp_loc_a101 WHERE cntry != TRIM(cntry);

--------------------------------------------------------------------------------
-- Table: silver.erp_px_cat_g1v2
--------------------------------------------------------------------------------

SELECT cat    FROM silver.erp_px_cat_g1v2 WHERE cat    != TRIM(cat);
SELECT subcat FROM silver.erp_px_cat_g1v2 WHERE subcat != TRIM(subcat);

-- NOTE: maintenance is never trimmed or standardized by the transformation
-- -- a nonzero result on the first check is a real, uncorrected gap.
SELECT maintenance FROM silver.erp_px_cat_g1v2 WHERE maintenance != TRIM(maintenance);
SELECT DISTINCT maintenance FROM silver.erp_px_cat_g1v2;