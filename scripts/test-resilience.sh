#!/usr/bin/env bash
set -euo pipefail

# Script: test-resilience.sh
# Purpose: Verify data persistence across OpenObserve Pod restart/deletion

NAMESPACE="openobserve"
NODE_PORT="30080"
BASE_URL="http://127.0.0.1:${NODE_PORT}"
AUTH_USER="root@example.com"
AUTH_PASS="Complexpass#123"

echo "================================================================================"
echo " [TEST] Verifying OpenObserve Pod Restart Resilience & Storage Persistence"
echo "================================================================================"

echo "▶ Step 1: Querying existing Container Logs & Metrics count before restart..."
NOW_MICROS=$(date +%s%6N)
START_MICROS=$((NOW_MICROS - 86400000000))
END_MICROS=$((NOW_MICROS + 3600000000))

LOGS_QUERY=$(jq -n \
  --arg sql "SELECT COUNT(*) as cnt FROM \"k8s_logs\"" \
  --argjson start "${START_MICROS}" \
  --argjson end "${END_MICROS}" \
  '{query: {sql: $sql, start_time: $start, end_time: $end}}')

LOGS_RES=$(curl -s -X POST "${BASE_URL}/api/default/_search?type=logs" \
  -u "${AUTH_USER}:${AUTH_PASS}" \
  -H "Content-Type: application/json" \
  -d "${LOGS_QUERY}" || echo "{}")

BEFORE_LOG_COUNT=$(echo "${LOGS_RES}" | jq -r '.hits[0].cnt // 0' 2>/dev/null || echo 0)
echo "✅ Current log count in 'k8s_logs' stream: ${BEFORE_LOG_COUNT} records"

echo ""
echo "▶ Step 2: Simulating OpenObserve Pod termination (Restart)..."
OO_POD=$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/name=openobserve-standalone -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod '${OO_POD}'..."
kubectl delete pod "${OO_POD}" -n "${NAMESPACE}" --wait=true

echo ""
echo "▶ Step 3: Waiting for replacement pod to be Ready..."
kubectl wait --namespace "${NAMESPACE}" \
  --for=condition=ready pod \
  -l app.kubernetes.io/name=openobserve-standalone \
  --timeout=180s

echo "Waiting for HTTP endpoint to be responsive..."
MAX_RETRIES=25
RETRY_COUNT=0
HTTP_CODE=""

while [ "${RETRY_COUNT}" -lt "${MAX_RETRIES}" ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/web/index.html" || true)
  if [ "${HTTP_CODE}" = "200" ]; then
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 3
done

if [ "${HTTP_CODE}" != "200" ]; then
  echo "❌ ERROR: OpenObserve did not recover within timeout (HTTP ${HTTP_CODE})"
  exit 1
fi
echo "✅ OpenObserve replacement pod is healthy and responsive."

echo ""
echo "▶ Step 4: Verifying Data and Dashboard Persistence after recovery..."
# Verify Dashboards survived restart
DASH_RES=$(curl -s -u "${AUTH_USER}:${AUTH_PASS}" "${BASE_URL}/api/default/dashboards" || echo "{}")
DASH_COUNT=$(echo "${DASH_RES}" | jq -r '.dashboards | length // 0' 2>/dev/null || echo 0)

if [ "${DASH_COUNT}" -eq 0 ]; then
  echo "❌ ERROR: Dashboards were lost after pod restart!"
  exit 1
fi
echo "✅ Dashboards persisted successfully: ${DASH_COUNT} dashboards found"

# Verify Log Data survived restart
FOUND_LOGS=0
for i in $(seq 1 15); do
  NOW_MICROS=$(date +%s%6N)
  START_MICROS=$((NOW_MICROS - 86400000000))
  END_MICROS=$((NOW_MICROS + 3600000000))

  VERIFY_QUERY=$(jq -n \
    --arg sql "SELECT COUNT(*) as cnt FROM \"k8s_logs\"" \
    --argjson start "${START_MICROS}" \
    --argjson end "${END_MICROS}" \
    '{query: {sql: $sql, start_time: $start, end_time: $end}}')

  AFTER_LOGS_RES=$(curl -s -X POST "${BASE_URL}/api/default/_search?type=logs" \
    -u "${AUTH_USER}:${AUTH_PASS}" \
    -H "Content-Type: application/json" \
    -d "${VERIFY_QUERY}" || echo "{}")

  AFTER_LOG_COUNT=$(echo "${AFTER_LOGS_RES}" | jq -r '.hits[0].cnt // 0' 2>/dev/null || echo 0)
  if [ "${AFTER_LOG_COUNT}" -gt 0 ]; then
    echo "✅ Historical container logs persisted successfully: ${AFTER_LOG_COUNT} records available in 'k8s_logs'"
    FOUND_LOGS=1
    break
  fi
  echo "Waiting for storage index sync (Attempt ${i}/15)..."
  sleep 3
done

if [ "${FOUND_LOGS}" -ne 1 ]; then
  echo "❌ ERROR: Historical logs were not recovered!"
  exit 1
fi

echo ""
echo "================================================================================"
echo " 🎉 ALL RESILIENCE & STORAGE PERSISTENCE TESTS PASSED!"
echo "================================================================================"
exit 0
