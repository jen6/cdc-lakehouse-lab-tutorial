# AWS CDC Lakehouse Lab

Reproducible infrastructure and Kubernetes service definitions for a commerce-domain
CDC data platform:

![AWS CDC lakehouse architecture](docs/assets/cdc-lakehouse-architecture.png)

Diagram source/export: [SVG](docs/assets/cdc-lakehouse-architecture.svg), [draw.io companion](docs/diagrams/cdc-lakehouse-architecture.drawio).

The first milestone is infrastructure readiness, not running every workload by
default. OpenTofu provisions AWS infrastructure, and Argo CD manages the EKS
services that can be added or removed independently.

## Pipeline Roles

| Layer | Component | Role |
| --- | --- | --- |
| Source | RDS MySQL | Operational schemas that behave like commerce services. |
| CDC runtime | Kafka Connect + Debezium | Reads MySQL binlog, manages connector tasks and offsets, and publishes change events. |
| Transport | MSK | Durable Kafka topics for CDC events and Kafka Connect internal state. |
| Stream processing | Flink | Converts Debezium events into Bronze/Silver/Gold Iceberg tables. |
| Lakehouse storage | S3 + Iceberg | Stores table data files and Iceberg metadata. |
| Catalog | Glue Data Catalog | Provides the Iceberg catalog used by Flink and Trino. |
| Consumption | Trino / Kubeflow | SQL analytics and ML/experiment workflows over lakehouse data. |

## Repository Layout

```text
infra/opentofu/     AWS infrastructure: VPC, EKS, RDS, MSK, S3, Glue, IAM
k8s/argocd/         Argo CD root app and child applications
k8s/apps/           Kubernetes manifests for data-platform services
k8s/rendered/       Generated GitOps overlay; created per lab and not committed in this seed repo
apps/generator/     Commerce schema bootstrap and workload generator
flink/sql/          CDC-to-Iceberg SQL templates
docs/               Architecture, deployment, teardown, and operations notes
```

## First Deploy Shape

- RDS MySQL single instance with `commerce`, `payment`, and `logistics` schema bootstrap support
- MSK Kafka cluster, default provisioned `kafka.t3.small` x 2 with an `msk_mode = "serverless"` option for lower-ops lab runs
- EKS managed node group for platform/data/ML services
- S3 bucket for Iceberg warehouse and Kubeflow artifacts
- Glue databases for `bronze`, `silver`, and `gold`
- IAM role for EKS service accounts that need S3/Glue/Secrets Manager access

## Quick Start

This tutorial repository intentionally does not commit `k8s/rendered/`.
Generate it after OpenTofu creates environment-specific outputs such as ECR
image URLs, IAM role ARNs, S3 bucket names, and Kafka bootstrap brokers.

```bash
LAB_ID=tutorial-$USER scripts/labctl.sh init
scripts/labctl.sh plan
scripts/labctl.sh deploy
```

The deploy command applies OpenTofu, builds and pushes the two runtime images,
renders `k8s/rendered/`, commits and pushes that rendered overlay, installs
Argo CD, configures private-repo access with a lab deploy key, and applies the
rendered root application.

```bash
scripts/labctl.sh status
```

See [docs/deploy-runbook.md](docs/deploy-runbook.md) for the full flow.
If using Codex, invoke the bundled `cdc-lakehouse-lab` skill for setup,
verification, and teardown.

## What To Check

Most services are private inside the EKS cluster. Use port-forwarding from your
local machine when you want to inspect them.

| Component | What to look at | Command | URL |
| --- | --- | --- | --- |
| Argo CD | Application sync and health status | `kubectl -n argocd port-forward svc/argocd-server 8080:443` | `https://localhost:8080` |
| Flink | Running/failed jobs, checkpoints, TaskManagers, job exceptions | `kubectl -n data port-forward svc/orders-cdc-rest 8082:8081` | `http://localhost:8082` |
| Trino | Cluster status and query history | `kubectl -n data port-forward svc/trino 8084:8080` | `http://localhost:8084/ui/` |
| Kafka Connect | Connector status and task failures | `kubectl -n data port-forward svc/kafka-connect 8083:8083` | `http://localhost:8083/connectors` |

For quick status checks:

```bash
kubectl -n argocd get applications
kubectl -n data get pods,svc
kubectl -n data get flinkdeployment orders-cdc
```

Useful logs while debugging the CDC path:

```bash
kubectl -n data logs deploy/kafka-connect
kubectl -n data logs deploy/source-generator
kubectl -n data logs deploy/trino-coordinator
kubectl -n data logs deploy/flink-kubernetes-operator
kubectl -n data logs -l app=orders-cdc,component=jobmanager
kubectl -n data logs -l app=orders-cdc,component=taskmanager
```

Trino's built-in Web UI is mainly for monitoring and query history. Run ad hoc
SQL through the Trino CLI in the coordinator pod:

```bash
kubectl -n data exec -it deploy/trino-coordinator -- trino --server http://localhost:8080
```

Starter queries:

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;
SHOW TABLES FROM iceberg.lab_bronze;
SELECT * FROM iceberg.lab_bronze.orders_cdc_events LIMIT 10;
```

## MSK Mode

Use `msk_mode = "provisioned"` when you want broker sizing, replication, and
monitoring practice. Use `msk_mode = "serverless"` when the goal is cheaper
stop-start lab work focused on CDC and lakehouse behavior. Switching an existing
environment from provisioned to serverless replaces the Kafka cluster, so do it
before Kafka contains state you care about.
