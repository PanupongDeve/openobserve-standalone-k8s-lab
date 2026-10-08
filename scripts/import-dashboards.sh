#!/usr/bin/env bash
# ==============================================================================
# Script: import-dashboards.sh
# Description: Auto-provision Declarative Kubernetes Dashboards into OpenObserve
# ==============================================================================

set -eo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZO_HOST="${ZO_HOST:-http://localhost:30080}"
ZO_USER="${ZO_USER:-root@example.com}"
ZO_PASS="${ZO_PASS:-Complexpass#123}"
ZO_ORG="${ZO_ORG:-default}"
DASHBOARDS_DIR="${BASE_DIR}/dashboards"

echo "================================================================================"
echo " [PROVISION] Importing Kubernetes Dashboards into OpenObserve"
echo "================================================================================"
echo "Target Endpoint  : ${ZO_HOST}"
echo "Organization     : ${ZO_ORG}"
echo "Dashboards Dir   : ${DASHBOARDS_DIR}"
echo ""

if [[ ! -d "${DASHBOARDS_DIR}" ]]; then
  echo "❌ FAIL: Directory ${DASHBOARDS_DIR} not found!"
  exit 1
fi

IMPORTED_COUNT=0

for file in "${DASHBOARDS_DIR}"/*.json; do
  [[ -f "${file}" ]] || continue
  
  while IFS= read -r dash_json; do
    [[ -z "${dash_json}" ]] && continue
    
    TITLE=$(echo "${dash_json}" | jq -r '.title // "Untitled"')
    DASH_ID=$(echo "${dash_json}" | jq -r '.dashboardId // "unknown"')
    
    echo "▶ Importing Dashboard: '${TITLE}' (ID: ${DASH_ID})..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${ZO_HOST}/api/${ZO_ORG}/dashboards" \
      -u "${ZO_USER}:${ZO_PASS}" \
      -H "Content-Type: application/json" \
      -d "${dash_json}")
    
    HTTP_STATUS=$(echo "${RESPONSE}" | tail -n1)
    BODY=$(echo "${RESPONSE}" | sed '$d')
    
    if [[ "${HTTP_STATUS}" -eq 200 || "${HTTP_STATUS}" -eq 201 ]]; then
      echo "  ✅ Successfully imported: ${TITLE} (HTTP ${HTTP_STATUS})"
      IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
    else
      echo "  ❌ Failed to import: ${TITLE} (HTTP ${HTTP_STATUS})"
      echo "     Response: ${BODY}"
      exit 1
    fi
  done < <(jq -c 'if type=="array" then .[] else . end' "${file}")
done

echo ""
echo "================================================================================"
echo " 🎉 Successfully imported ${IMPORTED_COUNT} dashboard(s) into OpenObserve!"
echo "================================================================================"
exit 0
