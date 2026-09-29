# docs/source_data_analysis.md

## 0. Profiling Confidence Statement

- **Input Type**: Full sample data — the complete extracts were provided and scanned in full (not a partial sample).
- **Sample Size**: 100% of each file's population was profiled programmatically: `cust_info.csv` (18,494 rows), `prd_info.csv` (397 rows), `sales_details.csv` (60,398 rows), `CUST_AZ12.csv` (18,484 rows), `LOC_A101.csv` (18,484 rows), `PX_CAT_G1V2.csv` (37 rows).
- **Caveats**: All percentages, counts, and cardinalities below are computed directly from the provided files — none are schema-based inferences or sample extrapolations. Business meanings and target-layer classification are interpretive (based on column names/context and `docs/requirements.md`), and are flagged as such where relevant. Sensitivity tagging (Section 2) is a heuristic, not a legal determination.

---

## 1. Source Inventory & System Catalog

| Source System | Entity / Table Name | File / Format | Primary / Business Key | Record Count / Volatility | Description |
|---|---|---|---|---|---|
| CRM | `cust_info` | `cust_info.csv` (flat file) | `cst_id` (with quality caveats — see Section 3) | 18,494 rows / append-heavy, low-moderate change rate — `cst_create_date` spans 2025-10-06 to 2026-01-27 | Customer master: identity, name, marital status, gender, create date |
| CRM | `prd_info` | `prd_info.csv` (flat file) | `prd_id` (surrogate, unique); `prd_key` (natural, historized — not unique) | 397 rows / low volume, but high row-per-product multiplicity due to versioning | Product master: identity, name, cost, product line, start/end date (appears to carry historical versions per product) |
| CRM | `sales_details` | `sales_details.csv` (flat file) | Composite: `sls_ord_num` + `sls_prd_key` | 60,398 rows / high — 27,659 distinct orders, `sls_order_dt` spans 2010-12-29 to 2014-01-28 | Sales transaction lines: order/ship/due dates, customer, product, sales amount, quantity, unit price |
| ERP | `CUST_AZ12` | `CUST_AZ12.csv` (flat file) | `CID` (unique, 18,484/18,484 distinct) | 18,484 rows / master-data supplement, refreshed alongside CRM customer base | Customer demographic supplement: birthdate, gender |
| ERP | `LOC_A101` | `LOC_A101.csv` (flat file) | `CID` (unique, 18,484/18,484 distinct) | 18,484 rows / master-data supplement | Customer geography supplement: country |
| ERP | `PX_CAT_G1V2` | `PX_CAT_G1V2.csv` (flat file) | `ID` (unique, 37/37 distinct) | 37 rows / static reference table | Product category reference: category, subcategory, maintenance flag |

Row counts above are the number of data rows read from each file (header excluded).

---

## 2. Source Data Dictionary & Profiling Notes

*Sensitivity classification is a heuristic based on column name/context, not a legal determination. All figures below are computed from the full population of the respective file.*

### Entity: `cust_info` (CRM — Customer Master)

| Column Name | Data Type (observed) | Nullable? | Uniqueness | Sensitivity | Business Meaning | Sample Values | Profiling Notes & Quality Alerts |
|---|---|---|---|---|---|---|---|
| `cst_id` | Numeric string (stored as text) | Yes — 4 blank | 18,485 distinct / 18,494 rows; 9 non-blank values repeated (2–3x) | PII (customer identifier) | CRM-native customer surrogate key | `11000`, `29466` | 4 rows have a blank `cst_id` but a populated, non-numeric `cst_key` (`SF566`, `PO25`, `13451235`, `A01Ass`) with all other fields blank — these look like junk/test trailer rows, not real customers. 9 distinct `cst_id` values appear 2–3 times each with differing `cst_create_date`, consistent with re-registration/record updates rather than random duplication (see DQ-02). |
| `cst_key` | Alphanumeric string | No blanks observed in normal rows (the 4 junk rows above have non-standard values) | 18,488 distinct | PII | CRM natural/business customer key, format `AW########` | `AW00011000` | Format is consistently `AW` + 8 digits for legitimate rows; the 4 junk rows break this pattern (see `cst_id` above). This is the key that ERP files reference (in altered formats — see Section 3, DQ-19). |
| `cst_firstname` | Text | Yes — 8 blank | 688 distinct | PII | Customer first name | ` Jon`, `Eugene` | 17 rows have leading/trailing whitespace (e.g. `' Jon'`, `'  Lauren'`) — needs `TRIM()`. |
| `cst_lastname` | Text | Yes — 7 blank | 398 distinct | PII | Customer last name | `Yang `, ` Torres` | 22 rows have leading/trailing whitespace (e.g. `'Yang '`, `'  Zhu'`) — needs `TRIM()`. |
| `cst_marital_status` | Single-char code | Yes — 7 blank | 3 distinct raw values (`M`, `S`, blank) | None | Marital status flag | `M`, `S` | Clean 2-value code otherwise (M=10,013, S=8,474); needs a decode rule to full text (Married/Single) for the dimension, and a rule for the 7 blanks (Unknown bucket). |
| `cst_gndr` | Single-char code | Yes — 4,578 blank (24.7%) | 3 distinct raw values (`M`, `F`, blank) | PII | Gender (CRM source) | `M`, `F` | Nearly 1 in 4 rows blank. Must be reconciled against `CUST_AZ12.GEN` per RA-07 — CRM is the candidate source of truth per RA-08 assumption, but coverage gap is material and should be confirmed with the business. |
| `cst_create_date` | Date (`YYYY-MM-DD` text) | Yes — 4 blank (same 4 junk rows as `cst_id`) | 115 distinct dates | None | Date the CRM customer record was created | `2025-10-06` | Range: 2025-10-06 to 2026-01-27. Consistently formatted `YYYY-MM-DD` in all non-blank rows. |

