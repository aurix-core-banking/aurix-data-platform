# Architecture

## Overview

The data platform provides storage, analytics, and reporting infrastructure for the Aurix ecosystem.

## Components

- **OLAP**: ClickHouse for real-time analytics and dashboards
- **Data Lake**: S3-compatible object storage with Parquet/Delta Lake format
- **Orchestration**: Airflow + dbt for data transformation
- **BI**: Metabase / Superset for dashboards
- **Data Catalog**: DataHub for metadata management

## Data Flow

```
Kafka → Data Pipelines → Data Lake (raw) → dbt (transformed) → ClickHouse → BI
                               ↓
                        ML Feature Store
```
