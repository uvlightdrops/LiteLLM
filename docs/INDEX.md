# LiteLLM Kubernetes deployment docs

## Scope

This repository contains a Kubernetes deployment setup for LiteLLM with a clearer split:

- direct dev manifests in `k8s/dev/`
- production templates in `k8s/prod/templates/`
- private secrets in `~/dev_data/LiteLLM`
- generated production manifests in `k8s/prod/generated/`

## Local dev mode (Minikube)

Use the `dev` configuration for local execution on this machine:

```bash
cd /home/flow/dev_ldbv/LiteLLM
kubectl apply -f k8s/dev/
minikube service litellm-api -n litellm-dev --url
```

This deployment:

- uses namespace `litellm-dev`
- exposes the service as `NodePort` on `localhost`
- keeps ingress disabled for local testing

## Production mode (real cluster)

Use the `prod` configuration for a real Kubernetes cluster:

```bash
cd /home/flow/dev_ldbv/LiteLLM
python k8s/k8s_fill_config.py prod
kubectl apply -f k8s/prod/generated/cf-prod/
```

This deployment:

- uses namespace `litellm`
- runs with ClusterIP + ingress + TLS
- expects the real cluster environment and DNS entries

## Diagnostics scripts

Quick checks for node and workload status:

```bash
chmod +x scripts/k8s/*.sh
./scripts/k8s/diagnose-dev.sh
./scripts/k8s/diagnose-prod.sh
```

Optional overrides:

```bash
MINIKUBE_PROFILE=minikube ./scripts/k8s/diagnose-dev.sh
KUBE_CONTEXT=prod-cluster HELM_RELEASE=litellm ./scripts/k8s/diagnose-prod.sh
```

## Secret directory

```bash
mkdir -p ~/dev_data/LiteLLM
chmod 700 ~/dev_data/LiteLLM
```

The secret files are:

- `~/dev_data/LiteLLM/values_creds_dev.yaml`
- `~/dev_data/LiteLLM/values_creds_staging.yaml`
- `~/dev_data/LiteLLM/values_creds_prod.yaml`

## Important

All secret values are placeholders by default and must be filled before deployment. Do not commit the private directory.
