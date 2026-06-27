#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOFU_DIR="$ROOT_DIR/infra/opentofu"
TMP_DIR="$ROOT_DIR/.tmp"
TFVARS="$TOFU_DIR/terraform.tfvars"
PLAN_FILE="$TMP_DIR/lab.tfplan"
ARGO_REPO_KEY="$TMP_DIR/argocd_repo_key"

usage() {
  cat <<'USAGE'
Usage: scripts/labctl.sh <command> [--yes]

Commands:
  init              Create a repo-local terraform.tfvars with a unique lab name.
  plan              Run tofu init/validate/plan.
  deploy            Apply OpenTofu, build/push images, render GitOps manifests,
                    commit/push k8s/rendered, install Argo CD, and apply root app.
  render            Render k8s/rendered from OpenTofu outputs.
  commit-rendered   Commit and push k8s/rendered to the current Git remote.
  status            Show Argo applications and non-running pods.
  teardown --yes    Delete Argo apps/namespaces, run tofu destroy, and remove the
                    lab deploy key when possible.

Environment:
  LAB_ID            Unique suffix used by init. Default: tutorial-<user>-<MMddHHmm>.
  LAB_MSK_MODE      provisioned or serverless. Default: provisioned.
  AWS_PROFILE       Optional AWS profile used by aws/tofu providers.
USAGE
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_base_tools() {
  need_cmd git
  need_cmd tofu
  need_cmd aws
  need_cmd kubectl
}

repo_ssh_url() {
  local remote
  remote="$(git -C "$ROOT_DIR" config --get remote.origin.url || true)"
  if [[ -z "$remote" ]]; then
    echo "No git remote.origin.url is configured." >&2
    exit 1
  fi

  if [[ "$remote" =~ ^https://github.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
    local repo="${BASH_REMATCH[2]%.git}"
    echo "git@github.com:${BASH_REMATCH[1]}/${repo}.git"
  elif [[ "$remote" =~ ^git@github.com:([^/]+)/(.+)$ ]]; then
    local repo="${BASH_REMATCH[2]%.git}"
    echo "git@github.com:${BASH_REMATCH[1]}/${repo}.git"
  else
    echo "$remote"
  fi
}

repo_name_with_owner() {
  if command -v gh >/dev/null 2>&1; then
    gh repo view "$(repo_ssh_url)" --json nameWithOwner --jq .nameWithOwner 2>/dev/null && return 0
    gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null && return 0
  fi

  local url
  url="$(repo_ssh_url)"
  if [[ "$url" =~ git@github.com:([^/]+/.+)\.git$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

sanitize_lab_id() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//' | cut -c1-28
}

tfvar_value() {
  local key="$1"
  sed -nE "s/^${key}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" "$TFVARS" | head -1
}

init_tfvars() {
  require_base_tools
  mkdir -p "$TMP_DIR"

  if [[ -f "$TFVARS" ]]; then
    echo "Using existing $TFVARS"
    guard_tfvars
    return 0
  fi

  local raw_lab_id lab_id repo_url msk_mode
  raw_lab_id="${LAB_ID:-tutorial-$(whoami)-$(date +%m%d%H%M)}"
  lab_id="$(sanitize_lab_id "$raw_lab_id")"
  repo_url="$(repo_ssh_url)"
  msk_mode="${LAB_MSK_MODE:-provisioned}"

  if [[ "$msk_mode" != "provisioned" && "$msk_mode" != "serverless" ]]; then
    echo "LAB_MSK_MODE must be provisioned or serverless." >&2
    exit 1
  fi

  cat >"$TFVARS" <<EOF
aws_region  = "ap-northeast-2"
project     = "cdc-lakehouse-${lab_id}"
environment = "lab"

repository_url = "${repo_url}"

msk_mode             = "${msk_mode}"
az_count             = 2
msk_broker_count     = 2
msk_instance_type    = "kafka.t3.small"
msk_ebs_volume_size  = 100
rds_instance_class   = "db.t4g.medium"
rds_allocated_storage = 100

eks_node_instance_types = ["m6i.large"]
eks_node_min_size       = 1
eks_node_desired_size   = 2
eks_node_max_size       = 4

rds_skip_final_snapshot = true
EOF

  echo "Created $TFVARS for cdc-lakehouse-${lab_id}-lab"
  guard_tfvars
}

guard_tfvars() {
  if [[ ! -f "$TFVARS" ]]; then
    echo "Missing $TFVARS. Run: scripts/labctl.sh init" >&2
    exit 1
  fi

  local project environment name
  project="$(tfvar_value project)"
  environment="$(tfvar_value environment)"
  name="${project}-${environment}"

  if [[ -z "$project" || -z "$environment" ]]; then
    echo "$TFVARS must set quoted project and environment values." >&2
    exit 1
  fi

  if [[ "$name" == "cdc-lakehouse-lab" ]]; then
    echo "Refusing to operate on cdc-lakehouse-lab; choose a unique tutorial lab id." >&2
    exit 1
  fi
}

tofu_init_validate() {
  guard_tfvars
  tofu -chdir="$TOFU_DIR" init
  tofu -chdir="$TOFU_DIR" validate
}

plan_lab() {
  require_base_tools
  mkdir -p "$TMP_DIR"
  init_tfvars
  tofu_init_validate
  tofu -chdir="$TOFU_DIR" plan -out="$PLAN_FILE"
}

apply_lab() {
  require_base_tools
  if [[ ! -f "$PLAN_FILE" ]]; then
    plan_lab
  fi
  tofu -chdir="$TOFU_DIR" apply "$PLAN_FILE"
}

update_kubeconfig() {
  local region cluster
  region="$(tofu -chdir="$TOFU_DIR" output -raw aws_region)"
  cluster="$(tofu -chdir="$TOFU_DIR" output -raw eks_cluster_name)"
  aws eks update-kubeconfig --region "$region" --name "$cluster" --alias "$cluster"
}

ecr_login_for_repo() {
  local repo_url region registry
  repo_url="$1"
  region="$(tofu -chdir="$TOFU_DIR" output -raw aws_region)"
  registry="${repo_url%%/*}"
  aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry" >/dev/null
}

build_images() {
  need_cmd docker
  require_base_tools

  local source_repo flink_repo
  source_repo="$(tofu -chdir="$TOFU_DIR" output -raw source_generator_repository_url)"
  flink_repo="$(tofu -chdir="$TOFU_DIR" output -raw flink_runtime_repository_url)"

  ecr_login_for_repo "$source_repo"
  docker build --platform linux/amd64 -t "${source_repo}:latest" "$ROOT_DIR/apps/generator"
  docker push "${source_repo}:latest"

  ecr_login_for_repo "$flink_repo"
  docker build --platform linux/amd64 -t "${flink_repo}:latest" "$ROOT_DIR/flink/runtime"
  docker push "${flink_repo}:latest"
}

render_manifests() {
  require_base_tools
  guard_tfvars
  "$ROOT_DIR/scripts/render-k8s-config.sh"
}

commit_rendered() {
  need_cmd git
  if [[ ! -d "$ROOT_DIR/k8s/rendered" ]]; then
    echo "Missing k8s/rendered. Run: scripts/labctl.sh render" >&2
    exit 1
  fi

  git -C "$ROOT_DIR" add -f k8s/rendered
  if git -C "$ROOT_DIR" diff --cached --quiet -- k8s/rendered; then
    echo "No rendered manifest changes to commit."
  else
    git -C "$ROOT_DIR" commit -m "Render lab GitOps manifests"
  fi
  git -C "$ROOT_DIR" push origin HEAD
}

install_argocd() {
  require_base_tools
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
  kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
  kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
}

configure_argocd_repo_secret() {
  require_base_tools
  need_cmd gh
  need_cmd ssh-keygen

  local repo_url nwo title key_id
  repo_url="$(repo_ssh_url)"
  nwo="$(repo_name_with_owner)"
  title="argocd-cdc-lakehouse-$(tfvar_value project)-$(tfvar_value environment)"

  mkdir -p "$TMP_DIR"
  if [[ ! -f "$ARGO_REPO_KEY" ]]; then
    ssh-keygen -t ed25519 -N "" -C "$title" -f "$ARGO_REPO_KEY" >/dev/null
  fi

  key_id="$(gh api "repos/${nwo}/keys" --jq ".[] | select(.title == \"${title}\") | .id" 2>/dev/null | head -1 || true)"
  if [[ -z "$key_id" ]]; then
    gh repo deploy-key add "${ARGO_REPO_KEY}.pub" --repo "$nwo" --title "$title" >/dev/null
  fi

  kubectl -n argocd create secret generic cdc-lakehouse-lab-repo \
    --from-literal=type=git \
    --from-literal=url="$repo_url" \
    --from-file=sshPrivateKey="$ARGO_REPO_KEY" \
    --dry-run=client -o yaml |
    kubectl apply -f -
  kubectl -n argocd label secret cdc-lakehouse-lab-repo argocd.argoproj.io/secret-type=repository --overwrite
}

apply_root_app() {
  if [[ ! -f "$ROOT_DIR/k8s/rendered/argocd/root-app.yaml" ]]; then
    echo "Missing rendered root app. Run deploy or render first." >&2
    exit 1
  fi
  kubectl apply -f "$ROOT_DIR/k8s/rendered/argocd/root-app.yaml"
}

status_lab() {
  update_kubeconfig >/dev/null 2>&1 || true
  kubectl -n argocd get applications.argoproj.io -o wide || true
  kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded || true
}

deploy_lab() {
  plan_lab
  apply_lab
  build_images
  update_kubeconfig
  render_manifests
  commit_rendered
  install_argocd
  configure_argocd_repo_secret
  apply_root_app
  status_lab
}

remove_deploy_key() {
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi

  local nwo title key_id
  nwo="$(repo_name_with_owner 2>/dev/null || true)"
  title="argocd-cdc-lakehouse-$(tfvar_value project)-$(tfvar_value environment)"
  if [[ -z "$nwo" ]]; then
    return 0
  fi

  key_id="$(gh api "repos/${nwo}/keys" --jq ".[] | select(.title == \"${title}\") | .id" 2>/dev/null | head -1 || true)"
  if [[ -n "$key_id" ]]; then
    gh api -X DELETE "repos/${nwo}/keys/${key_id}" >/dev/null || true
  fi
  rm -f "$ARGO_REPO_KEY" "${ARGO_REPO_KEY}.pub"
}

teardown_lab() {
  local yes="${1:-}"
  if [[ "$yes" != "--yes" ]]; then
    echo "teardown is destructive. Re-run: scripts/labctl.sh teardown --yes" >&2
    exit 1
  fi

  require_base_tools
  guard_tfvars
  update_kubeconfig || true

  kubectl -n argocd delete applications.argoproj.io cdc-lakehouse-root --ignore-not-found --wait=true || true
  kubectl -n argocd delete applications.argoproj.io --all --ignore-not-found --wait=false || true
  kubectl delete namespace data platform ml kubeflow cert-manager argocd --ignore-not-found --wait=false || true

  tofu -chdir="$TOFU_DIR" destroy -auto-approve
  remove_deploy_key
}

cmd="${1:-}"
case "$cmd" in
  init)
    init_tfvars
    ;;
  plan)
    plan_lab
    ;;
  deploy)
    deploy_lab
    ;;
  render)
    render_manifests
    ;;
  commit-rendered)
    commit_rendered
    ;;
  status)
    status_lab
    ;;
  teardown)
    teardown_lab "${2:-}"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
