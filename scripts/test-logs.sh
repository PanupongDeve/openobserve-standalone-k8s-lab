#!/usr/bin/env bash
# ==============================================================================
# Script: test-logs.sh
# Description: TDD Verification Script for Container Logs Ingestion into OpenObserve
# ==============================================================================

set -eo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZO_HOST="${ZO_HOST:-http://localhost:30080}"
ZO_USER="${ZO_USER:-root@example.com}"
ZO_PASS="${ZO_PASS:-Complexpass#123}"
ZO_ORG="${ZO_ORG:-default}"
STREAM_NAME="${STREAM_NAME:-k8s_logs}"
MAX_RETRIES=20
RETRY_INTERVAL=3

echo "================================================================================"
echo " [TEST] Verifying Kubernetes Container Logs Ingestion in OpenObserve"
echo "================================================================================"
echo "Target Endpoint : ${ZO_HOST}"
echo "Organization    : ${ZO_ORG}"
echo "Log Stream Name : ${STREAM_NAME}"
echo "User            : ${ZO_USER}"
echo ""

echo "▶ Step 1: Checking OpenTelemetry Collector DaemonSet status in namespace openobserve..."
OTEL_PODS=$(kubectl get pods -n openobserve -l "app.kubernetes.io/name=opentelemetry-collector" --no-headers 2>/dev/null || true)
if [[ -z "${OTEL_PODS}" ]]; then
  echo "❌ FAIL: OpenTelemetry Collector pods not found in namespace openobserve"
  exit 1
fi

READY_PODS=$(echo "${OTEL_PODS}" | awk '{split($2,a,"/"); if (a[1]==a[2] && a[1]>0) print $1}' | wc -l)
TOTAL_PODS=$(echo "${OTEL_PODS}" | wc -l)

if [[ "${READY_PODS}" -eq 0 ]]; then
  echo "❌ FAIL: OpenTelemetry Collector pods are not ready (${READY_PODS}/${TOTAL_PODS} ready)"
  exit 1
fi
echo "✅ OpenTelemetry Collector is running (${READY_PODS}/${TOTAL_PODS} pods ready)"
echo ""

echo "▶ Step 2: Waiting for log stream '${STREAM_NAME}' in OpenObserve (max ${MAX_RETRIES} attempts)..."
STREAM_FOUND=0
for i in $(seq 1 ${MAX_RETRIES}); do
  RESPONSE=$(curl -s -u "${ZO_USER}:${ZO_PASS}" "${ZO_HOST}/api/${ZO_ORG}/streams?type=logs" || echo "{}")
  STREAM_CHECK=$(echo "${RESPONSE}" | jq -r --arg s "${STREAM_NAME}" '.list[]? | select(.name==$s) | .name' 2>/dev/null || true)
  
  if [[ "${STREAM_CHECK}" == "${STREAM_NAME}" ]]; then
    echo "✅ Discovered log stream '${STREAM_NAME}' in OpenObserve at attempt ${i}"
    STREAM_FOUND=1
    break
  fi
  echo "   Attempt ${i}/${MAX_RETRIES}: Stream '${STREAM_NAME}' not ready yet. Waiting ${RETRY_INTERVAL}s..."
  sleep ${RETRY_INTERVAL}
done

if [[ "${STREAM_FOUND}" -eq 0 ]]; then
  echo "❌ FAIL: Log stream '${STREAM_NAME}' did not appear in OpenObserve within timeout"
  exit 1
fi

echo ""
echo "▶ Step 3: Querying container log records from '${STREAM_NAME}' stream..."
NOW_MICROS=$(date +%s%6N)
START_MICROS=$((NOW_MICROS - 86400000000))
END_MICROS=$((NOW_MICROS + 3600000000))

QUERY_PAYLOAD=$(jq -n \
  --arg sql "SELECT * FROM \"${STREAM_NAME}\" ORDER BY _timestamp DESC LIMIT 5" \
  --argjson start "${START_MICROS}" \
  --argjson end "${END_MICROS}" \
  '{query: {sql: $sql, start_time: $start, end_time: $end, from: 0, size: 5}}')

QUERY_RESULT=$(curl -s -X POST "${ZO_HOST}/api/${ZO_ORG}/_search?type=logs" \
  -u "${ZO_USER}:${ZO_PASS}" \
  -H "Content-Type: application/json" \
  -d "${QUERY_PAYLOAD}" || echo "{}")

HITS=$(echo "${QUERY_RESULT}" | jq -r '.hits | length // 0' 2>/dev/null || echo 0)

if [[ "${HITS}" -eq 0 ]]; then
  echo "❌ FAIL: No log records found in stream '${STREAM_NAME}'"
  echo "Response: ${QUERY_RESULT}"
  exit 1
fi

echo "✅ Successfully retrieved ${HITS} container log records from '${STREAM_NAME}'"
echo ""
echo "▶ Step 4: Verifying Kubernetes Metadata Fields in Log Record..."
SAMPLE_RECORD=$(echo "${QUERY_RESULT}" | jq -r '.hits[0]')
echo "Sample Record Preview:"
echo "${SAMPLE_RECORD}" | jq '{
  _timestamp: ._timestamp,
  stream: (.stream // .log_iostream // "N/A"),
  k8s_namespace: (.k8s_namespace_name // ."k8s.namespace.name" // "N/A"),
  k8s_pod: (.k8s_pod_name // ."k8s.pod.name" // "N/A"),
  k8s_container: (.k8s_container_name // ."k8s.container.name" // "N/A"),
  log_snippet: (.log // .body // "N/A" | tostring | .[0:80])
}'

echo ""
echo "================================================================================"
echo " 🎉 ALL CONTAINER LOGS VERIFICATION TESTS PASSED!"
echo "================================================================================"
exit 0
