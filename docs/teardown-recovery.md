# Teardown and Recovery

## Normal Cost-Saving Teardown

Durable state should live in S3, Glue, and RDS snapshots. EKS services and MSK
are reproducible.

Recommended shutdown order:

1. Stop workload generator.
2. Stop Debezium connector.
3. Stop Flink jobs with savepoints if you are preserving stream progress.
4. Snapshot RDS if source data should survive.
5. Export important Kafka topic samples if you need CDC replay evidence.
6. Run `scripts/labctl.sh teardown --yes`.

## What Survives

| Component | Preferred persistence |
| --- | --- |
| Source DB | RDS snapshot |
| Iceberg data | S3 bucket |
| Iceberg catalog | Glue Catalog |
| Kubernetes service state | Git manifests |
| Connector configs | Git manifests and Kafka Connect REST export |
| Flink progress | Savepoints in S3 |
| Kubeflow artifacts | S3 artifact store |

## MSK Deletion Tradeoff

Deleting MSK deletes Kafka topics and Kafka Connect internal offset/config/status
topics. After recreation, Debezium should run an initial snapshot again unless
you restored compatible offsets and source binlog positions.

For exact resume testing, keep MSK alive during the test window. For low-cost
practice, delete MSK and treat the next run as a fresh snapshot.

## RDS Stop vs Snapshot

- `stop` keeps the instance state but AWS can restart stopped RDS instances
  after the service limit window.
- `snapshot + delete` costs less for longer pauses and is the better fit for
  repeatable lab environments.
