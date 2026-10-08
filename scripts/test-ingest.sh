#!/usr/bin/env bash
set -euo pipefail

# Script: test-ingest.sh
# Purpose: Test OpenObserve Log Ingestion API and verify data queryability

NODE_PORT="30080"
BASE_URL="http://127.0.0.1:${NODE_PORT}"
AUTH_USER="root@example.com"
AUTH_PASS="Complexpass#123"
STREAM_NAME="lab_test_stream"
CURRENT_SEC=$(date +%s)
CURRENT_US=$((${CURRENT_SEC} * 1000000))
START_TIME=$((${CURRENT_US} - 3600000000))
END_TIME=$((${CURRENT_US} + 3600000000))
TEST_ID="test-ingest-${CURRENT_SEC}"

echo "=== [1/2] Sending JSON logs to stream '${STREAM_NAME}' ==="
INGEST_PAYLOAD=$(cat <<EOF
[
  {
    "_timestamp": ${CURRENT_US},
    "service": "k8s-lab-tester",
    "level": "INFO",
    "test_id": "${TEST_ID}",
    "message": "Automated log ingestion verification test",
    "environment": "k8s-local-lab"
  },
  {
    "_timestamp": ${CURRENT_US},
    "service": "k8s-lab-tester",
    "level": "WARN",
    "test_id": "${TEST_ID}",
    "message": "Simulated warning log event",
    "environment": "k8s-local-lab"
  }
]
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/default/${STREAM_NAME}/_json" \
  -u "${AUTH_USER}:${AUTH_PASS}" \
  -H "Content-Type: application/json" \
  -d "${INGEST_PAYLOAD}")

HTTP_BODY=$(echo "${RESPONSE}" | sed '$d')
HTTP_STATUS=$(echo "${RESPONSE}" | tail -n1)

echo "Ingest Response HTTP Status: ${HTTP_STATUS}"
echo "Ingest Response Body: ${HTTP_BODY}"

if [ "${HTTP_STATUS}" != "200" ]; then
  echo "ERROR: Ingestion failed with status ${HTTP_STATUS}"
  exit 1
fi

echo "Ingestion succeeded."

echo "=== [2/2] Querying ingested log from stream '${STREAM_NAME}' ==="
sleep 2

SEARCH_PAYLOAD=$(cat <<EOF
{
  "query": {
    "sql": "SELECT * FROM ${STREAM_NAME} WHERE test_id='${TEST_ID}'",
    "start_time": ${START_TIME},
    "end_time": ${END_TIME},
    "from": 0,
    "size": 10
  }
}
EOF
)

SEARCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/default/_search" \
  -u "${AUTH_USER}:${AUTH_PASS}" \
  -H "Content-Type: application/json" \
  -d "${SEARCH_PAYLOAD}")

SEARCH_BODY=$(echo "${SEARCH_RESPONSE}" | sed '$d')
SEARCH_STATUS=$(echo "${SEARCH_RESPONSE}" | tail -n1)

echo "Search Response HTTP Status: ${SEARCH_STATUS}"
echo "Search Response Body: ${SEARCH_BODY}"

if [ "${SEARCH_STATUS}" != "200" ]; then
  echo "ERROR: Search query failed with status ${SEARCH_STATUS}"
  exit 1
fi

if echo "${SEARCH_BODY}" | grep -q "${TEST_ID}"; then
  echo "SUCCESS: Found ingested records for test_id='${TEST_ID}'."
else
  echo "ERROR: Ingested record with test_id='${TEST_ID}' was not returned in search results!"
  exit 1
fi

echo "=================================================="
echo " Log Ingestion & Search Verification: PASSED "
echo " Stream: ${STREAM_NAME}"
echo " Test ID: ${TEST_ID}"
echo "=================================================="
