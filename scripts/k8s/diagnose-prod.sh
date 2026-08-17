#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=kubectl \
NAMESPACE="${NAMESPACE:-litellm}" \
SERVICE_NAME="${SERVICE_NAME:-litellm-api}" \
HELM_RELEASE="${HELM_RELEASE:-litellm}" \
HELM_NAMESPACE="${HELM_NAMESPACE:-${NAMESPACE:-litellm}}" \
KUBE_CONTEXT="${KUBE_CONTEXT:-}" \
"$SCRIPT_DIR/diagnose-cluster.sh"
