# OpenObserve Standalone on Kubernetes Lab & Infrastructure Monitoring

ชุดติดตั้งและสภาพแวดล้อมทดสอบ **OpenObserve** ในโหมด Standalone บน Kubernetes พร้อมระบบ Observability ครบวงจร ทั้งการเก็บ **Metrics** ด้วย **kube-prometheus-stack (Prometheus Agent Mode)**, การเก็บ **Container Logs** ด้วย **OpenTelemetry Collector DaemonSet (Helm Chart)**, การตั้งค่า **Data Retention Policy (Default 1 วัน)**, และ **Declarative PromQL Dashboards** พร้อมชุดสคริปต์อัตโนมัติสำหรับการ Deploy, Health Check, Metrics Ingestion, Log Ingestion, Dashboards Validation, และ Resilience Verification

---

## 1. ภาพรวมสถาปัตยกรรม (Architecture Overview)

ระบบออกแบบตามสถาปัตยกรรม Observability ครบวงจรสำหรับ Lab และ Small Workload:

- **All-in-One Standalone Pod (`ZO_NODE_ROLE: all`)**: รวมบทบาท Ingester, Querier และ Compactor ไว้ใน Pod เดียว ควบคุมผ่าน StatefulSet
- **Persistent Storage (PVC 10Gi)**: ผูกกับ `local-path` StorageClass เพื่อเก็บ SQLite Metadata, Write-Ahead Log (WAL) และ Disk Cache
- **Object Storage Backend (MinIO 20Gi)**: จัดเก็บข้อมูล Logs, Metrics ในรูปแบบไฟล์ Parquet แบบถาวร ป้องกันข้อมูลสูญหายเมื่อ Pod รีสตาร์ท
- **Data Retention & Compaction**: กำหนดนโยบายเก็บรักษาข้อมูลเริ่มต้น 1 วัน (`ZO_DATA_RETENTION_DAYS: 1`) พร้อมรอบการทำงานของ Compactor ทุก 5 นาที (`ZO_COMPACTOR_INTERVAL: 300s`) เพื่อกวาดล้างข้อมูลเก่าและป้องกันพื้นที่ Disk เต็ม
- **Kubernetes Metrics Ingestion**: ใช้ **kube-prometheus-stack** ในโหมด **Prometheus Agent Mode** สแครป Node, Pod, Container Metrics และส่งตรงเข้า OpenObserve ผ่าน **Prometheus Remote Write** (`/api/default/prometheus/api/v1/write`)
- **Kubernetes Container Logs Ingestion**: ใช้ **OpenTelemetry Collector (Contrib DaemonSet)** อ่านไฟล์ `/var/log/pods/*/*/*.log`, สกัด Kubernetes Metadata (`namespace`, `pod`, `container`, `node`), และส่งเข้า OpenObserve ผ่าน **OTLP HTTP** เข้าสู่ Stream `k8s_logs`
- **Declarative PromQL Dashboards**: จัดเตรียม Dashboard Templates (`dashboards/`) สำหรับ Cluster Overview และ Workload Metrics พร้อมสคริปต์ Auto-provision ผ่าน REST API
- **Service Exposure**: เปิดพอร์ต Web UI และ Ingestion API ผ่าน NodePort `30080` (HTTP) และ `30081` (gRPC)

```
+---------------------------------------------------------------------------------------------+
|                                      Kubernetes Cluster                                     |
|                                                                                             |
|  [node-exporter]  [kubelet / cAdvisor]  [kube-state-metrics]        [/var/log/pods/*/*/*.log] |
|         │                  │                     │                              │           |
|         └──────────────────┼─────────────────────┘                              ▼           |
|                            ▼ (Scrape)                          [OTel Collector DaemonSet]   |
|              [Prometheus (Agent Mode)]                          (filelog + k8sattributes)  |
|                            │                                                    │           |
|                            ▼ (Remote Write: /prometheus/...)                    ▼ (OTLP HTTP)
|           +─────────────────────────────────────────────────────────────────────+           |
|           |                    OpenObserve Standalone (Pod)                     |           |
|           |         [Ingestion Engine / PromQL & Log Search Query Engine]       |           |
|           |         [Compactor: Retention 1 Day / Interval 300s]                |           |
|           +──────────────────┬───────────────────────────────┬──────────────────+           |
|                              │ (Parquet - Metrics & Logs)    │ (Metadata)                   |
|                              ▼                               ▼                              |
|                       [MinIO S3 Bucket]                 [SQLite PVC]                        |
+---------------------------------------------------------------------------------------------+
```

