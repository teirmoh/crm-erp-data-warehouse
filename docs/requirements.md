# Data Warehouse Requirements Analysis

*Sales & Customer Analytics — Sourced from CRM and ERP Systems*

---

## RA-01 — Business Problem

The business currently holds customer, product, and sales data scattered across two disconnected operational systems (a CRM and an ERP), each using its own keys, formats, and codes. There is no unified, analysis-ready view of **who is buying what, where, and how much revenue and volume that generates over time**.

This project builds a data warehouse that integrates the CRM and ERP extracts into clean, conformed dimensions and a sales fact table, so the business can reliably answer sales-performance, customer, and product questions without manually reconciling six raw files.

## RA-02 — Source Systems

Two operational source systems, delivered as six flat-file (CSV) extracts:

| System | File | Approx. Rows | Contents |
|---|---|---|---|
| CRM | `cust_info.csv` | ~18.5K | Customer master: ID, key, name, marital status, gender, create date |
| CRM | `prd_info.csv` | ~398 | Product master: ID, key, name, cost, product line, start/end dates |
| CRM | `sales_details.csv` | ~60.4K | Sales transactions: order/ship/due dates, customer, product, sales amount, quantity, price |
| ERP | `CUST_AZ12.csv` | ~18.5K | Customer supplement: birthdate, gender |
| ERP | `LOC_A101.csv` | ~18.5K | Customer location: country |
| ERP | `PX_CAT_G1V2.csv` | 37 | Product category reference: category, subcategory, maintenance flag |

**Known integration issues found during profiling** (to resolve in the transform layer, not in scope for this document beyond noting them):
- Customer keys differ in format between CRM (`AW00011000`) and ERP (`AW-00011000`, `NASAW00011000`) — need normalization to join.
- Country values are inconsistent (`DE`, `Germany`, `US`, `USA`, `United States`, blanks) — need standardization.
- Product keys differ in format between the CRM product master (`CO-RF-FR-R92B-58`) and the sales fact (`BK-M18B-40`) — category prefix must be derived/matched, not assumed identical.
- `prd_cost` has nulls (2 rows); `sls_sales`, `sls_quantity`, `sls_price` have a small number of nulls/blanks (8 rows) that need a handling rule (exclude, impute, or flag).
- CRM `prd_info.prd_end_dt` is frequently blank, and some end dates predate start dates — history/SCD logic needs a documented rule.
- Name and free-text fields (e.g., `cst_firstname`) contain inconsistent leading/trailing whitespace.

## RA-03 — Business Processes

The data warehouse covers one core business process, with two supporting master-data processes:

- **Sales order process (core, transactional):** an order is placed for a customer against one or more products, with order/ship/due dates and quantity, unit price, and sales amount. This is the process that drives the fact table.
- **Customer management (supporting, master data):** customer records are created and maintained in the CRM, enriched with demographic (birthdate, gender) and geographic (country) attributes from the ERP.
- **Product management (supporting, master data):** products are defined in the CRM with cost and a product line, and classified into category/subcategory in the ERP.

## RA-04 — Business Questions

Representative questions the warehouse should be able to answer:

1. What is total sales revenue and order volume by month, quarter, and year?
2. Which products / product categories / subcategories generate the most revenue and quantity sold?
3. Who are the top customers by revenue, and how does spend break down by country, gender, or marital status?
4. What is average order value, and how does it trend over time?
5. How long does it typically take from order date to ship date, and to due date (fulfillment lead time)?
6. Which product lines are growing or declining year over year?
7. What share of sales comes from new vs. returning customers?
8. Which countries/regions contribute the most revenue, and how is that changing over time?

## RA-05 — KPIs and Metric Definitions

| KPI | Definition | Source field(s) |
|---|---|---|
| Total Sales Revenue | Sum of `sls_sales` for a given period/segment | `sales_details.sls_sales` |
| Total Quantity Sold | Sum of `sls_quantity` | `sales_details.sls_quantity` |
| Average Order Value | Total Sales Revenue ÷ distinct `sls_ord_num` count | derived |
| Average Selling Price | Total Sales Revenue ÷ Total Quantity Sold (should reconcile to `sls_price`) | derived |
| Order Count | Count of distinct `sls_ord_num` | `sales_details.sls_ord_num` |
| Fulfillment Lead Time (days) | `sls_ship_dt − sls_order_dt` | `sales_details` |
| On-Time Delivery Indicator | `sls_ship_dt ≤ sls_due_dt` | `sales_details` |
| Gross Margin (if in scope) | Sales Revenue − (Quantity × `prd_cost`) | `sales_details` + `prd_info.prd_cost` |
| Active Customer Count | Distinct customers with ≥1 order in period | `sales_details.sls_cust_id` |
| Revenue by Country | Total Sales Revenue grouped by standardized `CNTRY` | `sales_details` + `LOC_A101` |