### Entity: `prd_info` (CRM — Product Master)

| Column Name | Data Type (observed) | Nullable? | Uniqueness | Sensitivity | Business Meaning | Sample Values | Profiling Notes & Quality Alerts |
|---|---|---|---|---|---|---|---|
| `prd_id` | Numeric string | No | 397/397 distinct (100%) | None | Product surrogate key | `210`, `211` | Clean, fully unique — reliable technical PK. |
| `prd_key` | Alphanumeric, dash-delimited (`CAT-SUB-MODEL-SIZE`) | No | 295 distinct / 397 rows (102 values repeat) | None | Product natural/business key | `CO-RF-FR-R92B-58`, `AC-HE-HL-U509-R` | Not unique — 179 of 397 rows share a `prd_key` with 1–2 other rows, each with a different `prd_start_dt`/`prd_end_dt`, i.e. this table carries historical product versions (see DQ-05). Format differs from `sales_details.sls_prd_key` — confirmed derivable: stripping `prd_key`'s first two dash-segments (the category prefix) produces a 100% match against every distinct `sls_prd_key` value (see Section 4). |
| `prd_nm` | Text | No | 295 distinct (mirrors `prd_key` cardinality) | None | Product display name | `HL Road Frame - Black- 58` | Consistent with `prd_key` versioning pattern. |
| `prd_cost` | Numeric string | Yes — 2 blank | 109 distinct | None | Unit product cost | `12`, `14`, `3` | Range observed: 1–2,171. Only 2 nulls (0.5%), all other values numeric and non-negative. |
| `prd_line` | Single-char code + trailing space | Yes — 17 blank (4.3%) | 5 distinct raw values (`R `, `S `, `M `, `T `, blank — note trailing space is part of the raw value) | None | Product line code | `R `, `S `, `M `, `T ` | Every non-blank value carries a trailing space in the raw file — needs `TRIM()` before decoding. Distribution: R=162, M=112, S=54, T=52, blank=17. No documented decode table was provided; a lookup (e.g., R=Road, M=Mountain, S=Sport/Other, T=Touring) should be confirmed with the business, not assumed. |
| `prd_start_dt` | Date (`YYYY-MM-DD`) | No | 4 distinct dates only (`2003-07-01`, `2011-07-01`, `2012-07-01`, `2013-07-01`) | None | Effective start date of this product version | `2003-07-01` | Only 4 distinct values across 397 rows — consistent with batch-versioned product loads rather than true per-product start dates. |
| `prd_end_dt` | Date (`YYYY-MM-DD`) or blank | Yes — 197 blank (49.6%) | 3 distinct non-blank values | None | Effective end date of this product version | `2007-12-28`, `2008-12-27` | Blank in ~half the rows (interpretable as "currently active" version, consistent with RA-08's Type-1 default). Critically, in 200 of 397 rows (50.4%) the populated `prd_end_dt` is *earlier* than that same row's `prd_start_dt` (e.g. `prd_start_dt=2011-07-01`, `prd_end_dt=2007-12-28`) — this is very high-impact and suggests `prd_end_dt` on a given row may actually represent the prior version's end date rather than this row's own, or a load/shift error (see DQ-07). This needs business/source-system clarification before SCD logic is finalized. |

### Entity: `sales_details` (CRM — Sales Transactions)

| Column Name | Data Type (observed) | Nullable? | Uniqueness | Sensitivity | Business Meaning | Sample Values | Profiling Notes & Quality Alerts |
|---|---|---|---|---|---|---|---|
| `sls_ord_num` | Alphanumeric (`SO#####`) | No | 27,659 distinct / 60,398 rows (expected — one order has multiple lines) | None | Sales order number (degenerate dimension) | `SO43697` | Combined with `sls_prd_key`, forms a unique grain: all 60,398 `(sls_ord_num, sls_prd_key)` pairs are distinct — no duplicate order lines. |
| `sls_prd_key` | Alphanumeric (`MODEL-SIZE`, no category prefix) | No | 130 distinct | None | Product sold (FK candidate) | `BK-R93R-62` | Format differs from `prd_info.prd_key` (missing the 2-segment category prefix) — no `sls_prd_key` value exact-matches `prd_info.prd_key` directly (0/60,398), but 100% match once `prd_info.prd_key`'s first two dash-segments are stripped (see Section 4). Because `prd_info` carries multiple historical rows per stripped key, this join is 1:N on the product side unless resolved to one "current" row. |
| `sls_cust_id` | Numeric string | No | 18,484 distinct | PII | Customer who placed the order (FK candidate) | `21768` | Every value matches a `cust_info.cst_id` (0 orphans) — clean referential integrity to the CRM customer master. |
| `sls_order_dt` | Numeric string, intended `YYYYMMDD` | Effectively yes — 17 rows literal `'0'` (placeholder for missing date) | 1,127 distinct (incl. the `'0'` placeholder) | None | Order placed date | `20101229` | 60,379 rows are well-formed 8-digit dates; 17 rows are the literal value `0` (no real date captured); 1 row is a malformed 5-digit value and 1 row a malformed 4-digit value (both need investigation — likely truncated/mis-keyed). |
| `sls_ship_dt` | Numeric string, `YYYYMMDD` | No | 1,124 distinct | None | Ship date | `20110105` | 100% of rows are well-formed 8-digit dates; never earlier than that row's `sls_order_dt`. |
| `sls_due_dt` | Numeric string, `YYYYMMDD` | No | 1,124 distinct | None | Payment/fulfillment due date | `20110110` | 100% well-formed 8-digit dates; never earlier than `sls_order_dt`. |
| `sls_sales` | Numeric string | Yes — 8 blank | 49 distinct | None | Total line sales amount | `3578`, `3400` | Range: -54 to 3,578. 8 blank (0.01%), 3 negative, 2 exactly zero. In 20/60,398 rows (0.03%), `sls_sales ≠ sls_quantity × sls_price`, so the "should reconcile" assumption in RA-05 holds for 99.97% of rows but is not universal. |
| `sls_quantity` | Numeric string | No | 6 distinct (1–10) | None | Units sold on the line | `1`, `2`, `5` | Fully populated, no blanks, no negatives/zeros — the cleanest measure in the table. |
| `sls_price` | Numeric string | Yes — 7 blank | 47 distinct | None | Unit sales price | `3578`, `3400` | Range: -1,701 to 3,578. 7 blank, 5 negative. Negative-price rows are a distinct set of order lines from the negative/zero-`sls_sales` rows (10 unique lines total flagged across both). |

### Entity: `CUST_AZ12` (ERP — Customer Demographic Supplement)

| Column Name | Data Type (observed) | Nullable? | Uniqueness | Sensitivity | Business Meaning | Sample Values | Profiling Notes & Quality Alerts |
|---|---|---|---|---|---|---|---|
| `CID` | Alphanumeric, two observed prefix formats | No | 18,484/18,484 distinct (100%) | PII | ERP customer identifier (FK candidate to CRM customer) | `NASAW00011000` (11,042 rows), `AW00011000` (7,442 rows) | Two coexisting formats: an `NASAW########` prefix and a bare `AW########` format. Stripping a leading `NAS` from the first format yields a value that matches `cust_info.cst_key` for 100% of rows (18,484/18,484) — confirmed reliable join key after normalization (see Section 4, DQ-19). |
| `BDATE` | Date (`YYYY-MM-DD`) | No blanks, but data-quality nulls present in effect | 6,152 distinct | PII (DOB) | Customer birthdate | `1971-10-06` | Range spans 1916-02-10 to an implausible sentinel value of **9999-11-20**. 16 rows have a birthdate later than the current date (2026-09-24), which is logically impossible and indicates bad/placeholder data — these need a documented exclusion or null-out rule before feeding an age-derived attribute. |
| `GEN` | Text, inconsistent casing/format | Yes — 1,476 blank plus several whitespace-only variants | 9 distinct raw values | PII | Gender (ERP source) | `Male`, `Female`, `M `, `F`, `  ` | Highly inconsistent: full words (`Male`/`Female`, the majority), single letters (`M`/`F`, a handful), and multiple distinct whitespace-only strings that are effectively blank but don't collapse under a naive equality check. All must be standardized to a single code set and reconciled against `cust_info.cst_gndr` — the two sources will disagree for some customers and a source-of-truth rule is required per RA-07. |

### Entity: `LOC_A101` (ERP — Customer Geography Supplement)

| Column Name | Data Type (observed) | Nullable? | Uniqueness | Sensitivity | Business Meaning | Sample Values | Profiling Notes & Quality Alerts |
|---|---|---|---|---|---|---|---|
| `CID` | Alphanumeric, `AW-########` | No | 18,484/18,484 distinct (100%) | PII | ERP customer identifier (FK candidate to CRM customer) | `AW-00011000` | Single consistent format (`AW-` + 8 digits) across all rows. Removing the dash yields a value that matches `cust_info.cst_key` for 100% of rows — confirmed reliable join key after normalization (see Section 4, DQ-19). |
| `CNTRY` | Text | Yes — 332 blank, plus several distinct whitespace-only variants (5 rows total) | 13 distinct raw values | PII (residency/location) | Customer country | `Australia`, `Germany`, `DE`, `USA` | Same country is represented multiple ways: United States as `United States` (3,391), `USA` (2,591), and `US` (1,500); Germany as `Germany` (1,214) and `DE` (566). 337 rows are effectively blank (332 empty + 5 whitespace-only variants, 2%). Needs a standardization/mapping table before use as `Revenue by Country` grouping key (RA-05). |

### Entity: `PX_CAT_G1V2` (ERP — Product Category Reference)

| Column Name | Data Type (observed) | Nullable? | Uniqueness | Sensitivity | Business Meaning | Sample Values | Profiling Notes & Quality Alerts |
|---|---|---|---|---|---|---|---|
| `ID` | Alphanumeric, `CAT_SUB` | No | 37/37 distinct (100%) | None | Category reference key | `AC_BR`, `AC_HE` | Clean unique key. Matches the underscore-joined first two dash-segments of `prd_info.prd_key` for 390/397 product rows (98.2%) — see DQ-11 for the 7-row gap. |
| `CAT` | Text | No | 4 distinct | None | Top-level product category | `Accessories`, `Bikes`, `Clothing`, `Components` | Clean, small controlled vocabulary — no anomalies observed. |
| `SUBCAT` | Text | No | 37 distinct (1:1 with `ID`) | None | Product subcategory | `Bike Racks`, `Helmets` | Clean, 1:1 with `ID` as expected of a reference table. |
| `MAINTENANCE` | Text (`Yes`/`No`) | No | 2 distinct | None | Whether the subcategory requires maintenance tracking | `Yes`, `No` | Clean boolean-style flag, fully populated. |

---

## 3. Data Quality Audit & Risk Register

| Risk ID | Source Field | DQ Issue / Anomaly | Impact Level | Concrete Example | Proposed Handling in Staging/Bronze |
|---|---|---|---|---|---|
| DQ-01 | `cust_info.cst_id` / `cst_key` | 4 rows are junk/test trailer records: blank `cst_id`, non-numeric `cst_key`, all other fields blank | Low (4 rows) | `cst_key='SF566'`, `cst_id=''` | Exclude from `DIM_CUSTOMER` load; route to an error/quarantine table for review. |
| DQ-02 | `cust_info.cst_id` | 9 distinct `cst_id` values repeat 2–3 times with different `cst_create_date`, consistent with record re-registration/updates rather than random duplication | Medium | `cst_id=29466` appears 3x with `cst_create_date` = 2026-01-25, 2026-01-26, 2026-01-27 | Deduplicate by keeping the row with `MAX(cst_create_date)` per `cst_id` before loading `DIM_CUSTOMER` (Type-1 default per RA-08). |
| DQ-03 | `cust_info.cst_gndr` | 24.7% of rows (4,578) have blank gender | Medium-High | blank string | Fall back to `CUST_AZ12.GEN` where CRM gender is blank, per a documented reconciliation rule (RA-07); default to "Unknown" where both sources are blank. |
| DQ-04 | `cust_info.cst_firstname`, `cst_lastname` | Leading/trailing whitespace present (17 firstname rows, 22 lastname rows) | Low | `' Jon'`, `'Yang '` | `TRIM()` during staging load. |
| DQ-05 | `prd_info.prd_key` | Not a unique key — 102 distinct keys appear on 2–3 rows each (179 rows total), representing historical product versions with different `prd_start_dt`/`prd_end_dt` | High | `prd_key='AC-HE-HL-U509-R'` appears on `prd_id` 212 (2011–2007) and 213 (2012–2008) | Requires an explicit SCD decision (RA-08 default is Type 1/current-row-only): select the row per `prd_key` with the latest `prd_start_dt` (or open-ended `prd_end_dt`) as "current" for `DIM_PRODUCT`; retain all rows in a staging/history table regardless. |
| DQ-06 | `prd_info.prd_end_dt` | Blank in 197/397 rows (49.6%) | Medium | blank | Interpret blank as "currently active" (`9999-12-31` or NULL sentinel, per warehouse convention) rather than missing data — confirm with business. |
| DQ-07 | `prd_info.prd_start_dt` / `prd_end_dt` | In 200/397 rows (50.4%), the row's `prd_end_dt` predates its own `prd_start_dt` | **High** | `prd_id=212`: `prd_start_dt='2011-07-01'`, `prd_end_dt='2007-12-28'` | Flag for source-system clarification before building SCD/history logic — pattern suggests `prd_end_dt` may actually belong to the prior version's record, not this one. Do not use raw `prd_end_dt` for "is-current" logic until resolved; use `MAX(prd_start_dt)` per `prd_key` instead as an interim rule. |
| DQ-08 | `prd_info.prd_cost` | 2 rows blank | Low | blank | Exclude from cost-based KPIs (e.g. Gross Margin) or impute with category/product-line average, pending business rule. |
| DQ-09 | `prd_info.prd_line` | 17 rows blank (4.3%); populated values carry a trailing space (`'R '`) | Low | `prd_line=''`, `prd_line='R '` | `TRIM()` all values; default blank to an "Unknown" product line bucket. |
| DQ-10 | `prd_info.prd_key` vs. `sales_details.sls_prd_key` | Key formats differ — `prd_info.prd_key` carries a 2-segment category prefix that `sls_prd_key` omits | High (join-critical) | `prd_info.prd_key='CO-RF-FR-R92B-58'` vs. `sales_details.sls_prd_key='FR-R92B-58'`-style suffix | Confirmed derivable 1:1 mapping: strip the first two dash-delimited segments from `prd_info.prd_key` to match `sls_prd_key` (100% match rate, 60,398/60,398 rows). Implement as a staging transformation, combined with DQ-05's current-version selection. |
| DQ-11 | `prd_info.prd_key` vs. `PX_CAT_G1V2.ID` | 7/397 product rows (all `CO-PE-*`, Pedals) have a derived category prefix (`CO_PE`) with no matching row in `PX_CAT_G1V2` | Medium | `prd_key='CO-PE-PD-M282'` → derived `ID='CO_PE'`, absent from `PX_CAT_G1V2` | These 7 rows will have no `CAT`/`SUBCAT` in `DIM_PRODUCT` under an inner join — use a left join and flag/bucket as "Uncategorized: Pedals," and raise with the ERP data owner as a likely missing reference row. |
| DQ-12 | `sales_details.sls_order_dt` | 17 rows have the literal placeholder value `'0'` instead of a real date; 1 row is a malformed 5-digit value, 1 row a malformed 4-digit value | Medium | `sls_order_dt='0'` | Treat `'0'` and any value not matching `YYYYMMDD` (8 digits) as NULL for `DIM_DATE` join purposes; log to a DQ exception table rather than silently defaulting to a real date. |
| DQ-13 | `sales_details.sls_sales` | 8 blank, 3 negative, 2 exactly zero | Medium | `sls_sales=-54` on `sls_ord_num='SO61570'` | Per RA-08 assumption, treat as DQ exceptions (not valid zero/negative transactions) pending business sign-off; exclude from revenue KPIs or route to an exceptions table. |
| DQ-14 | `sales_details.sls_price` | 7 blank, 5 negative | Medium | `sls_price=-1701` on `sls_ord_num='SO58623'` | Same handling as DQ-13 — flag/exclude pending business rule; note the negative-price rows are a different set of 5 order lines than the negative-`sls_sales` rows. |
| DQ-15 | `sales_details` (`sls_sales`, `sls_quantity`, `sls_price`) | In 20/60,398 rows (0.03%), `sls_sales ≠ sls_quantity × sls_price` | Low | — | Recompute `sls_sales` as `sls_quantity × sls_price` at Silver layer where a discrepancy is detected, per RA-05's "should reconcile" note, rather than trusting the raw value uncritically. |
| DQ-16 | `CUST_AZ12.GEN` | 9 distinct raw values including full words, single letters, and multiple distinct whitespace-only strings; 1,476+ effectively blank | Medium | `'Male'`, `'M'`, `'  '`, `' '` | `TRIM()` then map to a single controlled code set (`M`/`F`/`Unknown`) before reconciling with `cust_info.cst_gndr`. |
| DQ-17 | `CUST_AZ12.BDATE` | Sentinel/invalid date `9999-11-20` present; 16 rows have a birthdate after the current date | Medium | `BDATE='9999-11-20'` | Null out or quarantine any `BDATE` in the future or implausibly far in the past (e.g. before 1900) before deriving age. |
| DQ-18 | `LOC_A101.CNTRY` | Same country represented multiple ways (`US`/`USA`/`United States`; `DE`/`Germany`); 337 rows effectively blank | High (KPI-critical — RA-05 "Revenue by Country") | `'US'`, `'USA'`, `'United States'` all present | Apply a country-standardization lookup (ISO or full-name convention, to be confirmed) at staging; bucket blanks as "Unknown." |
| DQ-19 | `CUST_AZ12.CID`, `LOC_A101.CID` vs. `cust_info.cst_key` | Three different customer-key formats across CRM and ERP: `AW########` (CRM), `NASAW########` / `AW########` (ERP CUST_AZ12, mixed), `AW-########` (ERP LOC_A101) | High (join-critical) | `cst_key='AW00011000'`; `CUST_AZ12.CID='NASAW00011000'`; `LOC_A101.CID='AW-00011000'` | Confirmed 100% match rate after normalization: strip leading `NAS` from `CUST_AZ12.CID`, strip the dash from `LOC_A101.CID`. Implement as a staging-layer key-normalization step feeding `DIM_CUSTOMER`. |

---

## 4. Entity-Relationship & Key Mapping

**Primary / Foreign Key Links** (all cardinalities and match rates below are computed from the full data, not inferred):

- `sales_details.sls_cust_id` → `cust_info.cst_id` — Cardinality: N:1 · Enforcement: App-level only (flat files, no DB constraint visible) · Match rate: 60,398/60,398 (100%), 0 orphans.
- `sales_details.sls_prd_key` (derived, no transform needed on this side) → `prd_info.prd_key` **with first two dash-segments stripped** — Cardinality: N:N in raw form (each stripped `prd_info.prd_key` maps to up to 3 historical rows; see DQ-05) — effectively N:1 once `prd_info` is resolved to a single "current" row per key · Enforcement: App-level only · Match rate: 60,398/60,398 (100%) after the transform.
- `CUST_AZ12.CID` **with leading `NAS` stripped** → `cust_info.cst_key` — Cardinality: 1:1 · Enforcement: App-level only · Match rate: 18,484/18,484 (100%).
- `LOC_A101.CID` **with dash removed** → `cust_info.cst_key` — Cardinality: 1:1 · Enforcement: App-level only · Match rate: 18,484/18,484 (100%).
- `prd_info.prd_key` **first two dash-segments, joined with underscore** → `PX_CAT_G1V2.ID` — Cardinality: N:1 · Enforcement: App-level only · Match rate: 390/397 (98.2%); 7 orphan rows, all `CO_PE` (Pedals) — see DQ-11.

**Referential Integrity Risks:**

- No database-enforced constraints are observable in any of the six extracts — all are flat files, so referential integrity is entirely dependent on staging-layer transformation logic (key normalization above) rather than source-system guarantees.
- `prd_info.prd_key` is not unique at the source (DQ-05), so any downstream join from `sales_details` to `prd_info` on the derived key is ambiguous (1:N) unless a "current version" rule is applied first — this is the single highest-risk join in the model, since it affects every row of the eventual `FACT_SALES`.
- The 7 orphaned `CO_PE` (Pedals) products (DQ-11) will silently lose category/subcategory attribution under an inner join to `PX_CAT_G1V2` — must use a left join plus a fallback bucket, or category-level KPIs (RA-04 Q2, Q6) will undercount Pedals.
- The 4 junk rows in `cust_info` (DQ-01) have no valid key to join on at all and must be filtered before any FK resolution is attempted.

---

## 5. Initial Source-to-Target Mapping (Draft)

Target layer is Bronze/Staging per the acceptance criteria (no DDL/transformation pipeline is specified here). Proposed target entity names align with the dimensional model in `docs/requirements.md` (RA-06, RA-07) where the staging table feeds directly into a named dimension or fact.

| Source Entity | Source Column | Source Data Type | Target Layer | Proposed Target Entity | Proposed Target Column | Target Data Type | Transformation Notes |
|---|---|---|---|---|---|---|---|
| `cust_info` | `cst_id` | text (numeric) | Bronze/Staging | `stg_crm_cust_info` → feeds `DIM_CUSTOMER` | `customer_bk` | `INT` | Exclude blank/junk rows (DQ-01); dedupe on `MAX(cst_create_date)` (DQ-02). |
| `cust_info` | `cst_key` | text | Bronze/Staging | `stg_crm_cust_info` → `DIM_CUSTOMER` | `customer_key` | `NVARCHAR(20)` | Normalize to uppercase; this is the join key to both ERP supplements. |
| `cust_info` | `cst_firstname` | text | Bronze/Staging | `DIM_CUSTOMER` | `first_name` | `NVARCHAR(100)` | `TRIM()` (DQ-04). |
| `cust_info` | `cst_lastname` | text | Bronze/Staging | `DIM_CUSTOMER` | `last_name` | `NVARCHAR(100)` | `TRIM()` (DQ-04). |
| `cust_info` | `cst_marital_status` | text (code) | Bronze/Staging | `DIM_CUSTOMER` | `marital_status` | `NVARCHAR(20)` | Decode `M`→Married, `S`→Single, blank→Unknown. |
| `cust_info` | `cst_gndr` | text (code) | Bronze/Staging | `DIM_CUSTOMER` | `gender` | `NVARCHAR(10)` | Reconcile with `CUST_AZ12.GEN` per RA-07 rule (DQ-03, DQ-16). |
| `cust_info` | `cst_create_date` | date | Bronze/Staging | `DIM_CUSTOMER` | `customer_create_date` | `DATE` | Direct load; used for dedup logic (DQ-02). |
| `prd_info` | `prd_id` | text (numeric) | Bronze/Staging | `stg_crm_prd_info` → feeds `DIM_PRODUCT` | `product_id` | `INT` | Direct load — reliable surrogate. |
| `prd_info` | `prd_key` | text | Bronze/Staging | `stg_crm_prd_info` → `DIM_PRODUCT` | `product_key` | `NVARCHAR(50)` | Derive `category_id` by stripping first 2 segments; resolve to current-version row (DQ-05, DQ-07). |
| `prd_info` | `prd_nm` | text | Bronze/Staging | `DIM_PRODUCT` | `product_name` | `NVARCHAR(200)` | Direct load. |
| `prd_info` | `prd_cost` | text (numeric) | Bronze/Staging | `DIM_PRODUCT` | `cost` | `DECIMAL(10,2)` | Cast to numeric; handle 2 blanks (DQ-08). |
| `prd_info` | `prd_line` | text (code) | Bronze/Staging | `DIM_PRODUCT` | `product_line` | `NVARCHAR(20)` | `TRIM()`, decode code to full text, default blank to Unknown (DQ-09). |
| `prd_info` | `prd_start_dt` / `prd_end_dt` | date | Bronze/Staging | `DIM_PRODUCT` | `effective_start_date` / `effective_end_date` | `DATE` | Interim rule per DQ-07: derive `effective_end_date` from the next version's `prd_start_dt` rather than trusting raw `prd_end_dt`, pending source clarification. |
| `sales_details` | `sls_ord_num` | text | Bronze/Staging | `stg_crm_sales_details` → feeds `FACT_SALES` | `order_number` | `NVARCHAR(20)` | Degenerate dimension — direct load. |
| `sales_details` | `sls_prd_key` | text | Bronze/Staging | `FACT_SALES` | `product_key` (FK) | `NVARCHAR(50)` | Joins to resolved `DIM_PRODUCT.product_key` (DQ-10). |
| `sales_details` | `sls_cust_id` | text (numeric) | Bronze/Staging | `FACT_SALES` | `customer_key` (FK) | `INT` | Direct join to `DIM_CUSTOMER.customer_bk`. |
| `sales_details` | `sls_order_dt` / `sls_ship_dt` / `sls_due_dt` | text (`YYYYMMDD`) | Bronze/Staging | `FACT_SALES` | `order_date_key` / `ship_date_key` / `due_date_key` (FK to `DIM_DATE`) | `DATE` | Parse `YYYYMMDD`; null out `'0'` and malformed values (DQ-12) rather than joining to a real `DIM_DATE` row. |
| `sales_details` | `sls_sales` | text (numeric) | Bronze/Staging | `FACT_SALES` | `sales_amount` | `DECIMAL(10,2)` | Flag/exclude blank, negative, zero per business rule (DQ-13); recompute where reconciliation fails (DQ-15). |
| `sales_details` | `sls_quantity` | text (numeric) | Bronze/Staging | `FACT_SALES` | `quantity` | `INT` | Direct cast — clean field. |
| `sales_details` | `sls_price` | text (numeric) | Bronze/Staging | `FACT_SALES` | `unit_price` | `DECIMAL(10,2)` | Flag/exclude blank, negative per business rule (DQ-14). |
| `CUST_AZ12` | `CID` | text | Bronze/Staging | `stg_erp_cust_az12` → feeds `DIM_CUSTOMER` | `customer_key` (join key) | `NVARCHAR(20)` | Strip leading `NAS` prefix where present (DQ-19). |
| `CUST_AZ12` | `BDATE` | date | Bronze/Staging | `DIM_CUSTOMER` | `birth_date` | `DATE` | Null out future-dated and sentinel (`9999-*`) values (DQ-17). |
| `CUST_AZ12` | `GEN` | text | Bronze/Staging | `DIM_CUSTOMER` | `gender` (ERP source, pre-reconciliation) | `NVARCHAR(10)` | `TRIM()` and standardize to `M`/`F`/`Unknown` (DQ-16), then reconcile with CRM value. |
| `LOC_A101` | `CID` | text | Bronze/Staging | `stg_erp_loc_a101` → feeds `DIM_CUSTOMER` | `customer_key` (join key) | `NVARCHAR(20)` | Strip dash (DQ-19). |
| `LOC_A101` | `CNTRY` | text | Bronze/Staging | `DIM_CUSTOMER` | `country` | `NVARCHAR(50)` | Apply country-standardization lookup (DQ-18); blank/whitespace → Unknown. |
| `PX_CAT_G1V2` | `ID` | text | Bronze/Staging | `stg_erp_px_cat_g1v2` → feeds `DIM_PRODUCT` | `category_id` (join key) | `NVARCHAR(10)` | Direct load — clean reference table. |
| `PX_CAT_G1V2` | `CAT` | text | Bronze/Staging | `DIM_PRODUCT` | `category` | `NVARCHAR(50)` | Direct load; left-join with fallback for the 7 unmatched Pedals rows (DQ-11). |
| `PX_CAT_G1V2` | `SUBCAT` | text | Bronze/Staging | `DIM_PRODUCT` | `subcategory` | `NVARCHAR(50)` | Direct load; same fallback as `category`. |
| `PX_CAT_G1V2` | `MAINTENANCE` | text (`Yes`/`No`) | Bronze/Staging | `DIM_PRODUCT` | `maintenance_flag` | `BIT`/`BOOLEAN` | Decode `Yes`/`No` to boolean. |

---

## 6. Open Items — Insufficient Input for Full Profiling

| ID | Entity / Column | What's Missing | Why It Matters |
|---|---|---|---|
| OI-01 | `prd_info.prd_line` | No decode table for the codes `R`/`M`/`S`/`T` was provided | `DIM_PRODUCT.product_line` cannot be populated with a confirmed business label without this — RA-04 Q6 ("which product lines are growing/declining") depends on it. |
| OI-02 | `prd_info.prd_start_dt` / `prd_end_dt` | No source-system documentation explaining why 50.4% of rows have `prd_end_dt` earlier than `prd_start_dt` (DQ-07) | This directly affects whether `DIM_PRODUCT` can be trusted as SCD Type-1 "current row" without misrepresenting product history; a data-owner conversation is needed before finalizing the transform. |
| OI-03 | `LOC_A101.CNTRY` | No standardization/mapping table (ISO codes vs. full names) was provided | RA-05's "Revenue by Country" KPI and RA-04 Q8 depend directly on a consistent country dimension; the mapping (`US`/`USA`/`United States` → one value, `DE`/`Germany` → one value) needs to be authored and confirmed with the business, not assumed. |
| OI-04 | `cust_info.cst_gndr` vs. `CUST_AZ12.GEN` | No documented source-of-truth or tie-breaking rule when the two disagree (both are individually incomplete) | RA-07 flags this as needing a rule; without it, `DIM_CUSTOMER.gender` will be inconsistent across loads. |
| OI-05 | `sales_details` (`sls_sales`, `sls_quantity`, `sls_price` nulls/negatives) | No confirmed business rule on whether to exclude, impute, or flag these rows | RA-02/RA-08 note this is pending business confirmation; the interim treatment proposed in Section 3 (DQ-13/DQ-14) should not be treated as final. |
| OI-06 | All six sources | No data-owner-confirmed business definitions were provided for any column — meanings in Section 2 are inferred from column names/context and `docs/requirements.md` | Column-level business meaning should be validated with the CRM/ERP system owners before sign-off, per RA-09 next steps. |
