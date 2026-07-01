# Version Upgrade Live Validation Runbook

This runbook is for the one-time goal of upgrading the lab stack, proving the
CDC-to-Iceberg pipeline in a real AWS/EKS environment, recording evidence, and
then tearing every lab resource down.

Do not mark the goal complete after code changes only. Completion requires live
pipeline evidence and teardown proof.

## Scope

Target stack:

| Area | Target |
| --- | --- |
| Flink runtime | `2.1.3` |
| Flink Kubernetes Operator | `1.15.0` |
| Iceberg runtime | `1.11.0` |
| Flink Kafka connector | `5.0.0-2.1` |
| Debezium Connect | `quay.io/debezium/connect:3.5.0.Final` |
| MSK Kafka | `3.9.x` |
| EKS | `1.36` |
| RDS MySQL | `8.4.9` |
| Trino chart | `1.42.2` |
| cert-manager | `v1.20.3` |
| external-secrets | `2.7.0` |
| kube-prometheus-stack | `87.3.0` |
| AWS provider | `~> 6.0` |
| EKS module | `~> 21.0` |
| VPC module | `~> 6.0` |

## Evidence File

Create a dated evidence file before live deployment:

```bash
mkdir -p docs/evidence
cat > "docs/evidence/version-upgrade-live-validation-$(date +%Y%m%d-%H%M%S).md" <<'EOF'
# Version Upgrade Live Validation Evidence

## Context

- Started at:
- AWS account:
- AWS region:
- Git commit:
- Rendered commit:

## Local Build Evidence

- `tofu init -upgrade`:
- `tofu validate`:
- Flink Maven build:
- Source generator Docker build:
- Flink runtime Docker build:
- Helm render checks:
- Kustomize checks:

## Provision Evidence

- `tofu plan` summary:
- `tofu apply` result:
- EKS cluster:
- MSK cluster:
- RDS instance:
- S3 lakehouse bucket:
- Glue databases:
- ECR repositories:

## Image Evidence

- Source generator image URI:
- Source generator digest:
- Flink runtime image URI:
- Flink runtime digest:

## GitOps Evidence

- Argo root app revision:
- Platform apps sync/health:
- Data apps sync/health:
- ML apps sync/health:

## Pipeline Evidence

- RDS schemas and row counts:
- Kafka Connect connector status:
- Kafka topics:
- FlinkDeployment status:
- Flink checkpoint evidence:
- S3 Iceberg metadata/data paths:
- Glue Iceberg tables:
- Trino validation queries:

## Teardown Evidence

- Argo/Kubernetes cleanup:
- `tofu destroy` result:
- Empty `tofu state list`:
- EKS not found:
- MSK not found:
- RDS not found:
- S3 bucket not found:
- ECR repositories not found:
- Glue databases not found:

## Known Gaps

- None, if complete.
EOF
```

Keep command outputs concise. Prefer exact resource names, timestamps, selected
rows, counts, and final statuses over full log dumps.

## Phase 1: Preflight

Verify AWS auth first. If this fails, do not render real manifests, push images,
or run `tofu plan`.

```bash
aws sso login
aws sts get-caller-identity --output json
aws kafka list-kafka-versions \
  --region ap-northeast-2 \
  --query 'KafkaVersions[].Version' \
  --output text
aws rds describe-db-engine-versions \
  --region ap-northeast-2 \
  --engine mysql \
  --query 'DBEngineVersions[?EngineVersion==`8.4.9`].EngineVersion' \
  --output text
```

Record the AWS account and region in the evidence file.

## Phase 2: Local Validation

Run these before provisioning:

```bash
tofu -chdir=infra/opentofu init -upgrade
tofu -chdir=infra/opentofu validate

JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.6/libexec/openjdk.jdk/Contents/Home \
  mvn -B -DskipTests package -f flink/runtime/pom.xml

docker build --platform linux/amd64 \
  -t cdc-lakehouse-source-generator:version-upgrade-check \
  apps/generator

docker build --platform linux/amd64 \
  -t cdc-lakehouse-flink-runtime:2.1.3-check \
  flink/runtime
```

