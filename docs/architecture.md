# Architecture

## Target Flow

```text
RDS MySQL
  commerce/payment/logistics schemas
  TPC-C/Olist seed plus continuous generator
        |
        v
Kafka Connect + Debezium on EKS
        |
        v
MSK topics
        |
        v
Flink on EKS
        |
        v
S3 Iceberg warehouse + Glue Catalog
        |
        +--> Trino on EKS
        +--> Kubeflow Pipelines on EKS
```

## Layering

- **Source:** RDS MySQL is the operational source. The first lab keeps multiple
  schemas in one instance to control cost. The bootstrap generator creates
  `commerce`, `payment`, and `logistics`.
- **CDC:** Debezium runs in Kafka Connect. In the first phase this is on EKS so
  connector lifecycle, offsets, and restarts are visible.
- **Transport:** MSK is the Kafka control plane for CDC events and Connect
  internal topics.
- **Lakehouse:** S3 stores Iceberg data and metadata files. Glue is the catalog.
- **Processing:** Flink reads Debezium topics and writes Bronze/Silver/Gold
  Iceberg tables.
- **Query:** Trino reads Iceberg through Glue.
- **ML/Experiment:** Kubeflow Pipelines consumes S3/Trino outputs and stores
  artifacts in S3.
- **Management:** Argo CD owns EKS service add/update/delete. OpenTofu owns AWS
  resources.

## Data Contract

Bronze keeps raw Debezium envelopes. Silver is keyed current-state data. Gold is
query-shaped analytical data.

```text
bronze.orders_cdc     raw before/after/op/source/ts_ms
silver.orders_current primary-key upserted current order state
gold.revenue_10m      recent revenue aggregates
gold.low_stock        inventory risk view
gold.delayed_orders   orders paid but not shipped in SLA
```
