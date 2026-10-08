#!/usr/bin/env bash
set -euo pipefail

# Script: run-all-tests.sh
# Purpose: Master automated test suite runner for OpenObserve Standalone, K8s Monitoring (Prometheus Metrics & OTel Container Logs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "############################################################"
echo " Starting OpenObserve Standalone Automated Test Suite "
echo "############################################################"

echo ""
echo ">>> STEP 1: Verify Kubernetes & HTTP Service Health (with Retention)"
"${SCRIPT_DIR}/verify-health.sh"

echo ""
echo ">>> STEP 2: Verify OpenTelemetry Container Logs Ingestion Pipeline"
"${SCRIPT_DIR}/test-logs.sh"

echo ""
echo ">>> STEP 3: Verify Prometheus Kubernetes Metrics Ingestion Pipeline"
"${SCRIPT_DIR}/test-metrics.sh"

echo ""
echo ">>> STEP 4: Verify Declarative Kubernetes Dashboards"
"${SCRIPT_DIR}/test-dashboards.sh"

echo ""
echo ">>> STEP 5: Verify Pod Resilience & Storage Persistence"
"${SCRIPT_DIR}/test-resilience.sh"

echo ""
echo "############################################################"
echo " ALL TESTS PASSED SUCCESSFULLY! "
echo " OpenObserve Standalone, Metrics & Container Logs are ready."
echo "############################################################"
