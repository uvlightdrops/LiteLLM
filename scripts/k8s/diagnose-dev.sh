#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=minikube \
NAMESPACE="${NAMESPACE:-litellm-dev}" \
SERVICE_NAME="${SERVICE_NAME:-litellm-api}" \
SHOW_MINIKUBE_URL=true \
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}" \
"$SCRIPT_DIR/diagnose-cluster.sh"
