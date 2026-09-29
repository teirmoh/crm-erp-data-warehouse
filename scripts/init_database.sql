/*******************************************************************************
Script Name:    01_Reset_And_Create_DataWarehouse.sql
Description:    Recreates the 'DataWarehouse' database from scratch and sets up 
                the Medallion Architecture schemas (Bronze, Silver, Gold).

================================================================================
  1. HEADER METADATA & CHANGE LOG
================================================================================
  * Author:            Data Engineering Team
  * Version:           1.1.0
  * Created Date:      2026-09-21
  * Target Platform:   SQL Server 2019+ / Azure SQL Managed Instance
  * Required Roles:    sysadmin OR dbcreator

  Change History:
  ------------------------------------------------------------------------------
  Date        Version   Author                 Description
  ------------------------------------------------------------------------------
  2026-09-15  1.0.0     Data Engineering Team  Initial creation with Medallion schemas.
  2026-09-21  1.1.0     Data Engineering Team  Added forced database reset logic & safety checks.

================================================================================
  2. CAUTION / WARNING: DESTRUCTIVE SCRIPT
================================================================================
  * Running this script will PERMANENTLY DELETE the 'DataWarehouse' database 
    and ALL tables, schemas, views, stored procedures, and data contained within it.
  * DO NOT execute this script in a PRODUCTION or STAGING environment unless 
    you explicitly intend to perform a complete wipe and reset.
  * Active connections will be forcibly terminated, rolling back any uncommitted
    transactions immediately.

================================================================================
  3. DATA GOVERNANCE & ARCHITECTURE RULES
================================================================================
  * BRONZE SCHEMA:
      - Objective: Landing raw, append-only source data.
      - Rule: No transformation; preserve source column names and data types.
  * SILVER SCHEMA:
      - Objective: Cleaned, deduplicated, and conformed data.
      - Rule: Standardized data types, cleansed nulls, business key mapping.
  * GOLD SCHEMA:
      - Objective: Business-ready reporting layer (Dimensional Modeling).
      - Rule: Optimized for BI/Reporting tools (Star Schemas: Fact & Dim tables).
*******************************************************************************/

-- Set SQL Execution Settings
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- -----------------------------------------------------------------------------
-- Step 1: Switch Context to Master Database
-- Ensures the connection is outside the target database before executing DROP.
-- -----------------------------------------------------------------------------
USE master;
GO

-- -----------------------------------------------------------------------------
-- Step 2: Drop Existing Database (If Exists)
-- -----------------------------------------------------------------------------
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'DataWarehouse')
BEGIN
    PRINT '--------------------------------------------------------------------';
    PRINT 'WARNING: Database [DataWarehouse] exists. Terminating active connections...';
    
    -- Forcefully disconnect active user sessions and rollback active transactions
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    
    PRINT 'Dropping database [DataWarehouse]...';
    DROP DATABASE DataWarehouse;
    
    PRINT 'SUCCESS: Existing database [DataWarehouse] dropped.';
    PRINT '--------------------------------------------------------------------';
END;
GO

-- -----------------------------------------------------------------------------
-- Step 3: Create Fresh Database Instance
-- -----------------------------------------------------------------------------
PRINT 'Creating database [DataWarehouse]...';
CREATE DATABASE DataWarehouse;
GO

-- -----------------------------------------------------------------------------
-- Step 4: Switch Context to New Database
-- -----------------------------------------------------------------------------
USE DataWarehouse;
GO

-- -----------------------------------------------------------------------------
-- Step 5: Establish Medallion Architecture Schemas
-- Note: 'GO' is placed before each 'CREATE SCHEMA' to satisfy the rule that 
-- 'CREATE SCHEMA' must be the first statement in a query batch.
-- -----------------------------------------------------------------------------

-- BRONZE LAYER
PRINT 'Creating schema [bronze]...';
GO
CREATE SCHEMA bronze;
GO

-- SILVER LAYER
PRINT 'Creating schema [silver]...';
GO
CREATE SCHEMA silver;
GO

-- GOLD LAYER
PRINT 'Creating schema [gold]...';
GO
CREATE SCHEMA gold;
GO


-- -----------------------------------------------------------------------------
-- Execution Confirmation
-- -----------------------------------------------------------------------------
PRINT '====================================================================';
PRINT 'SUCCESS: DataWarehouse database and Medallion schemas created successfully!';
PRINT '====================================================================';