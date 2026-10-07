/* ============================================================================
   Script Name     : data_quality_checks_gold.sql
   Description     : Data quality / referential integrity checks against the
                      Gold layer (gold.dim_customers, gold.dim_products,
                      gold.fact_sales). Validates what the views actually
                      guarantee by construction, and separately flags known,
                      investigated gaps in the current source dataset (e.g.
                      unmatched ERP category codes) that are expected to
                      return rows, not bugs to chase.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : SELECT on schema [gold]
   ----------------------------------------------------------------------------
   Revision History
   Date        Author              Version   Description
   ----------  ------------------  --------  ---------------------------------
   2026-10-05  Mohammed Abuteir    1.0.0     Initial documented version
   ============================================================================ */

SET NOCOUNT ON;
GO

--------------------------------------------------------------------------------
-- View: gold.dim_customers
--------------------------------------------------------------------------------

-- Surrogate key should always be unique and non-null by construction
-- (ROW_NUMBER() OVER (...)). Should always return zero rows.
SELECT
    customer_key,
    COUNT(*) AS occurrence_count
FROM gold.dim_customers
GROUP BY customer_key
HAVING COUNT(*) > 1 OR customer_key IS NULL;

-- Business key (customer_id) should never be NULL -- carried straight from
-- silver.crm_cust_info.cst_id, which Silver already filters NOT NULL.
SELECT customer_id FROM gold.dim_customers WHERE customer_id IS NULL;

-- Confirmed domain -- same mapping as the Silver layer.
SELECT DISTINCT gender
FROM gold.dim_customers
WHERE gender NOT IN ('Male', 'Female', 'n/a');

SELECT DISTINCT marital_status
FROM gold.dim_customers
WHERE marital_status NOT IN ('Single', 'Married', 'n/a');

-- NOTE: birthdate and country come only from the ERP LEFT JOINs
-- (erp_cust_az12, erp_loc_a101) -- there is no CRM-side fallback for either,
-- unlike gender. A customer with no matching ERP row will show NULL here by
-- design, not as an error. Informational count only.
SELECT
    SUM(CASE WHEN birthdate IS NULL THEN 1 ELSE 0 END) AS null_birthdate_count,
    SUM(CASE WHEN country   IS NULL THEN 1 ELSE 0 END) AS null_country_count
FROM gold.dim_customers;

--------------------------------------------------------------------------------
-- View: gold.dim_products
--------------------------------------------------------------------------------

-- Surrogate key should always be unique and non-null by construction.
SELECT
    product_key,
    COUNT(*) AS occurrence_count
FROM gold.dim_products
GROUP BY product_key
HAVING COUNT(*) > 1 OR product_key IS NULL;

-- Business key (product_id) should never be NULL.
SELECT product_id FROM gold.dim_products WHERE product_id IS NULL;

-- category should NEVER be NULL -- the CASE fallback guarantees it falls
-- back to the raw prd_cat code when no ERP category match exists. Should
-- always return zero rows; a result here means the fallback itself broke.
SELECT product_number, category
FROM gold.dim_products
WHERE category IS NULL;

-- NOTE: subcategory and maintenance have NO fallback -- they come only from
-- the ERP LEFT JOIN (erp_px_cat_g1v2) and will be NULL whenever category
-- fell back to the raw code. This is a KNOWN, INVESTIGATED gap in the
-- current source data: specific prd_cat codes (confirmed so far: AC_BC,
-- and a CO_PD/CO_PE naming mismatch between CRM and ERP) have no matching
-- row in erp_px_cat_g1v2 at all. A nonzero result below is expected, not a
-- new bug -- cross-check the category_id values against this known list
-- before investigating further.
SELECT DISTINCT product_number, category_id, category
FROM gold.dim_products
WHERE subcategory IS NULL OR maintenance IS NULL;

--------------------------------------------------------------------------------
-- View: gold.fact_sales
--------------------------------------------------------------------------------

-- Grain check: one row per (order_number, product_key) should be unique.
-- A result here means the fact table has duplicate line items for the same
-- order/product combination -- a real grain violation worth investigating.
SELECT
    order_number,
    product_key,
    COUNT(*) AS occurrence_count
FROM gold.fact_sales
GROUP BY order_number, product_key
HAVING COUNT(*) > 1;

-- Referential integrity: every fact row should resolve to a real dimension
-- row. NOTE: customer_key can be NULL if sls_cust_id has no match in
-- dim_customers; product_key can be NULL if sls_prd_key references a
-- product that is not "current" (dim_products only keeps
-- prd_end_dt IS NULL rows) -- i.e. a sale against a superseded product
-- version. Both are documented, known gaps in the model, not unexpected
-- bugs -- but worth tracking the volume.
SELECT
    SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END) AS orphaned_customer_key_count,
    SUM(CASE WHEN product_key  IS NULL THEN 1 ELSE 0 END) AS orphaned_product_key_count,
    COUNT(*)                                                AS total_fact_rows
FROM gold.fact_sales;

-- sales / quantity / price should all be valid positive numbers -- carried
-- through from Silver's correction logic. NOTE: inherits the same known
-- edge case documented in data_quality_checks_silver.sql (the three
-- correction CASE blocks don't chain off each other), so a nonzero result
-- here is a real, previously-flagged limitation, not new.
SELECT * FROM gold.fact_sales WHERE sales    IS NULL OR sales    <= 0;
SELECT * FROM gold.fact_sales WHERE quantity IS NULL OR quantity <= 0;
SELECT * FROM gold.fact_sales WHERE price    IS NULL OR price    <= 0;

-- Logical date order (order <= ship <= due) -- not enforced anywhere in the
-- pipeline, same as the Silver-layer check. A nonzero result is real.
SELECT *
FROM gold.fact_sales
WHERE order_date > ship_date OR ship_date > due_date;