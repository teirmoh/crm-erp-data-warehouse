/* ============================================================================
   Script Name     : ddl_silver.sql
   Description     : Creates (drops and recreates) the Silver layer tables
                      for CRM and ERP data. Mirrors the Bronze layer schema
                      with two changes: (1) columns are widened/typed toward
                      their cleansed/business form (e.g. sls_order_dt as DATE
                      instead of Bronze's raw INT), and (2) each table carries
                      a dwh_create_date audit column to track when a row was
                      loaded into the warehouse.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : ALTER, CREATE TABLE, DROP TABLE on schema [silver]
   ----------------------------------------------------------------------------
   Revision History
   Date        Author              Version   Description
   ----------  ------------------  --------  ---------------------------------
   2026-09-23  Mohammed Abuteir    1.0.0     Initial documented version
   ============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ============================================================================
   CAUTION: DESTRUCTIVE OPERATION
   The blocks below DROP existing tables in the [silver] schema if they exist.
   Any data currently residing in these tables will be PERMANENTLY LOST.
   Silver tables are expected to be fully rebuilt from Bronze on each run of
   the Silver load procedure, so this is expected behavior -- confirm this is
   the intended pattern before running against a non-dev environment.
   ============================================================================ */

--------------------------------------------------------------------------------
-- Table: silver.crm_cust_info
-- Cleansed CRM customer master data
--------------------------------------------------------------------------------
IF OBJECT_ID('silver.crm_cust_info', 'U') IS NOT NULL
    DROP TABLE silver.crm_cust_info;
GO

CREATE TABLE silver.crm_cust_info
(
    cst_id              INT,
    cst_key             NVARCHAR(10),
    cst_firstname       NVARCHAR(30),
    cst_lastname        NVARCHAR(30),
    cst_marital_status  NVARCHAR(10),
    cst_gndr            NVARCHAR(10),
    cst_create_date     DATE,
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);
GO

--------------------------------------------------------------------------------
-- Table: silver.crm_prd_info
-- Cleansed CRM product master data
--------------------------------------------------------------------------------
IF OBJECT_ID('silver.crm_prd_info', 'U') IS NOT NULL
    DROP TABLE silver.crm_prd_info;
GO

CREATE TABLE silver.crm_prd_info
(
    prd_id           INT,
	prd_cat			 NVARCHAR(10),
    prd_key          NVARCHAR(20),
    prd_nm           NVARCHAR(30),
    prd_cost         INT,
    prd_line         NVARCHAR(15),
    prd_start_dt     DATE,
    prd_end_dt       DATE,
    dwh_create_date  DATETIME2 DEFAULT GETDATE()
);
GO

--------------------------------------------------------------------------------
-- Table: silver.crm_sales_details
-- Cleansed CRM sales transaction line detail
-- NOTE: sls_order_dt / sls_ship_dt / sls_due_dt are DATE here (vs. Bronze's
--       raw INT), reflecting the type cast that happens during Bronze ->
--       Silver transformation.
--------------------------------------------------------------------------------
IF OBJECT_ID('silver.crm_sales_details', 'U') IS NOT NULL
    DROP TABLE silver.crm_sales_details;
GO

CREATE TABLE silver.crm_sales_details
(
    sls_ord_num      NVARCHAR(10),
    sls_prd_key      NVARCHAR(10),
    sls_cust_id      INT,
    sls_order_dt     DATE,
    sls_ship_dt      DATE,
    sls_due_dt       DATE,
    sls_sales        INT,
    sls_quantity     INT,
    sls_price        INT,
    dwh_create_date  DATETIME2 DEFAULT GETDATE()
);
GO

--------------------------------------------------------------------------------
-- Table: silver.erp_cust_az12
-- Cleansed ERP customer demographic data (AZ12 feed)
--------------------------------------------------------------------------------
IF OBJECT_ID('silver.erp_cust_az12', 'U') IS NOT NULL
    DROP TABLE silver.erp_cust_az12;
GO

CREATE TABLE silver.erp_cust_az12
(
    CID              NVARCHAR(15),
    BDATE            DATE,
    GEN              NVARCHAR(10),
    dwh_create_date  DATETIME2 DEFAULT GETDATE()
);
GO

--------------------------------------------------------------------------------
-- Table: silver.erp_loc_a101
-- Cleansed ERP customer location data (A101 feed)
--------------------------------------------------------------------------------
IF OBJECT_ID('silver.erp_loc_a101', 'U') IS NOT NULL
    DROP TABLE silver.erp_loc_a101;
GO

CREATE TABLE silver.erp_loc_a101
(
    CID              NVARCHAR(15),
    CNTRY            NVARCHAR(15),
    dwh_create_date  DATETIME2 DEFAULT GETDATE()
);
GO

--------------------------------------------------------------------------------
-- Table: silver.erp_px_cat_g1v2
-- Cleansed ERP product category / maintenance reference data (PX feed)
--------------------------------------------------------------------------------
IF OBJECT_ID('silver.erp_px_cat_g1v2', 'U') IS NOT NULL
    DROP TABLE silver.erp_px_cat_g1v2;
GO

CREATE TABLE silver.erp_px_cat_g1v2
(
    ID               NVARCHAR(5),
    CAT              NVARCHAR(15),
    SUBCAT           NVARCHAR(15),
    MAINTENANCE      NVARCHAR(5),
    dwh_create_date  DATETIME2 DEFAULT GETDATE()
);
GO