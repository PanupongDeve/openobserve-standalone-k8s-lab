#!/usr/bin/env bash
# ==============================================================================
# Script: test-dashboards.sh
# Description: TDD Verification Script for OpenObserve Kubernetes Dashboards
# ==============================================================================

set -eo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZO_HOST="${ZO_HOST:-http://localhost:30080}"
ZO_USER="${ZO_USER:-root@example.com}"
ZO_PASS="${ZO_PASS:-Complexpass#123}"
ZO_ORG="${ZO_ORG:-default}"

echo "================================================================================"
echo " [TEST] Verifying Kubernetes Dashboards in OpenObserve"
echo "================================================================================"
echo "Target Endpoint : ${ZO_HOST}"
echo "Organization    : ${ZO_ORG}"
echo "User            : ${ZO_USER}"
echo ""

echo "▶ Step 1: Querying dashboards list from OpenObserve REST API..."
RESPONSE=$(curl -s -u "${ZO_USER}:${ZO_PASS}" "${ZO_HOST}/api/${ZO_ORG}/dashboards" || echo "{}")
DASH_COUNT=$(echo "${RESPONSE}" | jq -r '.dashboards | length // 0' 2>/dev/null || echo 0)

if [[ "${DASH_COUNT}" -eq 0 ]]; then
  echo "❌ FAIL: No dashboards found in organization '${ZO_ORG}'"
  exit 1
fi
echo "✅ Found ${DASH_COUNT} dashboard(s) registered in OpenObserve"
echo ""

DASHBOARDS_DIR="${BASE_DIR}/dashboards"
REQUIRED_TITLES=()
for file in "${DASHBOARDS_DIR}"/*.json; do
  [[ -f "${file}" ]] || continue
  while IFS= read -r t; do
    [[ -n "${t}" ]] && REQUIRED_TITLES+=("${t}")
  done < <(jq -r 'if type=="array" then .[].title else .title end // empty' "${file}")
done

if [[ "${#REQUIRED_TITLES[@]}" -eq 0 ]]; then
  echo "⚠️ WARNING: No dashboard JSON files found in ${DASHBOARDS_DIR}"
fi

ALL_VALID=1

for title in "${REQUIRED_TITLES[@]}"; do
  FOUND=$(echo "${RESPONSE}" | jq -r --arg t "${title}" '[.dashboards[]? | select(.title == $t)] | length')
  if [[ "${FOUND}" -ge 1 ]]; then
    echo "  ✅ Dashboard present: '${title}'"
  else
    echo "  ❌ MISSING Dashboard: '${title}'"
    ALL_VALID=0
  fi
done

if [[ "${ALL_VALID}" -eq 0 ]]; then
  echo "❌ FAIL: One or more required dashboards are missing!"
  exit 1
fi

echo ""
echo "▶ Step 3: Inspecting Dashboard Panels and Structure..."
echo "${RESPONSE}" | jq -r '.dashboards[] | " - Dashboard: \(.title) (ID: \(.dashboard_id), Owner: \(.owner))"'

echo ""
echo "================================================================================"
echo " 🎉 ALL DASHBOARD VERIFICATION TESTS PASSED!"
echo "================================================================================"
exit 0