---

## 2. โครงสร้างโปรเจกต์ (Project Structure)

```text
.
├── dashboards/
│   ├── k8s-cluster-overview.json   # Declarative Dashboard สำหรับ Cluster & Node Overview (PromQL)
│   └── k8s-workload-metrics.json   # Declarative Dashboard สำหรับ Workload & Pod Metrics (PromQL)
├── helm/
│   ├── openobserve-values.yaml     # คอนฟิก Helm สำหรับ OpenObserve Standalone, MinIO และ Retention (1 วัน)
│   ├── kps-values.yaml             # คอนฟิก Helm สำหรับ kube-prometheus-stack (Agent Mode + Remote Write)
│   └── otel-collector-values.yaml  # คอนฟิก Helm สำหรับ OpenTelemetry Collector (DaemonSet + Container Logs)
├── scripts/
│   ├── deploy.sh                   # สคริปต์ติดตั้ง/อัปเกรด OpenObserve, KPS, OTel Collector และ Dashboards
│   ├── verify-health.sh            # สคริปต์ตรวจสอบสถานะ Pods, PVCs, Web UI และ Retention Configuration
│   ├── test-metrics.sh             # สคริปต์ตรวจสอบการไหลเข้าของ Prometheus Metrics Streams (PromQL)
│   ├── test-logs.sh                # สคริปต์ตรวจสอบ Container Log Ingestion และ Metadata ใน Stream k8s_logs
│   ├── test-dashboards.sh          # สคริปต์ตรวจสอบความพร้อมของ Dashboards ใน OpenObserve REST API
│   ├── test-resilience.sh          # สคริปต์ทดสอบความทนทาน ลบ Pod และยืนยันข้อมูล Logs/Metrics ไม่สูญหาย
│   ├── import-dashboards.sh        # สคริปต์ Auto-provision Dashboards เข้าสู่ OpenObserve REST API
│   ├── run-all-tests.sh            # Master Runner สำหรับรัน Test Suite ทั้งหมดอัตโนมัติ (E2E)
│   └── cleanup.sh                  # สคริปต์ถอนการติดตั้ง (รองรับโหมดปกติ และ --purge)
├── specs/
│   ├── 0-open-observe-standalone-setup.md # ข้อกำหนดทางเทคนิค (Specification)
│   └── 1-workshop-setup.md         # Workshop Lab Specification
├── tasks/
│   └── 0-open-observe-standalone-setup/  # Task breakdown (todo.md) และ Implementation Plan (plan.md)
└── README.md                       # คู่มือการใช้งานฉบับนี้
```

---

## 3. ข้อมูลการเข้าใช้งาน (Credentials & Access)

| รายการ | ค่าเริ่มต้น (Default Value) |
|---|---|
| **Web UI Endpoint** | `http://<NODE_IP>:30080` หรือ `http://127.0.0.1:30080` |
| **Root Username** | `root@example.com` |
| **Root Password** | `Complexpass#123` |
| **Data Retention** | `1 วัน (24 ชั่วโมง)` สำหรับทุก Stream |
| **Compactor Cycle** | ทุก `300 วินาที (5 นาที)` |
| **Log Stream** | `k8s_logs` (Container Logs จากทุก Pods ในคลัสเตอร์) |
| **MinIO Console** | `http://10.43.85.185:9001` (ClusterIP / Port-forward) |
| **MinIO Credentials** | `minioadmin` / `minioadminpassword` |
| **Target Namespace** | `openobserve` |

