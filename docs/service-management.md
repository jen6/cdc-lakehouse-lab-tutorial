# EKS Service Management

## Ownership Boundary

| Layer | Tool |
| --- | --- |
| VPC, EKS, RDS, MSK, S3, Glue, IAM | OpenTofu |
| Kubernetes service add/update/delete | Argo CD |
| Service packaging | Helm or Kustomize |
| Secrets | AWS Secrets Manager + External Secrets |

Argo CD applications are grouped by AppProject:

| AppProject | Scope |
| --- | --- |
| `platform` | Operators, observability, and shared platform services |
| `data` | CDC runtimes, Flink, Trino, and lakehouse services |
| `ml` | Kubeflow Pipelines and ML workflow services |

## Baseline Services

| Namespace | Service | Purpose |
| --- | --- | --- |
| `platform` | external-secrets | Sync AWS Secrets Manager values to Kubernetes Secrets |
| `cert-manager` | cert-manager | Admission webhook certificates for operators such as Flink |
| `platform` | kube-prometheus-stack | Metrics, dashboards, alerts |
| `data` | kafka-connect | Debezium connector runtime |
| `data` | flink-kubernetes-operator | Flink job lifecycle |
| `data` | trino | Iceberg/Glue query engine |
| `ml` | kubeflow-pipelines | ML/data experiment orchestration |

## Add Service

1. Add manifests or Helm values under `k8s/apps/<domain>/<service>/`.
2. Add an Argo CD `Application` under the matching domain folder in
   `k8s/argocd/apps/`.
3. Set `spec.project` to the matching AppProject and add the service repo or
   namespace to `k8s/argocd/apps/projects/00-appprojects.yaml` if it is new.
4. Run `scripts/labctl.sh render` after infrastructure outputs exist.
5. Run `scripts/labctl.sh commit-rendered` and sync the root app.

## Remove Service

1. Delete the Argo CD `Application` from Git.
2. Sync the root app with prune.
3. Confirm namespace resources were removed.

Do not store durable business data in pods or PVCs unless the persistence path is
documented and restorable. Prefer S3, RDS snapshots, and Glue.

## Kubeflow Pipelines

The first repository state keeps Kubeflow as a managed inventory placeholder
because the full install is heavy. Once the CDC-to-Iceberg path is verified,
replace `k8s/apps/ml/kubeflow-pipelines` with Kubeflow Pipelines standalone
Kustomize manifests:

```bash
PIPELINE_VERSION=2.16.1
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$PIPELINE_VERSION"
```

For GitOps, split that into two Argo CD apps: cluster-scoped resources first,
then the environment manifests.
