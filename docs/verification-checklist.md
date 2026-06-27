# Verification Checklist

Use this checklist before claiming the environment is ready beyond the IaC
scaffold stage.

## Infrastructure

- `tofu init` succeeds.
- `tofu validate` succeeds.
- `tofu plan` produces RDS, MSK, EKS, S3, Glue, IAM, and Secrets Manager changes.
- `tofu output` returns:
  - `eks_cluster_name`
  - `rds_endpoint`
  - `rds_secret_name`
  - `msk_bootstrap_brokers`
  - `lakehouse_bucket`
  - `data_workloads_role_arn`
  - `platform_workloads_role_arn`
  - `ml_workloads_role_arn`

## Source

- `apps/generator/generator.py bootstrap` creates `commerce`, `payment`, and
  `logistics`.
- The generator creates orders, order items, inventory updates, payments, and
  shipment updates.
- RDS MySQL has row-based binlogs and non-zero backup retention.

## CDC

- Kafka Connect pod is ready.
- `rds-commerce-source` connector status is `RUNNING`.
- MSK contains Debezium topics for:
  - `rds.commerce.orders`
  - `rds.commerce.order_items`
  - `rds.commerce.inventory`
  - `rds.payment.payments`
  - `rds.logistics.shipments`
- Restarting Kafka Connect resumes from `_connect_offsets`.

## Lakehouse

- Flink checkpointing succeeds.
- S3 contains Iceberg metadata and data files under `warehouse/`.
- Glue contains `lab_bronze`, `lab_silver`, and `lab_gold`.
- Delete and update events are visible in Bronze and correctly materialized in
  Silver.

## Query

- Trino catalog `iceberg` loads.
- These queries work:

```sql
SELECT count(*) FROM iceberg.lab_bronze.orders_cdc;
SELECT count(*) FROM iceberg.lab_silver.orders_current;
SELECT * FROM iceberg.lab_gold.revenue_10m ORDER BY window_start DESC LIMIT 10;
SELECT * FROM iceberg.lab_gold.low_stock ORDER BY quantity ASC LIMIT 20;
SELECT * FROM iceberg.lab_gold.delayed_orders LIMIT 20;
```

## ML/Experiment

- Kubeflow Pipelines or the placeholder app is managed by Argo CD.
- Pipeline artifacts are configured to land in S3 before real ML jobs are
  enabled.

## Operations

- `scripts/render-k8s-config.sh` creates a rendered overlay from OpenTofu
  outputs.
- Argo CD root app syncs rendered AppProjects and child applications.
- Child applications are assigned to `platform`, `data`, or `ml` AppProjects
  instead of the broad `default` project.
- Prometheus/Grafana dashboards show pod health, Flink checkpoints, and Kafka
  Connect task status.
- Teardown and recovery are tested with RDS snapshot plus S3/Glue retention.
