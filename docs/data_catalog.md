# Data Catalog — Gold Layer

Overview of the business-ready, analytics-facing objects in the `gold`
schema. These are **views**, not tables — each computes its result live from
the `silver` schema on every query; there is no separate load step for Gold.

---

## gold.dim_customers

**Purpose:** Customer dimension. One row per unique customer. CRM
(`silver.crm_cust_info`) is the primary source; ERP tables
(`silver.erp_cust_az12`, `silver.erp_loc_a101`) supplement it with
demographic and location data, and act as a fallback for gender when CRM
has no value.

**Grain:** One row per customer.

| Column | Data Type | Description |
|---|---|---|
| `customer_key` | `INT` | Surrogate key. Warehouse-generated, sequential, uniquely identifies each customer row in the Gold layer. Use this for all joins to `fact_sales` — never the business keys below. |
| `customer_id` | `INT` | Business key from the source CRM system (`cst_id`). Stable identifier as assigned by CRM. |
| `customer_number` | `NVARCHAR(10)` | Alternate customer identifier from CRM (`cst_key`). Used to join to ERP source tables. |
| `first_name` | `NVARCHAR(30)` | Customer's first name, trimmed. |
| `last_name` | `NVARCHAR(30)` | Customer's last name, trimmed. |
| `marital_status` | `NVARCHAR(10)` | Standardized marital status: `Single`, `Married`, or `n/a` if unknown/unmapped. |
| `gender` | `NVARCHAR(10)` | Standardized gender: `Male`, `Female`, or `n/a`. CRM value is used when present; falls back to the ERP value (`erp_cust_az12.gen`) when CRM's value is `n/a`. |
| `birthdate` | `DATE` | Customer's date of birth, sourced from ERP only (no CRM equivalent). Future-dated values are nulled out as invalid. **Can be `NULL`** if no matching ERP customer record exists. |
| `country` | `NVARCHAR(50)` | Customer's country, standardized (e.g. `US`/`USA` → `United States`), sourced from ERP only (no CRM equivalent). **Can be `NULL`** if no matching ERP location record exists. |
| `create_date` | `DATE` | Date the customer record was created in the source CRM system. |

**Known gaps:**
- `birthdate` / `country` are `NULL` for any customer with no matching row
  in the respective ERP source table — there is no fallback for these two
  columns (unlike `gender`).

---

## gold.dim_products

**Purpose:** Product dimension. **Current products only** — historical/
superseded product versions are excluded. CRM (`silver.crm_prd_info`) is
the primary source; ERP (`silver.erp_px_cat_g1v2`) supplements it with
category metadata.

**Grain:** One row per currently-active product (`prd_end_dt IS NULL` in
the underlying Silver filter).

| Column | Data Type | Description |
|---|---|---|
| `product_key` | `INT` | Surrogate key. Warehouse-generated, uniquely identifies each product row in the Gold layer. Use this for all joins to `fact_sales` — never the business keys below. |
| `product_id` | `INT` | Business key from the source CRM system (`prd_id`). |
| `product_number` | `NVARCHAR(20)` | Product key as used in sales transactions, with the category-code prefix stripped (`prd_key` in Silver, extracted from the raw CRM `prd_key`). |
| `product_name` | `NVARCHAR(30)` | Product name/description. |
| `category_id` | `NVARCHAR(5)` | Category code as it appears in the ERP category reference table (`erp_px_cat_g1v2.id`). `NULL` when no matching ERP category row exists. |
| `category` | `NVARCHAR(15)` | Product category, human-readable. Sourced from ERP when a match exists; **falls back to the raw CRM category code** (`prd_cat`) when no ERP match exists, so this column is never `NULL`. |
| `subcategory` | `NVARCHAR(15)` | Product subcategory, sourced from ERP only — **no fallback**. `NULL` whenever `category` fell back to the raw CRM code. |
| `cost` | `INT` | Product cost. Defaults to `0` if missing in the source. |
| `product_line` | `NVARCHAR(15)` | Standardized product line: `Mountain`, `Road`, `Other Sales`, `Touring`, or `n/a`. |
| `maintenance` | `NVARCHAR(5)` | Whether the product requires maintenance (`Yes`/`No`), sourced from ERP only — **no fallback**. `NULL` whenever `category` fell back to the raw CRM code. |
| `start_date` | `DATE` | Date this product version became active. |

