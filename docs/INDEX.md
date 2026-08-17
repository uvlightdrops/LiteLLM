# LiteLLM Kubernetes deployment docs

## Scope

This repository contains a small Kubernetes deployment setup for LiteLLM with split configuration:

- public YAML templates in `k8s/templates/`
- private secrets in `~/dev_data/LiteLLM`
- generated final manifests in `k8s/generated/`

## Local dev mode (Minikube)

Use the `dev` configuration for local execution on this machine:

```bash
cd /home/flow/dev_ldbv/LiteLLM
python k8s/k8s_fill_config.py dev
kubectl apply -f k8s/generated/cf-dev/
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
kubectl apply -f k8s/generated/cf-prod/
```

This deployment:

- uses namespace `litellm`
- runs with ClusterIP + ingress + TLS
- expects the real cluster environment and DNS entries

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