---

## 4. วิธีการติดตั้งและเริ่มต้นใช้งาน (Quickstart)

### 4.1 ติดตั้งระบบทั้งหมด (OpenObserve + KPS + OTel Collector + Dashboards)
รันสคริปต์ deploy เพื่อสร้าง namespace, ติดตั้ง Helm releases, รัน OTel Collector DaemonSet และ import dashboards:

```bash
./scripts/deploy.sh
```

### 4.2 ตรวจสอบสถานะระบบ
รันสคริปต์เพื่อเช็กสถานะ Pods, Storage (PVC), Retention Configuration และ HTTP Readiness:

```bash
./scripts/verify-health.sh
```

### 4.3 เข้าใช้งาน Web UI
เปิดเบราว์เซอร์แล้วไปที่ `http://localhost:30080` ล็อกอินด้วย:
- Email: `root@example.com`
- Password: `Complexpass#123`

- **เมนู Logs:** ค้นหา Container Logs ของทุก Container ใน Stream `k8s_logs` กรองตาม `k8s_namespace_name`, `k8s_pod_name`, `k8s_container_name`
- **เมนู Dashboards:** แสดงกราฟสถานะระบบ Kubernetes ด้วย PromQL:
  - **Kubernetes / Compute Resources / Cluster**
  - **Kubernetes / Compute Resources / Namespace (Workloads)**
  - **Kubernetes / Compute Resources / Namespace (Pods)**
  - **Kubernetes / API server**

---

## 5. การทดสอบระบบอัตโนมัติ (Automated Testing & TDD)

สามารถรันการทดสอบครบทุกขั้นตอนแบบ End-to-End Suite:

```bash
./scripts/run-all-tests.sh
```

### รายละเอียดการทดสอบแต่ละสคริปต์:
1. **Health Verification** (`./scripts/verify-health.sh`): ตรวจสอบ Pods ทุกตัวอยู่ในสถานะ Ready, PVC ทั้งหมดอยู่ในสถานะ Bound, Retention Env ถูกตั้งค่าเป็น 1 วัน และหน้า Web UI ตอบกลับ HTTP 200
2. **Container Logs Verification** (`./scripts/test-logs.sh`): ตรวจสอบว่า OTel Collector ส่ง Container Logs เข้าสู่ Stream `k8s_logs` และสกัดฟิลด์ Metadata ของ Kubernetes ได้ครบถ้วน
3. **Metrics Stream Ingestion** (`./scripts/test-metrics.sh`): ตรวจสอบว่า `kube-prometheus-stack` (Agent Mode) ส่ง Core Metrics (`node_cpu_seconds_total`, `node_memory_memtotal_bytes`, `container_cpu_usage_seconds_total`, `kube_pod_status_phase`) เข้าสู่ OpenObserve ผ่าน Prometheus Remote Write
4. **Dashboards Validation** (`./scripts/test-dashboards.sh`): ตรวจสอบว่า Dashboards ทั้งหมดถูกสร้างและมีโครงสร้าง PromQL สมบูรณ์บน OpenObserve API
5. **Resilience & Storage Sync** (`./scripts/test-resilience.sh`): สั่งลบ Pod ของ OpenObserve เพื่อจำลองกรณี Pod แครช และตรวจสอบว่าหลัง Pod ตัวใหม่ขึ้นมา ข้อมูล Logs, Metrics และ Dashboards ยังคงอยู่ครบถ้วนจาก SQLite และ MinIO

---

## 6. การลบและคลีนอัปสภาพแวดล้อม (Cleanup)

### ถอนการติดตั้งเฉพาะ Helm Releases (คงข้อมูลใน PVC ไว้)
```bash
./scripts/cleanup.sh
```

### ถอนการติดตั้งทั้งหมดแบบสมบูรณ์ (ลบ Helm Releases, PVC และ Namespace)
```bash
./scripts/cleanup.sh --purge
```
