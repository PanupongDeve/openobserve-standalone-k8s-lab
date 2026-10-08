# Implementation Plan: OpenObserve Standalone, Kubernetes Monitoring (Metrics) & Container Logs Collection (OTel Collector)

## Overview
แผนการติดตั้งและทดสอบ OpenObserve ในโหมด Standalone บน Kubernetes Cluster ร่วมกับ MinIO (Subchart) เพื่อใช้เป็น Object Storage Backend สำหรับจัดเก็บไฟล์ Parquet และใช้ PersistentVolumeClaim (PVC) ผ่าน `local-path` สำหรับเก็บ SQLite metadata, WAL และ Disk Cache พร้อมทั้งเปิด Service แบบ `NodePort` สำหรับเข้าถึง Web UI ขยายขอบเขตสู่ระบบ Observability ครบวงจรด้วย **kube-prometheus-stack (Prometheus Agent Mode)** สำหรับสแครป Kubernetes Metrics, **OpenTelemetry Collector (DaemonSet)** สำหรับเก็บ Container Logs เข้า Stream `k8s_logs`, การกำหนด **Data Retention Policy 1 วัน**, และจัดเตรียมชุด Declarative PromQL Dashboards บน OpenObserve

## Architecture Decisions
- **Standalone All-in-One Pod (`ZO_NODE_ROLE: all`)**: เหมาะสำหรับ Lab และเวิร์กโหลดขนาดเล็ก รวมบทบาท Ingester, Querier, และ Compactor ไว้ใน Pod เดียว
- **Hybrid Storage Model**: แยก SQLite สำหรับ Metadata/Index ชั่วคราวบน Local Disk (PVC) และส่งข้อมูล Log/Metric แบบ Parquet ไปเก็บถาวรบน MinIO ช่วยป้องกันข้อมูลสูญหายเมื่อ Pod รีสตาร์ท
- **Data Retention & Compactor Policy**: กำหนด `ZO_DATA_RETENTION_DAYS: "1"` (24 ชั่วโมง) และ `ZO_COMPACTOR_INTERVAL: "300s"` (5 นาที) เพื่อกวาดล้างข้อมูลหมดอายุออกจาก MinIO สม่ำเสมอ ไม่เปลือง Disk
- **Prometheus Agent Mode for Metrics**: ใช้ `kube-prometheus-stack` ในโหมด Agent Mode เพื่อดึง Node, Pod, Container Metrics ส่งตรงเข้า OpenObserve ผ่าน Prometheus Remote Write (`/api/default/prometheus/api/v1/write`) โดยไม่ต้องเปิด TSDB Storage ขนาดใหญ่
- **OpenTelemetry Collector DaemonSet for Logs**: ใช้ Helm Chart `open-telemetry/opentelemetry-collector` (Contrib) อ่านไฟล์ `/var/log/pods/*/*/*.log`, สกัด Kubernetes Metadata (`k8sattributes`) และส่งเข้า OpenObserve OTLP HTTP Endpoint เข้าสู่ Stream `k8s_logs`
- **Declarative & Automated PromQL Dashboards**: จัดเก็บ Dashboard เป็น JSON Templates ใน repository พร้อมสคริปต์ Provisioning ผ่าน REST API เพื่อให้สามารถควบคุม Version Control และนำเข้าซ้ำได้อัตโนมัติ
- **Automated Verification & TDD Workflow**: มีชุดสคริปต์ทดสอบอัตโนมัติสำหรับตรวจสอบ Health Check (พร้อมตรวจ Retention Env), Container Logs Ingestion, Prometheus Metrics Ingestion, Dashboards Validation, และ Pod Restart Resilience

---

## Task List

