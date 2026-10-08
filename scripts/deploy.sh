#!/usr/bin/env bash
set -euo pipefail

# Script: deploy.sh
# Purpose: Deploy or upgrade OpenObserve Standalone, kube-prometheus-stack (Agent Mode), OpenTelemetry Collector (Logs), and Dashboards

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OO_VALUES_FILE="${ROOT_DIR}/helm/openobserve-values.yaml"
KPS_VALUES_FILE="${ROOT_DIR}/helm/kps-values.yaml"
OTEL_VALUES_FILE="${ROOT_DIR}/helm/otel-collector-values.yaml"
NAMESPACE="openobserve"
OO_RELEASE="openobserve"
KPS_RELEASE="kps"
OTEL_RELEASE="otel-collector"
OO_CHART="openobserve/openobserve-standalone"
KPS_CHART="prometheus-community/kube-prometheus-stack"
OTEL_CHART="open-telemetry/opentelemetry-collector"

echo "=== [1/6] Adding and updating Helm repositories ==="
helm repo add openobserve https://charts.openobserve.ai --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
helm repo update

echo "=== [2/6] Creating Namespace and Secret for OpenObserve Auth ==="
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic openobserve-auth \
  --from-literal=ZO_ROOT_USER_EMAIL="root@example.com" \
  --from-literal=ZO_ROOT_USER_PASSWORD="Complexpass#123" \
  -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "=== [3/6] Deploying/Upgrading OpenObserve Release '${OO_RELEASE}' (Retention: 1 Day) ==="
helm upgrade --install "${OO_RELEASE}" "${OO_CHART}" \
  --namespace "${NAMESPACE}" \
  -f "${OO_VALUES_FILE}"

echo "=== [4/6] Deploying/Upgrading kube-prometheus-stack (Agent Mode Metrics) ==="
helm upgrade --install "${KPS_RELEASE}" "${KPS_CHART}" \
  --namespace "${NAMESPACE}" \
  -f "${KPS_VALUES_FILE}"

echo "=== [5/6] Deploying/Upgrading OpenTelemetry Collector (Container Logs DaemonSet) ==="
helm upgrade --install "${OTEL_RELEASE}" "${OTEL_CHART}" \
  --namespace "${NAMESPACE}" \
  -f "${OTEL_VALUES_FILE}"

echo "Waiting for OpenObserve, Prometheus stack, and OTel Collector pods to become ready..."
kubectl rollout status statefulset -n "${NAMESPACE}" --timeout=180s || true
kubectl rollout status deployment -n "${NAMESPACE}" --timeout=180s || true
kubectl rollout status daemonset -n "${NAMESPACE}" --timeout=180s || true

echo "=== [6/6] Auto-provisioning Kubernetes Dashboards ==="
"${SCRIPT_DIR}/import-dashboards.sh"

echo "================================================================================"
echo " 🎉 OpenObserve Standalone, kube-prometheus-stack & OTel Collector Deployed!"
echo "================================================================================"
