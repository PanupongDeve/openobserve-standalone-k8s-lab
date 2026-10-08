# Task List: OpenObserve Standalone, Kubernetes Monitoring (Metrics) & Container Logs Collection (OTel Collector)

รายการงานและขั้นตอนการติดตั้ง ปรับแต่ง Data Retention, ติดตั้ง OpenTelemetry Collector สำหรับเก็บ Container Logs, ทดสอบ และตรวจสอบความพร้อมใช้งานของระบบตามข้อกำหนดในเอกสาร [`specs/0-open-observe-standalone-setup.md`](file:///home/panupong/github/openobserve-standalone-k8s-lab/specs/0-open-observe-standalone-setup.md)

---

## Phase 1: Configuration & Test Harness Setup (TDD RED Phase)

### Task 1: อัปเดต OpenObserve Values (Retention 1 วัน) และสร้าง OpenTelemetry Collector Values
**Description:** 
1. ปรับปรุง [`helm/openobserve-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/openobserve-values.yaml) โดยเพิ่มคอนฟิก `ZO_DATA_RETENTION_DAYS: "1"` และ `ZO_COMPACTOR_INTERVAL: "300s"`
2. สร้างไฟล์ [`helm/otel-collector-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/otel-collector-values.yaml) สำหรับติดตั้ง Chart `open-telemetry/opentelemetry-collector` ในโหมด DaemonSet เพื่ออ่าน Container Logs จาก `/var/log/pods/*/*/*.log`, สกัด K8s Metadata (`k8sattributes`), exclude log ตัวเอง และส่ง OTLP HTTP เข้า OpenObserve Stream `k8s_logs`

**Acceptance criteria:**
- [x] ไฟล์ [`helm/openobserve-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/openobserve-values.yaml) มี `ZO_DATA_RETENTION_DAYS: "1"` และ `ZO_COMPACTOR_INTERVAL: "300s"` ในส่วน `config`
- [x] มีไฟล์ [`helm/otel-collector-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/otel-collector-values.yaml) ที่ตั้งค่า:
  - `mode: daemonset`
  - `image.repository: otel/opentelemetry-collector-contrib`
  - `receivers.filelog` รองรับ CRI-O / Containerd regex parser และจับคู่ namespace/pod/container
  - `processors.k8sattributes` ดึง pod, namespace, node, container metadata
  - `processors.resource` ใส่ `stream_name: k8s_logs`
  - `exporters.otlphttp/openobserve` ชี้ไปที่ `http://openobserve-openobserve-standalone.openobserve.svc.cluster.local:5080/api/default` พร้อม Basic Auth
  - mount volume `/var/log/pods` และ `/var/lib/docker/containers` แบบ readOnly
- [x] ทดสอบ Render Template ของทั้ง 2 Charts ผ่านฉลุยไม่มีข้อผิดพลาด

**Verification:**
- [x] ตรวจสอบ Template Rendering:
  ```bash
  helm template openobserve openobserve/openobserve-standalone -f helm/openobserve-values.yaml --namespace openobserve > /dev/null
  helm template otel-collector open-telemetry/opentelemetry-collector -f helm/otel-collector-values.yaml --namespace openobserve > /dev/null
  ```

**Dependencies:** None  
**Files likely touched:**
- `helm/openobserve-values.yaml`
- `helm/otel-collector-values.yaml`

**Estimated scope:** Small (2 files)

---

### Task 2: สร้างสคริปต์ทดสอบ Log Ingestion (`scripts/test-logs.sh`) และอัปเดต `scripts/verify-health.sh` (RED)
**Description:** 
1. สร้างสคริปต์ [`scripts/test-logs.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-logs.sh) เพื่อ Query OpenObserve Search API ตรวจสอบว่ามี Container Logs ไหลเข้า Stream `k8s_logs` และมี Metadata (`k8s_namespace_name`, `k8s_pod_name`, `k8s_container_name`)
2. อัปเดต [`scripts/verify-health.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/verify-health.sh) ให้ตรวจเช็ค DaemonSet `otel-collector` และตรวจสอบค่า Environment Variable ด้าน Data Retention บน OpenObserve Pod

**Acceptance criteria:**
- [x] มีสคริปต์ [`scripts/test-logs.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-logs.sh) ที่สามารถ query search logs และ assert ความถูกต้องของฟิลด์
- [x] สคริปต์ [`scripts/verify-health.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/verify-health.sh) ตรวจสอบสถานะ Pods ของ `otel-collector` และค่า `ZO_DATA_RETENTION_DAYS`
- [x] รัน `./scripts/test-logs.sh` ก่อนติดตั้ง OTel Collector แล้วต้องล้มเหลวอย่างถูกต้อง (RED state)
- [x] สคริปต์ทั้งหมดผ่านการตรวจ Syntax (`bash -n scripts/*.sh`)

**Verification:**
- [x] ตรวจสอบ Syntax:
  ```bash
  bash -n scripts/test-logs.sh scripts/verify-health.sh
  ```
- [x] รัน `./scripts/test-logs.sh` และยืนยัน RED state (Exit Code != 0)

**Dependencies:** Task 1  
**Files likely touched:**
- `scripts/test-logs.sh`
- `scripts/verify-health.sh`

**Estimated scope:** Small (2 files)

---

## Phase 2: Deployment & Log Ingestion Pipeline (TDD GREEN Phase)

### Task 3: ปรับปรุงสคริปต์ Deploy และ Cleanup ให้รองรับ OpenTelemetry Collector
**Description:** 
1. ปรับปรุง [`scripts/deploy.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/deploy.sh) ให้เพิ่ม repo `open-telemetry`, ติดตั้ง Helm release `otel-collector` และรอ Pods พร้อมทำงาน
2. ปรับปรุง [`scripts/cleanup.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/cleanup.sh) ให้ถอนการติดตั้ง Release `otel-collector` ด้วย

**Acceptance criteria:**
- [x] [`scripts/deploy.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/deploy.sh) มีขั้นตอนติดตั้ง `otel-collector` ผ่าน Helm พร้อม rollout wait
- [x] [`scripts/cleanup.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/cleanup.sh) ลบ Release `otel-collector` สะอาดหมดจด
- [x] สคริปต์ผ่าน Syntax check

**Verification:**
- [x] ตรวจสอบ Syntax:
  ```bash
  bash -n scripts/deploy.sh scripts/cleanup.sh
  ```

**Dependencies:** Task 1, Task 2  
**Files likely touched:**
- `scripts/deploy.sh`
- `scripts/cleanup.sh`

**Estimated scope:** Small (2 files)

---

### Task 4: ติดตั้ง/อัปเกรด OpenObserve, Deploy OTel Collector และทดสอบ Log Ingestion (GREEN)
**Description:** ดำเนินการ Deploy OpenObserve (อัปเดต Retention), kube-prometheus-stack และ OTel Collector จากนั้นรัน `scripts/test-logs.sh` และ `scripts/test-metrics.sh` เพื่อยืนยันว่าข้อมูล Logs และ Metrics ไหลเข้าสู่ระบบอย่างถูกต้อง (เข้าสู่ GREEN state)

**Acceptance criteria:**
- [x] Pod `otel-collector` รันในสถานะ `Running` บนทุก Node
- [x] Pod `openobserve` มี Environment `ZO_DATA_RETENTION_DAYS=1` และ `ZO_COMPACTOR_INTERVAL=300s`
- [x] Stream `k8s_logs` ปรากฏใน OpenObserve
- [x] สคริปต์ [`scripts/test-logs.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-logs.sh) ทำงานผ่าน (Exit Code 0 - PASS)
- [x] สคริปต์ [`scripts/test-metrics.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-metrics.sh) และ [`scripts/test-dashboards.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-dashboards.sh) ทำงานผ่าน

**Verification:**
- [x] รันสคริปต์ทดสอบ:
  ```bash
  ./scripts/verify-health.sh
  ./scripts/test-logs.sh
  ./scripts/test-metrics.sh
  ./scripts/test-dashboards.sh
  ```

**Dependencies:** Task 3  
**Files likely touched:**
- ไม่มี (Execution & Verification)

**Estimated scope:** Small (Deployment & Verification)

---

## Phase 3: E2E Integration, Resilience & Documentation

### Task 5: ทดสอบ Data Persistence, Compaction & Pod Restart Resilience
**Description:** ตรวจสอบว่าไฟล์ Parquet ของทั้ง Metrics และ Logs ถูก Sync ลง MinIO Bucket อย่างต่อเนื่อง และทดสอบ Restart OpenObserve Pod เพื่อยืนยันว่าข้อมูลเดิม Dashboards และ Retention settings ยังอยู่ครบถ้วน

**Acceptance criteria:**
- [x] ตรวจพบไฟล์ Parquet ใน MinIO Bucket สำหรับ stream `prometheus` และ `k8s_logs`
- [x] รันสคริปต์ [`scripts/test-resilience.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-resilience.sh) สั่ง Restart Pod แล้วข้อมูลและ Dashboards ยังคงอยู่ครบ 100%

**Verification:**
- [x] รันสคริปต์ทดสอบ Resilience:
  ```bash
  ./scripts/test-resilience.sh
  ```

**Dependencies:** Task 4  
**Files likely touched:**
- `scripts/test-resilience.sh`

**Estimated scope:** Small (1 file)

---

### Task 6: รวม Test Suite เข้า `scripts/run-all-tests.sh`, อัปเดต `README.md` และลบ Legacy Files
**Description:** 
1. รวมการรัน `test-logs.sh` และการตรวจ Retention เข้าใน [`scripts/run-all-tests.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/run-all-tests.sh)
2. อัปเดตเอกสารคู่มือ [`README.md`](file:///home/panupong/github/openobserve-standalone-k8s-lab/README.md) ให้ครอบคลุมสถาปัตยกรรม Logs (OTel Collector) และ Data Retention (1 วัน)
3. ลบโฟลเดอร์ที่ไม่ใช้งาน `otel/` ออกจาก Codebase

**Acceptance criteria:**
- [x] สคริปต์ [`scripts/run-all-tests.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/run-all-tests.sh) รันทุกชุดทดสอบ (Health/Retention, Metrics Ingestion, Log Ingestion, Dashboards, Resilience) ผ่านครบ 100% (ALL TESTS PASSED)
- [x] ไฟล์ [`README.md`](file:///home/panupong/github/openobserve-standalone-k8s-lab/README.md) สะท้อนสถาปัตยกรรมครบวงจร (Metrics + Logs + Retention)
- [x] โฟลเดอร์ `otel/` ถูกลบออกอย่างเรียบร้อย

**Verification:**
- [x] รัน End-to-End Test Suite:
  ```bash
  ./scripts/run-all-tests.sh
  ```
- [x] ตรวจสอบว่าไม่มี Broken Links หรือไฟล์ตกค้าง

**Dependencies:** Task 1 - Task 5  
**Files likely touched:**
- `scripts/run-all-tests.sh`
- `README.md`

**Estimated scope:** Medium (2 files + cleanup)

---

## Checkpoint: Project Complete & Verified
- [x] OpenObserve Standalone, kube-prometheus-stack และ OTel Collector รันร่วมกันสมบูรณ์
- [x] Prometheus Remote Write สตรีม Metrics เข้า OpenObserve
- [x] OTel Collector สตรีม Container Logs เข้า OpenObserve Stream `k8s_logs`
- [x] Data Retention Policy 1 วันทำงานร่วมกับ Compactor อย่างมีประสิทธิภาพ
- [x] Kubernetes PromQL Dashboards แสดงผลกราฟได้ถูกต้อง
- [x] รัน `./scripts/run-all-tests.sh` ผ่านครบ 100%