All revenue/quantity KPIs should be built to exclude or flag the small number of rows with null `sls_sales`/`sls_quantity`/`sls_price` per the rule agreed with the business (see RA-02, RA-08).

## RA-06 — Candidate Fact Tables

**`FACT_SALES`** — grain: **one row per sales order line** (one `sls_ord_num` + `sls_prd_key` combination).

| Column | Type | Notes |
|---|---|---|
| Order Number | degenerate dimension | `sls_ord_num` |
| Customer Key | FK → `DIM_CUSTOMER` | from `sls_cust_id` |
| Product Key | FK → `DIM_PRODUCT` | from `sls_prd_key` |
| Order Date Key | FK → `DIM_DATE` | from `sls_order_dt` |
| Ship Date Key | FK → `DIM_DATE` | from `sls_ship_dt` |
| Due Date Key | FK → `DIM_DATE` | from `sls_due_dt` |
| Sales Amount | measure | `sls_sales` |
| Quantity | measure | `sls_quantity` |
| Price | measure | `sls_price` |

A future, separately scoped fact table could track **inventory/cost** if unit cost history (`prd_cost` by `prd_start_dt`/`prd_end_dt`) needs to be modeled as a slowly changing measure — noted as out of scope for now (see RA-08).

## RA-07 — Candidate Dimensions

| Dimension | Grain | Primary source(s) | Key attributes |
|---|---|---|---|
| `DIM_CUSTOMER` | one row per customer | `cust_info` + `CUST_AZ12` + `LOC_A101` | customer key, name, marital status, gender (reconciled between CRM/ERP), birthdate, country, create date |
| `DIM_PRODUCT` | one row per product (with history, if SCD2 is adopted) | `prd_info` + `PX_CAT_G1V2` | product key, name, category, subcategory, product line, cost, maintenance flag, start/end date |
| `DIM_DATE` | one row per calendar day | generated | date, day, month, quarter, year, weekday, fiscal period |

Gender is captured in both `cust_info` (CRM) and `CUST_AZ12` (ERP) and will need a documented source-of-truth or reconciliation rule where the two disagree.

## RA-08 — Project Scope and Assumptions

**In scope**
- Integrating the six listed CRM/ERP flat-file extracts into `DIM_CUSTOMER`, `DIM_PRODUCT`, `DIM_DATE`, and `FACT_SALES`.
- Standardizing customer keys, country names, gender values, and trimming free-text fields.
- Building the KPIs listed in RA-05 on top of the warehouse.
- Documenting and applying a consistent rule for the small volume of null/blank measures in `sales_details`.

**Out of scope (for this phase)**
- Real-time or streaming ingestion — this is a batch, file-based load.
- Inventory, procurement, returns, or cost-of-goods-sold processes beyond `prd_cost`.
- Currency conversion (data assumed to be in a single currency; not explicitly indicated in the source).
- Historical tracking (SCD Type 2) for customer/product attribute changes, unless explicitly requested — default assumption is Type 1 (overwrite) with `prd_start_dt`/`prd_end_dt` used only to establish current-vs-historical product records within CRM.

**Assumptions**
- `sls_cust_id` in `sales_details` maps to `cst_id` in `cust_info` (both CRM-native keys).
- The CRM `prd_info.prd_key` and the ERP `PX_CAT_G1V2.ID` share a derivable category-prefix convention that will be confirmed during source-to-target mapping.
- Rows with null core measures (`sls_sales`, `sls_quantity`, `sls_price`) are treated as data-quality exceptions, not valid zero-value transactions, pending business confirmation.
- All dates are in a single time zone/locale; no time-zone normalization is required.

## RA-09 — Requirements Document

This document (RA-01 through RA-08 above) constitutes the requirements document for the project. Recommended next steps to close out RA-09:

1. Circulate this document to stakeholders for sign-off on scope, KPI definitions, and the null-handling/SCD assumptions.
2. Once approved, proceed to source-to-target mapping and physical data model design (star schema DDL for `DIM_CUSTOMER`, `DIM_PRODUCT`, `DIM_DATE`, `FACT_SALES`).
3. Track open questions raised in RA-02 (key formats, gender reconciliation, product-key matching) as explicit tickets before the transform layer is built.
