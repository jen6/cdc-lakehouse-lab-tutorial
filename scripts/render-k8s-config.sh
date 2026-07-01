#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOFU_DIR="${TOFU_DIR:-$ROOT_DIR/infra/opentofu}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/k8s/rendered}"

cd "$TOFU_DIR"

tofu_output_raw() {
  tofu output -no-color -raw "$1" 2>/dev/null || true
}

reject_bad_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *"Warning:"* || "$value" == *"No outputs found"* || "$value" == *$'\033'* ]]; then
    echo "Missing required render value: $name. Run tofu apply first or provide the matching environment override." >&2
    exit 1
  fi
}

value_from_env_or_output() {
  local env_name="$1"
  local output_name="$2"
  local required="${3:-required}"
  local value="${!env_name:-}"
  if [[ -z "$value" ]]; then
    value="$(tofu_output_raw "$output_name")"
  fi
  if [[ "$required" == "required" ]]; then
    reject_bad_value "$env_name/$output_name" "$value"
  fi
  printf '%s' "$value"
}

repo_url="$(value_from_env_or_output ARGOCD_REPOSITORY_URL argocd_repository_url)"
aws_region="$(value_from_env_or_output AWS_REGION aws_region)"
msk_mode="$(value_from_env_or_output MSK_MODE msk_mode)"
msk_bootstrap="$(value_from_env_or_output MSK_BOOTSTRAP_BROKERS msk_bootstrap_brokers)"
rds_secret_name="$(value_from_env_or_output RDS_SECRET_NAME rds_secret_name)"
eks_cluster_name="$(value_from_env_or_output EKS_CLUSTER_NAME eks_cluster_name)"
lakehouse_role_arn="$(value_from_env_or_output LAKEHOUSE_WORKLOADS_ROLE_ARN lakehouse_workloads_role_arn)"
data_role_arn="$(value_from_env_or_output DATA_WORKLOADS_ROLE_ARN data_workloads_role_arn optional)"
platform_role_arn="$(value_from_env_or_output PLATFORM_WORKLOADS_ROLE_ARN platform_workloads_role_arn optional)"
ml_role_arn="$(value_from_env_or_output ML_WORKLOADS_ROLE_ARN ml_workloads_role_arn optional)"
lakehouse_bucket="$(value_from_env_or_output LAKEHOUSE_BUCKET lakehouse_bucket)"
source_generator_repository_url="$(value_from_env_or_output SOURCE_GENERATOR_REPOSITORY_URL source_generator_repository_url)"
flink_runtime_repository_url="$(value_from_env_or_output FLINK_RUNTIME_REPOSITORY_URL flink_runtime_repository_url)"
source_generator_image="${SOURCE_GENERATOR_IMAGE:-$source_generator_repository_url:latest}"
flink_image="${FLINK_ICEBERG_IMAGE:-$flink_runtime_repository_url:latest}"
msk_cluster_name="${MSK_CLUSTER_NAME:-$eks_cluster_name}"
rds_db_instance_identifier="${RDS_DB_INSTANCE_IDENTIFIER:-$eks_cluster_name-source}"

data_role_arn="${data_role_arn:-$lakehouse_role_arn}"
platform_role_arn="${platform_role_arn:-$lakehouse_role_arn}"
ml_role_arn="${ml_role_arn:-$lakehouse_role_arn}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R "$ROOT_DIR/k8s/argocd" "$OUT_DIR/argocd"
cp -R "$ROOT_DIR/k8s/apps" "$OUT_DIR/apps"
mkdir -p "$OUT_DIR/flink"
cp "$ROOT_DIR/flink/README.md" "$OUT_DIR/flink/README.md"
cp -R "$ROOT_DIR/flink/sql" "$OUT_DIR/flink/sql"

export RENDER_REPO_URL="$repo_url"
export RENDER_AWS_REGION="$aws_region"
export RENDER_MSK_MODE="$msk_mode"
export RENDER_MSK_BOOTSTRAP="$msk_bootstrap"
export RENDER_MSK_CLUSTER_NAME="$msk_cluster_name"
export RENDER_RDS_DB_INSTANCE_IDENTIFIER="$rds_db_instance_identifier"
export RENDER_RDS_SECRET_NAME="$rds_secret_name"
export RENDER_DATA_ROLE_ARN="$data_role_arn"
export RENDER_PLATFORM_ROLE_ARN="$platform_role_arn"
export RENDER_ML_ROLE_ARN="$ml_role_arn"
export RENDER_LAKEHOUSE_BUCKET="$lakehouse_bucket"
export RENDER_SOURCE_GENERATOR_IMAGE="$source_generator_image"
export RENDER_FLINK_IMAGE="$flink_image"

find "$OUT_DIR" -type f \( -name '*.yaml' -o -name '*.sql' \) -print0 |
  xargs -0 perl -pi -e '
    s#https://github.com/your-org/cdc-lakehouse-lab.git#$ENV{RENDER_REPO_URL}#g;
    s#REPLACE_WITH_MSK_MODE#$ENV{RENDER_MSK_MODE}#g;
    s#REPLACE_WITH_MSK_BOOTSTRAP_BROKERS#$ENV{RENDER_MSK_BOOTSTRAP}#g;
    s#REPLACE_WITH_MSK_CLUSTER_NAME#$ENV{RENDER_MSK_CLUSTER_NAME}#g;
    s#REPLACE_WITH_RDS_DB_INSTANCE_IDENTIFIER#$ENV{RENDER_RDS_DB_INSTANCE_IDENTIFIER}#g;
    s#REPLACE_WITH_RDS_SECRET_NAME#$ENV{RENDER_RDS_SECRET_NAME}#g;
    s#REPLACE_WITH_DATA_WORKLOADS_ROLE_ARN#$ENV{RENDER_DATA_ROLE_ARN}#g;
    s#REPLACE_WITH_PLATFORM_WORKLOADS_ROLE_ARN#$ENV{RENDER_PLATFORM_ROLE_ARN}#g;
    s#REPLACE_WITH_ML_WORKLOADS_ROLE_ARN#$ENV{RENDER_ML_ROLE_ARN}#g;
    s#REPLACE_WITH_LAKEHOUSE_BUCKET#$ENV{RENDER_LAKEHOUSE_BUCKET}#g;
    s#REPLACE_WITH_SOURCE_GENERATOR_IMAGE#$ENV{RENDER_SOURCE_GENERATOR_IMAGE}#g;
    s#REPLACE_WITH_FLINK_ICEBERG_IMAGE#$ENV{RENDER_FLINK_IMAGE}#g;
    s#ap-northeast-2#$ENV{RENDER_AWS_REGION}#g;
  '

perl -pi -e 's#path: k8s/argocd/apps#path: k8s/rendered/argocd/apps#g' "$OUT_DIR/argocd/root-app.yaml"
find "$OUT_DIR/argocd/apps" -type f -name '*.yaml' -print0 |
  xargs -0 perl -pi -e 's#path: k8s/apps/#path: k8s/rendered/apps/#g'

echo "Rendered Kubernetes config to $OUT_DIR"
