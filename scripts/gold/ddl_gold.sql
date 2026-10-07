/* ============================================================================
   Script Name     : ddl_gold.sql
   Description     : Creates the Gold layer views — business-ready,
                      dimensionally-modeled data built on top of Silver.
                      dim_customers and dim_products are dimension views with
                      warehouse-generated surrogate keys (customer_key,
                      product_key); fact_sales joins to those dimensions via
                      their surrogate keys only, never business keys,
                      following standard Kimball star-schema convention.
                      Unlike Bronze/Silver, Gold has no separate load
                      procedure -- these are views, not tables, and compute
                      their result live from Silver on every query.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : SELECT on schema [silver]; CREATE VIEW, ALTER on [gold]
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
-- Customer dimension — CRM is the primary source; ERP fills gender when CRM
-- has no value, and supplies birthdate/country (CRM has no equivalent).
--------------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
    ci.cst_id                              AS customer_id,
    ci.cst_key                             AS customer_number,
    ci.cst_firstname                       AS first_name,
    ci.cst_lastname                        AS last_name,
    ci.cst_marital_status                  AS marital_status,
    CASE
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr   -- CRM is primary source for gender
        ELSE COALESCE(ca.gen, 'n/a')                 -- fallback to ERP
    END                                     AS gender,
    ca.bdate                                AS birthdate,
    cl.cntry                                AS country,
    ci.cst_create_date                      AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 cl ON ci.cst_key = cl.cid;
GO

--------------------------------------------------------------------------------
-- View: gold.dim_products
-- Product dimension — current products only (prd_end_dt IS NULL excludes
-- historical/superseded product versions). ERP category lookup falls back
-- to the raw CRM category code when no match exists.
--------------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY prd.prd_start_dt, prd.prd_key) AS product_key,
    prd.prd_id                                                  AS product_id,
    prd.prd_key                                                 AS product_number,
    prd.prd_nm                                                  AS product_name,
    pc.id                                                       AS category_id,
    CASE
        WHEN pc.cat IS NULL THEN prd.prd_cat   -- fallback when no ERP category match
        ELSE pc.cat
    END                                                          AS category,
    pc.subcat                                                   AS subcategory,
    prd.prd_cost                                                AS cost,
    prd.prd_line                                                AS product_line,
    pc.maintenance                                               AS maintenance,
    prd.prd_start_dt                                            AS start_date
FROM silver.crm_prd_info prd
LEFT JOIN silver.erp_px_cat_g1v2 pc ON prd.prd_cat = pc.id
WHERE prd.prd_end_dt IS NULL;
GO

--------------------------------------------------------------------------------
-- View: gold.fact_sales
-- Sales fact table — joins to dimensions via surrogate keys only
-- (customer_key, product_key), never via business keys.
--------------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num AS order_number,
    prd.product_key AS product_key,
    ci.customer_key AS customer_key,
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt  AS ship_date,
    sd.sls_due_dt   AS due_date,
    sd.sls_sales    AS sales,
    sd.sls_quantity AS quantity,
    sd.sls_price    AS price
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_customers ci ON sd.sls_cust_id  = ci.customer_id
LEFT JOIN gold.dim_products  prd ON sd.sls_prd_key = prd.product_number;
GO