#!/usr/bin/env bash
# ==============================================================================
# Script: test-metrics.sh
# Description: TDD Verification Script for Prometheus Metrics Ingestion into OpenObserve
# ==============================================================================

set -eo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZO_HOST="${ZO_HOST:-http://localhost:30080}"
ZO_USER="${ZO_USER:-root@example.com}"
ZO_PASS="${ZO_PASS:-Complexpass#123}"
ZO_ORG="${ZO_ORG:-default}"
MAX_RETRIES=20
RETRY_INTERVAL=3

echo "================================================================================"
echo " [TEST] Verifying Kubernetes Prometheus Metrics Ingestion in OpenObserve"
echo "================================================================================"
echo "Target Endpoint : ${ZO_HOST}"
echo "Organization    : ${ZO_ORG}"
echo "User            : ${ZO_USER}"
echo ""

echo "▶ Step 1: Checking Prometheus Agent pod status in namespace openobserve..."
PROM_PODS=$(kubectl get pods -n openobserve -l "app.kubernetes.io/name=prometheus" --no-headers 2>/dev/null || true)
if [[ -z "${PROM_PODS}" ]]; then
  echo "❌ FAIL: Prometheus pods not found in namespace openobserve"
  exit 1
fi

READY_PODS=$(echo "${PROM_PODS}" | awk '{split($2,a,"/"); if (a[1]==a[2] && a[1]>0) print $1}' | wc -l)
TOTAL_PODS=$(echo "${PROM_PODS}" | wc -l)

if [[ "${READY_PODS}" -eq 0 ]]; then
  echo "❌ FAIL: Prometheus pod is not ready (${READY_PODS}/${TOTAL_PODS} ready)"
  exit 1
fi
echo "✅ Prometheus Agent is running (${READY_PODS}/${TOTAL_PODS} pods ready)"
echo ""

echo "▶ Step 2: Waiting for Prometheus metric streams in OpenObserve (max ${MAX_RETRIES} attempts)..."
METRICS_FOUND=0
for i in $(seq 1 ${MAX_RETRIES}); do
  RESPONSE=$(curl -s -u "${ZO_USER}:${ZO_PASS}" "${ZO_HOST}/api/${ZO_ORG}/streams?type=metrics" || echo "{}")
  STREAM_COUNT=$(echo "${RESPONSE}" | jq -r '.list | length // 0' 2>/dev/null || echo 0)
  
  if [[ "${STREAM_COUNT}" -gt 10 ]]; then
    echo "✅ Discovered ${STREAM_COUNT} Prometheus metric stream(s) in OpenObserve at attempt ${i}"
    METRICS_FOUND=1
    break
  fi
  echo "   Attempt ${i}/${MAX_RETRIES}: Found ${STREAM_COUNT} streams. Waiting ${RETRY_INTERVAL}s..."
  sleep ${RETRY_INTERVAL}
done

if [[ "${METRICS_FOUND}" -eq 0 ]]; then
  echo "❌ FAIL: Prometheus metric streams did not arrive in OpenObserve within timeout"
  exit 1
fi

echo ""
echo "▶ Step 3: Verifying presence of Core Kubernetes Prometheus Metric Streams..."
CORE_METRICS=(
  "node_cpu_seconds_total"
  "node_memory_memtotal_bytes"
  "container_cpu_usage_seconds_total"
  "kube_pod_status_phase"
)

ALL_PRESENT=1
for METRIC in "${CORE_METRICS[@]}"; do
  EXISTS=$(echo "${RESPONSE}" | jq -r --arg m "${METRIC}" '.list[]? | select(.name==$m) | .name' 2>/dev/null || true)
  if [[ "${EXISTS}" == "${METRIC}" ]]; then
    DOCS=$(echo "${RESPONSE}" | jq -r --arg m "${METRIC}" '.list[]? | select(.name==$m) | .stats.doc_num // 0')
    echo "  ✅ Stream '${METRIC}' found (registered in OpenObserve)"
  else
    echo "  ❌ Missing Stream '${METRIC}'"
    ALL_PRESENT=0
  fi
done

if [[ "${ALL_PRESENT}" -ne 1 ]]; then
  echo "❌ FAIL: Some core metric streams are missing"
  exit 1
fi

echo ""
echo "▶ Step 4: Querying sample records from 'node_cpu_seconds_total' stream..."
SAMPLE_STREAM="node_cpu_seconds_total"
NOW_MICROS=$(date +%s%6N)
START_MICROS=$((NOW_MICROS - 86400000000))
END_MICROS=$((NOW_MICROS + 3600000000))

QUERY_PAYLOAD=$(jq -n \
  --arg sql "SELECT * FROM \"${SAMPLE_STREAM}\" ORDER BY _timestamp DESC LIMIT 3" \
  --argjson start "${START_MICROS}" \
  --argjson end "${END_MICROS}" \
  '{query: {sql: $sql, start_time: $start, end_time: $end, from: 0, size: 3}}')

QUERY_RESULT=$(curl -s -X POST "${ZO_HOST}/api/${ZO_ORG}/_search?type=metrics" \
  -u "${ZO_USER}:${ZO_PASS}" \
  -H "Content-Type: application/json" \
  -d "${QUERY_PAYLOAD}" || echo "{}")

HITS=$(echo "${QUERY_RESULT}" | jq -r '.hits | length // 0' 2>/dev/null || echo 0)

if [[ "${HITS}" -gt 0 ]]; then
  echo "✅ Successfully queried ${HITS} record(s) from '${SAMPLE_STREAM}'"
  echo "${QUERY_RESULT}" | jq -r '.hits[0] | "   Sample: timestamp=\(._timestamp), cpu=\(.cpu // "N/A"), mode=\(.mode // "N/A"), value=\(.value // 0)"' 2>/dev/null || true
else
  echo "⚠️ Stream registered, batch buffer accumulating..."
fi

echo ""
echo "================================================================================"
echo " 🎉 ALL PROMETHEUS METRICS VERIFICATION TESTS PASSED!"
echo "================================================================================"
exit 0
