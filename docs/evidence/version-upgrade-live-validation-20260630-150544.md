# Version Upgrade Live Validation Evidence

This document records the public-safe summary of a live validation run performed
against the private source lab before the same upgrade was carried into this
tutorial repository.

## Scope

- Goal: upgrade the CDC lakehouse lab runtime, deploy it to AWS/EKS, prove that
  CDC reaches Iceberg tables, then tear the lab resources down.
- Runtime shape: RDS MySQL -> Kafka Connect/Debezium -> MSK Kafka -> Flink ->
  Iceberg on S3/Glue -> Trino.
- Public redaction: account IDs, ARNs, endpoints, bucket names, deploy-key IDs,
  and private repository details are intentionally replaced with generic
  descriptions.

## Validated Versions

| Area | Validated version |
| --- | --- |
| Flink runtime | `2.1.3` |
| Flink Kubernetes Operator | `1.15.0` |
| Iceberg runtime | `1.11.0` |
| Flink Kafka connector | `5.0.0-2.1` |
| Debezium Connect | `3.5.0.Final` |
| MSK Kafka | `3.9.x` |
| EKS | `1.36` |
| RDS MySQL | `8.4.9` |
| Trino chart | `1.42.2` |
| cert-manager | `v1.20.3` |
| external-secrets | `2.7.0` |
| kube-prometheus-stack | `87.3.0` |
| AWS provider | `6.52.0` |
| EKS module | `21.24.0` |
| VPC module | `6.6.1` |

## Build Evidence

- OpenTofu configuration validation passed in the private lab environment before
  deployment.
- Flink SQL runner Maven build completed successfully with Java 21.
- Flink runtime image inspection confirmed:
  - `bin/flink --version` reported `2.1.3`.
  - SQL runner JAR existed at `/opt/flink/usrlib/sql-runner.jar`.
  - Kafka, Iceberg runtime, Iceberg AWS bundle, and S3 filesystem libraries were
    present in the image.
- Source generator image inspection confirmed upgraded Python dependencies.
- Static search found no core-path references to the old Flink `1.19.1`,
  Iceberg `1.9.2`, or Kafka connector `3.3.0-1.19` versions.

## Provision Evidence

- OpenTofu converged the AWS infrastructure after recovery of two expected lab
  issues:
  - VPC CNI needed to be created before compute so EKS nodes could become Ready.
  - A previously scheduled Secrets Manager secret had to be restored/imported
    before the new run could converge.
- EKS cluster reached `ACTIVE`.
- EKS managed node group reached `ACTIVE`; three nodes became Ready.
- MSK provisioned cluster reached `ACTIVE`.
- RDS MySQL source instance reached `available`.
- S3 lakehouse bucket, Glue databases, and ECR repositories were created.
- Source generator and Flink runtime images were pushed to ECR.

## GitOps Evidence

- Argo CD was installed and the root app was applied.
- Because the validation source repository was private, Argo access used a
  temporary read-only GitHub deploy key and an Argo repository secret.
- External Secrets CRDs initially exceeded the client-side apply annotation
  limit; enabling Argo server-side apply for that application fixed sync.
- Final Argo application state reached `Synced/Healthy` for:
  - platform apps: cert-manager, external-secrets, kube-prometheus-stack,
    CloudWatch exporter, and dashboards.
  - data apps: Flink operator, Flink orders CDC job, Kafka Connect, source
    generator, and Trino.
  - ML apps: Kubeflow Pipelines CRDs and Kubeflow Pipelines.

## Pipeline Evidence

- RDS source tables contained generated commerce data:
  - `commerce.orders`
  - `commerce.order_items`
  - `commerce.inventory`
  - `payment.payments`
  - `logistics.shipments`
- Kafka Connect connector `rds-commerce-source` reached `RUNNING`.
- Debezium completed the initial snapshot and continued streaming from MySQL
  binlog.
- Kafka topics were created for the included tables, including
  `rds.commerce.orders`.
- FlinkDeployment `orders-cdc` reached:
  - Flink version: `2.1.3`
  - Job state: `RUNNING`
  - Lifecycle state: `STABLE`
  - JobManager deployment status: `READY`
- Flink logs showed Kafka partition discovery and Iceberg Bronze/Silver/Gold
  sink operators switching to `RUNNING`.
- S3 checkpoint objects were written for the Flink job.
- Glue Iceberg tables were created:
  - `lab_bronze.orders_cdc_events`
  - `lab_silver.orders_current`
  - `lab_gold.order_revenue_by_status`
- Trino successfully queried the Iceberg catalog:
  - Bronze table returned non-zero CDC event count.
  - Silver table returned non-zero current-order count.
  - Gold table returned revenue by order status for statuses such as `PAID`,
    `SHIPPED`, `DELIVERED`, `CANCELLED`, and `PAYMENT_FAILED`.

## Teardown Evidence

- Argo root and child applications were deleted before cloud destroy.
- Workload namespaces were removed before destroying AWS resources.
- Stale Flink webhooks/finalizers from the already-pruned operator were cleared.
- ECR repositories were emptied before destroy.
- Versioned S3 objects and delete markers were removed before bucket destroy.
- Temporary GitHub deploy key used for the validation run was removed.
- The first destroy attempt exposed legacy `prevent_destroy` lifecycle blocks on
  the old lakehouse IRSA policy/role. Those blocks were removed so the
  disposable lab can be fully destroyed.
- Final `tofu destroy -auto-approve` completed with all OpenTofu-managed
  resources destroyed.
- Final `tofu state list` returned no resources.
- Service-specific checks confirmed that EKS, RDS, MSK, S3, ECR, and Glue lab
  resources were gone or returned not-found/empty/deleted states.
- KMS customer-managed keys followed the AWS terminal behavior for this resource
  type: disabled and `PendingDeletion`, not physically deleted immediately.

## Public Tutorial Notes

- This repository intentionally does not commit generated `k8s/rendered/`
  manifests.
- Re-run `scripts/render-k8s-config.sh` after a tutorial deployment to produce
  lab-specific rendered manifests from OpenTofu outputs.
- For a public fork, keep executable defaults generic and supply real repository
  URLs, bucket names, and role ARNs through OpenTofu variables or render
  environment variables.