Confirm runtime contents:

```bash
docker run --rm --entrypoint bash cdc-lakehouse-flink-runtime:2.1.3-check -lc '
  bin/flink --version
  ls -1 \
    /opt/flink/usrlib/sql-runner.jar \
    /opt/flink/lib/flink-sql-connector-kafka.jar \
    /opt/flink/lib/iceberg-flink-runtime.jar \
    /opt/flink/lib/iceberg-aws-bundle.jar \
    /opt/flink/plugins/s3-fs-hadoop/*
'
```

Render with placeholder values only for static checks. Do not commit placeholder
rendered manifests as deployable evidence.

```bash
ARGOCD_REPOSITORY_URL='git@github.com:jen6/cdc-lakehouse-lab-tutorial.git' \
AWS_REGION=ap-northeast-2 \
MSK_MODE=provisioned \
MSK_BOOTSTRAP_BROKERS='b-1.example:9092,b-2.example:9092' \
RDS_SECRET_NAME='cdc-lakehouse-tutorial-sandbox/rds/source' \
EKS_CLUSTER_NAME='cdc-lakehouse-tutorial-sandbox' \
LAKEHOUSE_WORKLOADS_ROLE_ARN='arn:aws:iam::123456789012:role/cdc-lakehouse-tutorial-sandbox-lakehouse' \
DATA_WORKLOADS_ROLE_ARN='arn:aws:iam::123456789012:role/cdc-lakehouse-tutorial-sandbox-data' \
PLATFORM_WORKLOADS_ROLE_ARN='arn:aws:iam::123456789012:role/cdc-lakehouse-tutorial-sandbox-platform' \
ML_WORKLOADS_ROLE_ARN='arn:aws:iam::123456789012:role/cdc-lakehouse-tutorial-sandbox-ml' \
LAKEHOUSE_BUCKET='cdc-lakehouse-tutorial-sandbox-lakehouse-123456789012' \
SOURCE_GENERATOR_REPOSITORY_URL='123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/cdc-lakehouse-tutorial-sandbox/source-generator' \
FLINK_RUNTIME_REPOSITORY_URL='123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/cdc-lakehouse-tutorial-sandbox/flink-runtime' \
scripts/render-k8s-config.sh
```

Check for bad render output:

```bash
rg -n $'\033|Warning:|No outputs found|REPLACE_WITH_' k8s/rendered && exit 1 || true
find k8s/rendered/apps -maxdepth 4 -name kustomization.yaml -print | sort |
  while read -r file; do
    kubectl kustomize "$(dirname "$file")" >/tmp/kustomize-one.yaml
  done
```

## Phase 3: Provision AWS

Plan and apply only after local validation passes and AWS auth is active.

```bash
tofu -chdir=infra/opentofu plan -out=tfplan
tofu -chdir=infra/opentofu apply tfplan
```

Record:

```bash
tofu -chdir=infra/opentofu output
aws eks describe-cluster \
  --region ap-northeast-2 \
  --name "$(tofu -chdir=infra/opentofu output -raw eks_cluster_name)" \
  --query 'cluster.{name:name,version:version,status:status,endpoint:endpoint}'
aws kafka list-clusters-v2 \
  --region ap-northeast-2 \
  --query 'ClusterInfoList[?ClusterName==`'"$(tofu -chdir=infra/opentofu output -raw eks_cluster_name)"'`]'
aws rds describe-db-instances \
  --region ap-northeast-2 \
  --db-instance-identifier "$(tofu -chdir=infra/opentofu output -raw eks_cluster_name)-source" \
  --query 'DBInstances[0].{id:DBInstanceIdentifier,engine:Engine,version:EngineVersion,status:DBInstanceStatus}'
```

## Phase 4: Build And Push Runtime Images

Authenticate to ECR:

