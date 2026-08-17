# LiteLLM Kubernetes deployment

This repository contains the Kubernetes templates and a small wrapper around the `yaml_config_support` package.

## Deployment model

- Local dev: Minikube on localhost
  - namespace: `litellm-dev`
  - service: `NodePort` on port `30080`
  - ingress disabled
  - secrets from `~/dev_data/LiteLLM`
- Real prod: dedicated cluster
  - namespace: `litellm`
  - service: `ClusterIP`
  - ingress enabled with TLS and cert-manager

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

Example secret file (`~/dev_data/LiteLLM/values_creds_dev.yaml`):

```yaml
stringData:
  litellm-master-key: "dev-secret"
  database-url: "postgresql://litellm:devpw@postgres-dev:5432/litellm_dev"
  database-password: "devpw"
  openai-api-key: "sk-dev"
  anthropic-api-key: "sk-ant-dev"
  jwt-secret: "dev-jwt-secret"
```

## Generate rendered manifests

```bash
cd /home/flow/dev_ldbv/LiteLLM
python k8s/k8s_fill_config.py dev
python k8s/k8s_fill_config.py prod --outdir /tmp/litellm-k8s
```

## Local Minikube dev flow

```bash
minikube start
python k8s/k8s_fill_config.py dev
kubectl apply -f k8s/generated/cf-dev/
minikube service litellm-api -n litellm-dev --url
```

## Production flow

```bash
python k8s/k8s_fill_config.py prod
kubectl apply -f k8s/generated/cf-prod/
```

## Notes

- Secrets are intentionally not committed.
- `k8s/generated/` is ignored in git.
- The generated manifests are rendered by the `yaml_config_support` overlay mechanism.
