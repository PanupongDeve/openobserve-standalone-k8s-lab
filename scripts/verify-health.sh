#!/usr/bin/env bash
set -euo pipefail

# Script: verify-health.sh
# Purpose: Verify health of OpenObserve pods, PVCs, services, and HTTP UI endpoint

NAMESPACE="openobserve"
NODE_PORT="30080"
ENDPOINT_URL="http://127.0.0.1:${NODE_PORT}"

echo "=== [1/4] Checking Pod status in namespace '${NAMESPACE}' ==="
kubectl get pods -n "${NAMESPACE}" -o wide

echo "Waiting for all Pods to be Ready..."
kubectl wait --namespace "${NAMESPACE}" \
  --for=condition=ready pod \
  --all \
  --timeout=180s

echo "=== [2/4] Checking PVC status in namespace '${NAMESPACE}' ==="
kubectl get pvc -n "${NAMESPACE}"

# Check for unbound PVCs
UNBOUND_PVCS=$(kubectl get pvc -n "${NAMESPACE}" --no-headers | awk '$2 != "Bound" {print $1}')
if [ -n "${UNBOUND_PVCS}" ]; then
  echo "ERROR: The following PVCs are not Bound: ${UNBOUND_PVCS}"
  exit 1
fi
echo "All PVCs are successfully Bound."

echo "=== [3/4] Checking Services in namespace '${NAMESPACE}' ==="
kubectl get svc -n "${NAMESPACE}"

echo "=== [4/5] Verifying OpenObserve Data Retention Configuration ==="
OO_POD=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=openobserve-standalone" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${OO_POD}" ]; then
  RETENTION_ENV=$(kubectl get pod "${OO_POD}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].env[?(@.name=="ZO_DATA_RETENTION_DAYS")].value}' 2>/dev/null || true)
  COMPACTOR_ENV=$(kubectl get pod "${OO_POD}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].env[?(@.name=="ZO_COMPACTOR_INTERVAL")].value}' 2>/dev/null || true)
  echo "OpenObserve Retention Settings in Pod '${OO_POD}':"
  echo "  - ZO_DATA_RETENTION_DAYS: ${RETENTION_ENV:-not set}"
  echo "  - ZO_COMPACTOR_INTERVAL:  ${COMPACTOR_ENV:-not set}"
fi

echo "=== [5/5] Verifying HTTP Web UI Endpoint (${ENDPOINT_URL}) ==="
MAX_RETRIES=15
RETRY_COUNT=0
HTTP_CODE=""

while [ "${RETRY_COUNT}" -lt "${MAX_RETRIES}" ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ENDPOINT_URL}/web/index.html" || true)
  if [ "${HTTP_CODE}" = "200" ]; then
    echo "HTTP Web UI check succeeded (HTTP 200 OK)."
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Waiting for Web UI (current status: '${HTTP_CODE}')... retry ${RETRY_COUNT}/${MAX_RETRIES}"
  sleep 4
done

if [ "${HTTP_CODE}" != "200" ]; then
  echo "ERROR: Web UI endpoint returned HTTP ${HTTP_CODE} instead of 200."
  exit 1
fi

echo "=================================================="
echo " OpenObserve Health Check: ALL CHECKS PASSED "
echo " Access UI: ${ENDPOINT_URL}"
echo " Default User: root@example.com / Complexpass#123"
echo "=================================================="