```bash
aws ecr get-login-password --region ap-northeast-2 |
  docker login --username AWS --password-stdin \
  "$(tofu -chdir=infra/opentofu output -raw source_generator_repository_url | cut -d/ -f1)"
```

Build and push:

```bash
SOURCE_GENERATOR_REPO="$(tofu -chdir=infra/opentofu output -raw source_generator_repository_url)"
FLINK_RUNTIME_REPO="$(tofu -chdir=infra/opentofu output -raw flink_runtime_repository_url)"

docker build --platform linux/amd64 -t "$SOURCE_GENERATOR_REPO:latest" apps/generator
docker build --platform linux/amd64 -t "$FLINK_RUNTIME_REPO:latest" flink/runtime

docker push "$SOURCE_GENERATOR_REPO:latest"
docker push "$FLINK_RUNTIME_REPO:latest"

aws ecr describe-images \
  --region ap-northeast-2 \
  --repository-name "$(basename "$SOURCE_GENERATOR_REPO")" \
  --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' \
  --output text
aws ecr describe-images \
  --region ap-northeast-2 \
  --repository-name "$(basename "$FLINK_RUNTIME_REPO")" \
  --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' \
  --output text
```

Record image URIs and digests.

## Phase 5: Render Real GitOps Manifests

Render with real OpenTofu outputs:

```bash
scripts/render-k8s-config.sh
rg -n $'\033|Warning:|No outputs found|REPLACE_WITH_' k8s/rendered && exit 1 || true
```

Commit only the intended upgrade, rendered manifests, lockfile, and evidence
updates. Preserve unrelated user document edits unless intentionally included.

Use the repository's lore commit protocol.

## Phase 6: Install And Sync Argo CD

```bash
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name "$(tofu -chdir=infra/opentofu output -raw eks_cluster_name)"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=300s

kubectl apply -f k8s/rendered/argocd/root-app.yaml
kubectl -n argocd annotate application cdc-lakehouse-root \
  argocd.argoproj.io/refresh=hard --overwrite
```

Record:

```bash
kubectl -n argocd get applications.argoproj.io -o wide
kubectl -n argocd get applications.argoproj.io \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\t"}{.status.sync.revision}{"\n"}{end}'
```

Proceed only when required platform and data apps are `Synced` and `Healthy`.

## Phase 7: Prove CDC To Iceberg

Bootstrap source schemas and start live writes:

```bash
kubectl -n data create job source-generator-bootstrap-manual \
  --from=job/source-generator-bootstrap || true
kubectl -n data wait --for=condition=complete \
  job/source-generator-bootstrap-manual --timeout=300s

kubectl -n data rollout status deploy/source-generator --timeout=300s
kubectl -n data rollout status deploy/kafka-connect --timeout=300s
```

Check Kafka Connect:

```bash
kubectl -n data port-forward svc/kafka-connect 8083:8083 >/tmp/kafka-connect-pf.log 2>&1 &
PF_PID=$!
sleep 5
curl -fsS localhost:8083/connectors
curl -fsS localhost:8083/connectors/rds-commerce-source/status
kill "$PF_PID"
```

Check Flink:

```bash
kubectl -n data get flinkdeployment orders-cdc -o yaml
kubectl -n data get pods -o wide
kubectl -n data logs deploy/orders-cdc --tail=200 || true
kubectl -n data get flinkdeployment orders-cdc \
  -o jsonpath='{.status.jobStatus.state}{"\n"}{.status.lifecycleState}{"\n"}'
```

Check S3 and Glue:

```bash
LAKEHOUSE_BUCKET="$(tofu -chdir=infra/opentofu output -raw lakehouse_bucket)"
aws s3 ls "s3://$LAKEHOUSE_BUCKET/warehouse/" --recursive --summarize | tail -50
aws glue get-databases --region ap-northeast-2 \
  --query 'DatabaseList[?starts_with(Name, `lab_`)].Name' \
  --output table
aws glue get-tables --region ap-northeast-2 --database-name lab_bronze \
  --query 'TableList[].Name' --output table
aws glue get-tables --region ap-northeast-2 --database-name lab_silver \
  --query 'TableList[].Name' --output table
aws glue get-tables --region ap-northeast-2 --database-name lab_gold \
  --query 'TableList[].Name' --output table
```