**Known gaps:**
- A small number of CRM category codes (confirmed: `AC_BC`; also a
  `CO_PD`/`CO_PE` naming mismatch between CRM and ERP) have no matching row
  in `erp_px_cat_g1v2`. For these products, `category` shows the raw CRM
  code instead of the ERP-mapped name, and `subcategory`/`maintenance` are
  `NULL` (no fallback exists for those two columns).
- Products that have been superseded by a newer version (non-current) are
  **excluded entirely** from this view — sales referencing them will show a
  `NULL` `product_key` in `fact_sales`.

---

## gold.fact_sales

**Purpose:** Sales fact table. One row per order line item. Joins to both
dimensions exclusively via surrogate keys (`customer_key`, `product_key`),
never via business keys — standard Kimball star-schema convention.

**Grain:** One row per order line item (`order_number` + `product_key`
combination within a single sales transaction).

| Column | Data Type | Description |
|---|---|---|
| `order_number` | `NVARCHAR(10)` | Sales order identifier, trimmed. |
| `product_key` | `INT` | Foreign key to `gold.dim_products.product_key`. **Can be `NULL`** — see known gaps below. |
| `customer_key` | `INT` | Foreign key to `gold.dim_customers.customer_key`. |
| `order_date` | `DATE` | Date the order was placed. `NULL` if the raw source date was unparseable (not an 8-digit value). |
| `ship_date` | `DATE` | Date the order shipped. `NULL` if the raw source date was unparseable. |
| `due_date` | `DATE` | Date the order was due. `NULL` if the raw source date was unparseable. |
| `sales` | `INT` | Total sales amount for the line item. Recalculated as `quantity × |price|` when the raw source value was missing, non-positive, or inconsistent with quantity/price. |
| `quantity` | `INT` | Quantity ordered. Derived from `sales` and `price` when the raw source value was missing or non-positive. |
| `price` | `INT` | Unit price. Derived from `sales` and `quantity` when the raw source value was missing or non-positive. |

**Known gaps:**
- `product_key` is `NULL` for 409 rows — all 409 trace to a single cause: a
  sale referencing product key `SJ-0194-X`, a jersey size variant (XL) that
  exists in sales history but was never added to the CRM product master
  (`crm_prd_info` only has S/M/L for that product line). Confirmed source
  data gap, not a pipeline defect.
- `sales` / `quantity` / `price` correction logic evaluates each of the
  three fields independently against the *original* Bronze values rather
  than chaining off each other's corrected output. A row with more than one
  of these fields simultaneously invalid in Bronze can still fail the
  `sales = quantity × |price|` invariant after transformation. See
  `tests/data_quality_checks_silver.sql` for the validation query.
- Logical date ordering (`order_date ≤ ship_date ≤ due_date`) is **not
  enforced** anywhere in the pipeline.

---

## Source Lineage Summary

```
bronze.crm_cust_info  ──┐
bronze.erp_cust_az12  ──┼──> silver.* (cleansed/typed) ──> gold.dim_customers
bronze.erp_loc_a101   ──┘

bronze.crm_prd_info      ──┐
bronze.erp_px_cat_g1v2   ──┴──> silver.* (cleansed/typed) ──> gold.dim_products

bronze.crm_sales_details ───> silver.crm_sales_details ───> gold.fact_sales
                                                              (joins to dim_customers,
                                                               dim_products via surrogate keys)
```

See `docs/data_model.drawio.png` for the visual ERD, and
`scripts/gold/ddl_gold.sql` for the view definitions.
