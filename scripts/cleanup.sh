#!/usr/bin/env bash
set -euo pipefail

# Script: cleanup.sh
# Purpose: Uninstall OpenObserve, kube-prometheus-stack, and OpenTelemetry Collector Releases, and cleanup resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE="openobserve"
OO_RELEASE="openobserve"
KPS_RELEASE="kps"
OTEL_RELEASE="otel-collector"
PURGE=false

for arg in "$@"; do
  case $arg in
    --purge|--all)
      PURGE=true
      shift
      ;;
  esac
done

echo "=== [1/4] Uninstalling Helm release '${OTEL_RELEASE}' in namespace '${NAMESPACE}' ==="
if helm status "${OTEL_RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  helm uninstall "${OTEL_RELEASE}" -n "${NAMESPACE}"
  echo "Helm release '${OTEL_RELEASE}' uninstalled."
else
  echo "Helm release '${OTEL_RELEASE}' not found or already uninstalled."
fi

echo "=== [2/4] Uninstalling Helm release '${KPS_RELEASE}' in namespace '${NAMESPACE}' ==="
if helm status "${KPS_RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  helm uninstall "${KPS_RELEASE}" -n "${NAMESPACE}"
  echo "Helm release '${KPS_RELEASE}' uninstalled."
else
  echo "Helm release '${KPS_RELEASE}' not found or already uninstalled."
fi

echo "=== [3/4] Uninstalling Helm release '${OO_RELEASE}' in namespace '${NAMESPACE}' ==="
if helm status "${OO_RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  helm uninstall "${OO_RELEASE}" -n "${NAMESPACE}"
  echo "Helm release '${OO_RELEASE}' uninstalled."
else
  echo "Helm release '${OO_RELEASE}' not found or already uninstalled."
fi

echo "Waiting for pods in '${NAMESPACE}' to terminate..."
kubectl wait --namespace "${NAMESPACE}" \
  --for=delete pod \
  --all \
  --timeout=120s 2>/dev/null || true

if [ "${PURGE}" = true ]; then
  echo "=== [4/4] Purging PVCs, Secrets and Namespace '${NAMESPACE}' (--purge mode) ==="
  echo "Deleting all PVCs in '${NAMESPACE}'..."
  kubectl delete pvc --all -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true

  echo "Deleting namespace '${NAMESPACE}'..."
  kubectl delete namespace "${NAMESPACE}" --timeout=60s 2>/dev/null || true

  echo "Waiting for namespace deletion..."
  kubectl wait --for=delete namespace/"${NAMESPACE}" --timeout=120s 2>/dev/null || true
  echo "Purge complete: All resources, PVCs, and namespace removed."
else
  echo "=== [4/4] Preserving PVCs and Namespace (Default mode) ==="
  echo "PVCs and namespace '${NAMESPACE}' are preserved. Use '--purge' to remove all data."
fi

echo "Cleanup completed successfully."