### Phase 1: Configuration & Test Harness Setup (RED Phase)
- [x] **Task 1**: ปรับปรุง [`helm/openobserve-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/openobserve-values.yaml) (Retention 1 วัน + Compactor 300s) และจัดทำ [`helm/otel-collector-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/otel-collector-values.yaml) สำหรับ Container Logs
- [x] **Task 2**: สร้างสคริปต์ทดสอบ Log Ingestion ([`scripts/test-logs.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-logs.sh)) และอัปเดต [`scripts/verify-health.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/verify-health.sh) เพื่อยืนยัน RED State

#### Checkpoint: Foundation & RED Tests Ready
- [x] Render Helm Templates ผ่านทั้ง 3 ชุด (`openobserve`, `kps`, `otel-collector`)
- [x] สคริปต์ Deploy/Cleanup/Test พร้อมรันและผ่าน Syntax Check

### Phase 2: Deployment & Log Ingestion Pipeline (GREEN Phase)
- [x] **Task 3**: ปรับปรุงสคริปต์ [`scripts/deploy.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/deploy.sh) และ [`scripts/cleanup.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/cleanup.sh) ให้รองรับ OpenTelemetry Collector
- [x] **Task 4**: ติดตั้ง/อัปเกรด OpenObserve, kube-prometheus-stack และ OTel Collector พร้อมรันการทดสอบสู่สถานะ GREEN

#### Checkpoint: Metrics & Logs Pipelines Active
- [x] Pods ทุกตัว (`openobserve`, `minio`, `kps-prometheus`, `node-exporter`, `kube-state-metrics`, `otel-collector`) รันในสถานะ `Running`
- [x] Prometheus Remote Write สตรีม Metrics เข้า OpenObserve ต่อเนื่อง
- [x] OTel Collector สตรีม Container Logs เข้า Stream `k8s_logs` สำเร็จ
- [x] สคริปต์ `test-logs.sh` และ `test-metrics.sh` ผ่าน (PASS)

### Phase 3: E2E Integration, Resilience & Documentation
- [x] **Task 5**: ทดสอบความคงทนของข้อมูลและ Storage Persistence หลัง Restart Pod ([`scripts/test-resilience.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/test-resilience.sh))
- [x] **Task 6**: รวม Test Suite เข้า [`scripts/run-all-tests.sh`](file:///home/panupong/github/openobserve-standalone-k8s-lab/scripts/run-all-tests.sh), อัปเดตคู่มือ [`README.md`](file:///home/panupong/github/openobserve-standalone-k8s-lab/README.md) และลบโฟลเดอร์ Legacy `otel/`

#### Checkpoint: Project Complete & Fully Verified
- [x] ทุก Test Case ผ่านการทดสอบ 100% ทั้ง Health/Retention, Logs, Metrics, Dashboards และ Resilience
- [x] Documentation และ Codebase สะอาด เป็นไปตามสเปกล่าสุด

---

## Risks and Mitigations

| ความเสี่ยง (Risk) | ผลกระทบ (Impact) | แนวทางป้องกันและแก้ไข (Mitigation) |
|---|---|---|
| พื้นที่ MinIO เต็มเร็วใน Lab Cluster | High | กำหนด `ZO_DATA_RETENTION_DAYS: "1"` ควบคู่กับ `ZO_COMPACTOR_INTERVAL: "300s"` ให้กวาดล้างข้อมูลเก่าสม่ำเสมอ |
| Resource Pod สูงเกินลิมิตจนถูก OOMKilled | Medium | กำหนด `resources.requests` และ `resources.limits` ใน values.yaml สำหรับทุก Component อย่างเหมาะสม |
| OTel Collector เกิด Log Loop จาก Log ของตัวเอง | High | ใส่ `exclude: [/var/log/pods/openobserve_otel-collector*/*/*.log]` ใน config ของ `filelog` receiver |
| OTel Collector ดึง Kubelet/Pod Metadata ไม่สำเร็จ | High | กำหนด ClusterRole ให้ครอบคลุม `pods`, `namespaces`, `nodes`, `replicasets` และผูก ServiceAccount ให้ถูกต้อง |
| Dashboard JSON ไม่เข้ากันของ Schema | Medium | ใช้วิธีทดสอบ Schema และ Provision ผ่าน REST API พร้อมทำ Verification Test Script ตรวจสอบการสร้างสำเร็จ |
