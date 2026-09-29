# Enterprise CRM-ERP Data Warehouse (Bronze-Silver-Gold) Pipeline

A SQL Server data warehouse project that ingests CRM and ERP source extracts
and processes them through a medallion architecture (Bronze -> Silver -> Gold)
into analytics-ready tables.

## Status

| Layer  | DDL | Load Logic | Status        |
|--------|-----|------------|---------------|
| Bronze | ✅  | ✅         | Complete      |
| Silver | ✅  | ⏳         | In progress   |
| Gold   | ⏳  | ⏳         | Not started   |

## Architecture

- **Bronze** — raw, unmodified data loaded as-is from source CSV extracts
  via `BULK INSERT`. No business rules applied; column types are widened as
  needed to avoid truncation on ingestion.
- **Silver** — cleansed, standardized, and typed data (e.g. date columns cast
  from raw `INT`/text to `DATE`, business keys and codes normalized). Each
  Silver table carries a `dwh_create_date` audit column.
- **Gold** — business-ready, modeled data (facts/dimensions) for reporting
  and analytics. Not yet built.

![Architecture Diagram](docs/DataWarehouseArchitecture.drawio.png)

## Project Structure

```
crm-erp-data-warehouse/
├── scripts/
│   ├── bronze/
│   │   ├── 01_ddl.sql              # Creates bronze schema tables
│   │   └── 02_load_procedure.sql   # bronze.load_bronze — BULK INSERT from CSV
│   ├── silver/
│   │   └── 01_ddl.sql              # Creates silver schema tables
│   └── gold/                       # Reserved for Gold layer scripts
├── datasets/                       # Raw CRM/ERP CSV extracts (not tracked in git)
├── docs/                           # Diagrams and planning notes (see below)
├── tests/                          # Validation / data quality test scripts
├── .gitignore
└── README.md
```

## Documentation (`docs/`)

### Architecture

![Architecture Diagram](docs/DataWarehouseArchitecture.drawio.png)

### Data Flow

![Data Flow Diagram](docs/data_flow.drawio.png)

### Data Integration

![Data Integration Diagram](docs/data_integration.drawio.png)

### Data Model

*Not yet added — planned once the Gold-layer dimensional model is designed.*

### Notes

| File | Description |
|------|--------------|
| `requirements` | Project requirements notes. |
| `source_data_analysis` | Analysis notes on the source CRM/ERP data (structure, quality issues, assumptions). |

> Editable `.drawio` source files for the diagrams above (if kept in the
> repo separately from their `.png` exports) can be opened and edited for
> free at [app.diagrams.net](https://app.diagrams.net) — no account
> required.

## Testing (`tests/`)

Holds validation and data quality scripts for the pipeline — e.g. row-count
reconciliation between Bronze and Silver, null/duplicate checks, and
referential integrity checks across CRM/ERP sources. *(Update this section
with specifics once the test scripts are finalized.)*

## Prerequisites

- Microsoft SQL Server 2016+
- Permissions: `CREATE TABLE`/`DROP TABLE`/`ALTER` on the target database,
  plus `ADMINISTER BULK OPERATIONS` (or `bulkadmin` role) for the load
  procedure, and file-system read access for the SQL Server service account
  on the machine hosting the source CSVs.

## Setup & Run

1. **Place source files** — copy your CRM/ERP CSV extracts into
   `datasets/` locally (git-ignored; see `.gitignore`).
2. **Create schemas** (if not already present):
   ```sql
   CREATE SCHEMA bronze;
   CREATE SCHEMA silver;
   ```
3. **Bronze layer**
   ```sql
   :r scripts/bronze/01_ddl.sql
   :r scripts/bronze/02_load_procedure.sql
   EXEC bronze.load_bronze;
   ```
4. **Silver layer**
   ```sql
   :r scripts/silver/01_ddl.sql
   -- Silver load procedure (Bronze -> Silver transformation) is in progress
   ```

> Note: `BULK INSERT` file paths in `02_load_procedure.sql` are currently
> hard-coded local paths (see script comments). Update these to match your
> environment before running.

## Roadmap

- [ ] Silver layer transformation/load procedure
- [ ] Gold layer dimensional model (facts/dimensions)
- [ ] Data model diagram (`docs/`)
- [ ] Data quality / validation scripts in `tests/`
- [ ] Documentation of source-to-target mappings