Check Trino:

```bash
kubectl -n data port-forward svc/trino 8080:8080 >/tmp/trino-pf.log 2>&1 &
TRINO_PF_PID=$!
sleep 5
kubectl -n data run trino-cli-check --rm -i --restart=Never \
  --image=trinodb/trino:480 \
  --command -- trino --server http://trino:8080 --catalog iceberg --execute '
    SHOW SCHEMAS;
    SELECT count(*) AS bronze_orders FROM lab_bronze.orders_cdc;
    SELECT count(*) AS silver_orders FROM lab_silver.orders_current;
    SELECT * FROM lab_gold.revenue_10m ORDER BY window_start DESC LIMIT 10;
  '
kill "$TRINO_PF_PID"
```

Minimum evidence required:

- Kafka Connect connector and task state are `RUNNING`.
- FlinkDeployment lifecycle is stable and the job is running.
- S3 has Iceberg metadata and data files under the warehouse path.
- Glue has Bronze, Silver, and Gold tables.
- Trino returns non-error counts from Bronze and Silver.
- At least one Gold query returns rows or a defensible empty result tied to the
  current generated data window.

## Phase 8: Teardown

Teardown is part of completion, not cleanup after completion.

First remove GitOps-managed Kubernetes resources:

```bash
kubectl -n argocd delete application cdc-lakehouse-root --ignore-not-found
kubectl -n argocd delete applications.argoproj.io --all --ignore-not-found
kubectl delete namespace data platform ml kubeflow cert-manager argocd \
  --ignore-not-found --wait=false
```

If Flink finalizers block namespace deletion, remove stale webhooks first:

```bash
kubectl delete validatingwebhookconfiguration flink-operator-data-webhook-configuration --ignore-not-found
kubectl delete mutatingwebhookconfiguration flink-operator-data-webhook-configuration --ignore-not-found
kubectl -n data patch flinkdeployment orders-cdc \
  --type=merge -p '{"metadata":{"finalizers":[]}}' || true
```

Then destroy cloud resources:

```bash
tofu -chdir=infra/opentofu destroy
```

If destroy is blocked:

- Empty versioned S3 bucket objects and delete markers, then retry.
- Delete remaining ECR images, then retry.
- Keep polling EKS node groups and MSK clusters while AWS reports deletion in
  progress.

## Phase 9: Prove Teardown

Completion requires proof that billable resources are gone:

```bash
tofu -chdir=infra/opentofu state list

aws eks describe-cluster \
  --region ap-northeast-2 \
  --name "$(tofu -chdir=infra/opentofu output -raw eks_cluster_name 2>/dev/null || echo cdc-lakehouse-tutorial-sandbox)"

aws kafka list-clusters-v2 --region ap-northeast-2 \
  --query 'ClusterInfoList[?contains(ClusterName, `cdc-lakehouse`)]'

aws rds describe-db-instances --region ap-northeast-2 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `cdc-lakehouse`)].DBInstanceIdentifier'

aws s3api head-bucket --bucket "$LAKEHOUSE_BUCKET"

aws ecr describe-repositories --region ap-northeast-2 \
  --query 'repositories[?contains(repositoryName, `cdc-lakehouse`)].repositoryName'

aws glue get-databases --region ap-northeast-2 \
  --query 'DatabaseList[?starts_with(Name, `lab_`)].Name'
```

Acceptable teardown evidence:

- `tofu state list` is empty.
- EKS returns not found for the cluster.
- MSK cluster list has no matching lab cluster.
- RDS has no matching source instance.
- S3 lakehouse bucket returns not found or no such bucket.
- ECR has no matching lab repositories.
- Glue has no lab databases.

Only after this evidence is recorded can the goal be marked complete.
