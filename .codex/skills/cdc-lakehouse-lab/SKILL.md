---
name: cdc-lakehouse-lab
description: Set up, verify, operate, and tear down this repository's AWS CDC Lakehouse tutorial lab. Use when Codex is asked to deploy the lab with OpenTofu/Terraform, render and commit GitOps manifests, configure Argo CD for a private GitHub repo, check app health, avoid impacting existing AWS infrastructure, or destroy the lab after use.
---

# CDC Lakehouse Lab

Use the repository script `scripts/labctl.sh` as the primary control surface. It keeps all mutable state inside this clone, generates a unique `terraform.tfvars`, renders `k8s/rendered`, configures Argo CD repository access, and requires an explicit `--yes` for teardown.

## Safety Rules

- Never run raw `tofu apply` or `tofu destroy` first. Start with `scripts/labctl.sh init` or `scripts/labctl.sh plan`.
- Refuse to operate on `project = "cdc-lakehouse"` with `environment = "lab"`; that name is reserved for the original development environment.
- Keep `k8s/rendered/`, `terraform.tfvars`, tfstate, `.terraform/`, and `.tmp/` out of the seed/tutorial commit. The rendered overlay is generated and force-added only in the user's lab repo after OpenTofu outputs exist.
- Use the repo's current `origin` remote as `repository_url`. For private GitHub repos, let `labctl.sh deploy` create a read-only deploy key and an Argo CD repository secret.
- Only run teardown when the user explicitly asks to delete/destroy the lab. Use `scripts/labctl.sh teardown --yes`.

## Workflows

### First deploy

1. Verify the clone has its own GitHub remote:
   ```bash
   git remote -v
   ```
2. Initialize repo-local variables:
   ```bash
   LAB_ID=tutorial-<short-name> scripts/labctl.sh init
   ```
3. Review the plan:
   ```bash
   scripts/labctl.sh plan
   ```
4. Deploy:
   ```bash
   scripts/labctl.sh deploy
   ```

`deploy` runs OpenTofu, builds/pushes the source generator and Flink runtime images to the lab ECR repos, renders `k8s/rendered`, commits/pushes the rendered overlay, installs Argo CD, configures repo access, applies the rendered root app, and prints status.

### Status checks

Use:

```bash
scripts/labctl.sh status
```

If more detail is needed, check:

```bash
kubectl -n argocd get applications.argoproj.io -o wide
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n data get flinkdeployment orders-cdc
```

### Re-render after infrastructure output changes

Use this after changing OpenTofu outputs, images, or Kubernetes templates:

```bash
scripts/labctl.sh render
scripts/labctl.sh commit-rendered
```

### Teardown

Only when explicitly requested:

```bash
scripts/labctl.sh teardown --yes
```

This removes Argo applications/namespaces best-effort, runs `tofu destroy -auto-approve` from `infra/opentofu`, and removes the lab deploy key when GitHub CLI access is available.

## Expected Prerequisites

The host should have `git`, `gh`, `aws`, `tofu`, `kubectl`, `docker`, and `ssh-keygen`. AWS credentials must point at the intended lab account/region before deploy or teardown.
