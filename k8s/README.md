# LiteLLM Kubernetes deployment

This repository now keeps the Kubernetes layout aligned by environment:

- `k8s/dev/` - direct Minikube manifests for local development
- `k8s/prod/templates/` - production templates for `yaml_config_support`
- `k8s/prod/generated/` - rendered production manifests
- `scripts/k8s/` - diagnostics helpers

## Deployment model

- Local dev: Minikube on localhost
  - namespace: `litellm-dev`
  - service: `NodePort` on port `30080`
  - ingress disabled
  - local PostgreSQL runs in-cluster
- Real prod: dedicated cluster
  - namespace: `litellm`
  - service: `ClusterIP`
  - ingress enabled with TLS
  - manifests rendered from `k8s/prod/templates/`

## Value store

The secret files are stored outside the repo in a private directory:

```bash
mkdir -p ~/dev_data/LiteLLM
chmod 700 ~/dev_data/LiteLLM
```

Optional override:

```bash
export LITELLM_SECRET_DIR=~/dev_data/LiteLLM
```

## Local Minikube dev flow

```bash
minikube start
kubectl apply -f k8s/dev/
minikube service litellm-api -n litellm-dev --url
```

## Production flow

```bash
cd /home/flow/dev_ldbv/LiteLLM
python k8s/k8s_fill_config.py prod
kubectl apply -f k8s/prod/generated/cf-prod/
```

## Diagnostics

Use the bundled scripts to collect a quick status snapshot for nodes and workloads:

```bash
chmod +x scripts/k8s/*.sh
./scripts/k8s/diagnose-dev.sh
./scripts/k8s/diagnose-prod.sh
```

Useful overrides:

```bash
NAMESPACE=litellm-dev ./scripts/k8s/diagnose-dev.sh
KUBE_CONTEXT=prod-cluster HELM_RELEASE=litellm ./scripts/k8s/diagnose-prod.sh
```

## Notes

- Secrets are intentionally not committed.
- `k8s/prod/generated/` is ignored in git.
- The production manifests are rendered by the `yaml_config_support` overlay mechanism.
