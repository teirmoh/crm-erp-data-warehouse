/* ============================================================================
   Script Name     : ddl_bronze.sql
   Description     : Creates (drops and recreates) the Bronze layer staging 
                      tables for CRM and ERP source system ingestion.
                      Includes: crm_cust_info, crm_prd_info, crm_sales_details,
                      erp_cust_az12, erp_loc_a101, erp_px_cat_g1v2.
   Author          : Mohammed Abuteir
   Version         : 1.0.0
   Target Platform : Microsoft SQL Server 2016+
   Required Perms  : ALTER, CREATE TABLE, DROP TABLE on schema [bronze]
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
   The blocks below DROP existing tables in the [bronze] schema if they exist.
   Any data currently residing in these tables will be PERMANENTLY LOST.
   Bronze tables are expected to be re-populated in full on each load, so this
   is expected behavior for a full-refresh staging layer -- confirm this is
   the intended load pattern before running against a non-dev environment.
   ============================================================================ */

--------------------------------------------------------------------------------
-- Table: bronze.crm_cust_info
-- CRM source: customer master data
--------------------------------------------------------------------------------
IF OBJECT_ID('bronze.crm_cust_info', 'U') IS NOT NULL
    DROP TABLE bronze.crm_cust_info;
GO

CREATE TABLE bronze.crm_cust_info
(
    cst_id              INT,
    cst_key             NVARCHAR(10),
    cst_firstname       NVARCHAR(30),
    cst_lastname        NVARCHAR(30),
    cst_marital_status  CHAR(1),
    cst_gndr            CHAR(1),
    cst_create_date     DATE
);
GO

--------------------------------------------------------------------------------
-- Table: bronze.crm_prd_info
-- CRM source: product master data
--------------------------------------------------------------------------------
IF OBJECT_ID('bronze.crm_prd_info', 'U') IS NOT NULL
    DROP TABLE bronze.crm_prd_info;
GO

CREATE TABLE bronze.crm_prd_info
(
    prd_id        INT,
    prd_key       NVARCHAR(20),
    prd_nm        NVARCHAR(30),
    prd_cost      INT,
    prd_line      NVARCHAR(5),
    prd_start_dt  DATETIME,
    prd_end_dt    DATETIME
);
GO

--------------------------------------------------------------------------------
-- Table: bronze.crm_sales_details
-- CRM source: sales transaction line detail
-- NOTE: sls_order_dt / sls_ship_dt / sls_due_dt are ingested as INT (raw
--       source format, e.g. YYYYMMDD) and are expected to be cast to DATE
--       during the Silver layer transformation, not at Bronze ingestion.
--------------------------------------------------------------------------------
IF OBJECT_ID('bronze.crm_sales_details', 'U') IS NOT NULL
    DROP TABLE bronze.crm_sales_details;
GO

CREATE TABLE bronze.crm_sales_details
(
    sls_ord_num    NVARCHAR(10),
    sls_prd_key    NVARCHAR(10),
    sls_cust_id    INT,
    sls_order_dt   INT,
    sls_ship_dt    INT,
    sls_due_dt     INT,
    sls_sales      INT,
    sls_quantity   INT,
    sls_price      INT
);
GO

--------------------------------------------------------------------------------
-- Table: bronze.erp_cust_az12
-- ERP source: customer demographic extract (AZ12 feed)
--------------------------------------------------------------------------------
IF OBJECT_ID('bronze.erp_cust_az12', 'U') IS NOT NULL
    DROP TABLE bronze.erp_cust_az12;
GO

CREATE TABLE bronze.erp_cust_az12
(
    CID    NVARCHAR(15),
    BDATE  DATE,
    GEN    NVARCHAR(10)
);
GO

--------------------------------------------------------------------------------
-- Table: bronze.erp_loc_a101
-- ERP source: customer location extract (A101 feed)
--------------------------------------------------------------------------------
IF OBJECT_ID('bronze.erp_loc_a101', 'U') IS NOT NULL
    DROP TABLE bronze.erp_loc_a101;
GO

CREATE TABLE bronze.erp_loc_a101
(
    CID    NVARCHAR(15),
    CNTRY  NVARCHAR(15)
);
GO

--------------------------------------------------------------------------------
-- Table: bronze.erp_px_cat_g1v2
-- ERP source: product category / maintenance reference extract (PX feed)
--------------------------------------------------------------------------------
IF OBJECT_ID('bronze.erp_px_cat_g1v2', 'U') IS NOT NULL
    DROP TABLE bronze.erp_px_cat_g1v2;
GO

CREATE TABLE bronze.erp_px_cat_g1v2
(
    ID           NVARCHAR(5),
    CAT          NVARCHAR(15),
    SUBCAT       NVARCHAR(15),
    MAINTENANCE  NVARCHAR(5)
);
GO