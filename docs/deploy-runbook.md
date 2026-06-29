# Deploy Runbook

## 1. Provision AWS

```bash
LAB_ID=tutorial-$USER scripts/labctl.sh init
scripts/labctl.sh plan
scripts/labctl.sh deploy
```

`labctl.sh deploy` provisions AWS, builds and pushes runtime images, renders
`k8s/rendered`, commits and pushes that rendered overlay, installs Argo CD,
configures private-repo access, and applies the root app.

If you need to inspect outputs manually:

```bash
tofu -chdir=infra/opentofu output rds_secret_arn
tofu -chdir=infra/opentofu output msk_bootstrap_brokers
tofu -chdir=infra/opentofu output lakehouse_bucket
tofu -chdir=infra/opentofu output data_workloads_role_arn
tofu -chdir=infra/opentofu output platform_workloads_role_arn
tofu -chdir=infra/opentofu output ml_workloads_role_arn
```

This tutorial documents the provisioned MSK path. That keeps broker sizing,
replication, storage, and broker metrics visible while you practice CDC
operations. Serverless MSK is outside this tutorial path because it changes the
Kafka client authentication work for Kafka Connect and Flink.

## 2. Configure kubeconfig manually

```bash
aws eks update-kubeconfig \
  --region "$(tofu -chdir=infra/opentofu output -raw aws_region)" \
  --name "$(tofu -chdir=infra/opentofu output -raw eks_cluster_name)"
```

`scripts/labctl.sh deploy` already does this.

## 3. Install Argo CD manually

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
scripts/render-k8s-config.sh
git add -f k8s/rendered
git commit -m "Render lab GitOps manifests"
git push origin HEAD
kubectl apply -f k8s/rendered/argocd/root-app.yaml
```

Before applying the root app, set `repository_url` in `terraform.tfvars` to your
pushed repository URL. `scripts/render-k8s-config.sh` renders dynamic values from
OpenTofu outputs into `k8s/rendered/`. Commit or push that rendered overlay to
the repository branch that Argo CD will read; otherwise Argo CD will fetch the
unrendered placeholders.

For private GitHub repos, `scripts/labctl.sh deploy` creates a lab deploy key
and an Argo CD repository secret so Argo can read the rendered Git path.

## 4. Bootstrap Source Schemas

Run the generator bootstrap job locally or as a Kubernetes job after exporting
the RDS secret values:

```bash
export MYSQL_HOST="$(tofu -chdir=infra/opentofu output -raw rds_endpoint)"
export MYSQL_PORT=3306
export MYSQL_USER=admin
export MYSQL_PASSWORD="$(aws secretsmanager get-secret-value \
  --secret-id "$(tofu -chdir=infra/opentofu output -raw rds_secret_name)" \
  --query SecretString --output text | jq -r .password)"

python apps/generator/generator.py bootstrap
python apps/generator/generator.py run --rate-per-second 2
```

## 5. Verify CDC

Check Kafka Connect:

```bash
kubectl -n data port-forward svc/kafka-connect 8083:8083
curl localhost:8083/connectors
curl localhost:8083/connectors/rds-commerce-source/status
```

Check MSK topics with your preferred Kafka CLI container or EKS debug pod.

## 6. Verify Lakehouse

Use Trino:

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;
SHOW TABLES FROM iceberg.lab_silver;
SELECT count(*) FROM iceberg.lab_silver.orders_current;
```

## 7. Add or Remove Services

Add a service by adding manifests under `k8s/apps/<domain>/<service>/`, then
adding an Argo CD Application under the matching `k8s/argocd/apps/<domain>/`
folder:

- `platform` for operators, observability, and shared platform services.
- `data` for CDC, Flink, Trino, and lakehouse runtime services.
- `ml` for Kubeflow Pipelines and ML workflow services.

For environment-specific values, run `scripts/labctl.sh render` and
`scripts/labctl.sh commit-rendered`.

Remove a service by deleting its Application from Git and syncing with prune
enabled, or by deleting the Application directly in Argo CD for an emergency
rollback.
