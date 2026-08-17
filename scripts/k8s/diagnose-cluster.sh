#!/usr/bin/env bash

set -uo pipefail

MODE="${MODE:-kubectl}"
NAMESPACE="${NAMESPACE:-litellm}"
SERVICE_NAME="${SERVICE_NAME:-litellm-api}"
HELM_RELEASE="${HELM_RELEASE:-}"
HELM_NAMESPACE="${HELM_NAMESPACE:-$NAMESPACE}"
SHOW_MINIKUBE_URL="${SHOW_MINIKUBE_URL:-false}"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

section() {
  printf '\n== %s ==\n' "$1"
}

run_kubectl() {
  if [[ "$MODE" == "minikube" ]]; then
    minikube -p "$MINIKUBE_PROFILE" kubectl -- "$@"
  elif [[ -n "$KUBE_CONTEXT" ]]; then
    kubectl --context "$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

best_effort() {
  "$@" || true
}

print_failing_pods() {
  local pods

  pods="$(run_kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | awk '
    {
      split($2, ready, "/");
      if (ready[1] != ready[2] || ($3 != "Running" && $3 != "Completed")) {
        print $1;
      }
    }
  ')"

  if [[ -z "$pods" ]]; then
    echo "No failing pods detected."
    return
  fi

  for pod in $pods; do
    section "Describe pod: $pod"
    best_effort run_kubectl -n "$NAMESPACE" describe pod "$pod"
    section "Logs: $pod"
    best_effort run_kubectl -n "$NAMESPACE" logs "$pod" --tail=120
    section "Previous logs: $pod"
    best_effort run_kubectl -n "$NAMESPACE" logs "$pod" --previous --tail=120
  done
}

if [[ "$MODE" == "minikube" ]]; then
  require_cmd minikube
else
  require_cmd kubectl
fi

section "Cluster access"
if [[ "$MODE" == "minikube" ]]; then
  best_effort minikube -p "$MINIKUBE_PROFILE" status
else
  best_effort kubectl config current-context
fi

section "Nodes"
run_kubectl get nodes -o wide

if ! run_kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  section "Namespace"
  echo "Namespace '$NAMESPACE' not found."
  exit 1
fi

section "Namespace"
run_kubectl get namespace "$NAMESPACE"

section "Pods"
run_kubectl -n "$NAMESPACE" get pods -o wide

section "Deployments"
best_effort run_kubectl -n "$NAMESPACE" get deployments -o wide

section "StatefulSets"
best_effort run_kubectl -n "$NAMESPACE" get statefulsets -o wide

section "Services"
best_effort run_kubectl -n "$NAMESPACE" get services -o wide

section "Ingress"
best_effort run_kubectl -n "$NAMESPACE" get ingress -o wide

section "PersistentVolumeClaims"
best_effort run_kubectl -n "$NAMESPACE" get pvc

section "Recent events"
best_effort run_kubectl -n "$NAMESPACE" get events --sort-by=.metadata.creationTimestamp

if [[ -n "$HELM_RELEASE" ]] && command -v helm >/dev/null 2>&1; then
  section "Helm releases"
  best_effort helm list -n "$HELM_NAMESPACE"
  section "Helm status: $HELM_RELEASE"
  best_effort helm status "$HELM_RELEASE" -n "$HELM_NAMESPACE"
fi

if [[ "$SHOW_MINIKUBE_URL" == "true" ]]; then
  section "Minikube service URL"
  best_effort minikube -p "$MINIKUBE_PROFILE" service "$SERVICE_NAME" -n "$NAMESPACE" --url
fi

section "Failing pods"
print_failing_pods
