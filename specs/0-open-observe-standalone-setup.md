# Spec: OpenObserve Standalone Installation via Helm, Kubernetes Infrastructure Monitoring with kube-prometheus-stack & Container Logs Collection with OpenTelemetry Collector

เอกสารข้อกำหนดทางเทคนิค (Specification) สำหรับการติดตั้ง OpenObserve แบบ Standalone บน Kubernetes พร้อมระบบ Observability ครบวงจร ทั้งการเก็บ **Metrics** ด้วย **kube-prometheus-stack (Prometheus Agent Mode)**, การเก็บ **Container Logs** ด้วย **OpenTelemetry Collector DaemonSet (Helm Chart)**, การควบคุม **Data Retention Policy (Default 1 วัน)** และการจัดเตรียม Kubernetes Dashboards บน OpenObserve ด้วย PromQL

---

## 1. Objective (วัตถุประสงค์และภาพรวมสถาปัตยกรรม)

ติดตั้งและตั้งค่าระบบ Observability ด้วย **OpenObserve Standalone** บน Kubernetes สำหรับสภาพแวดล้อม Lab / Small Workload พร้อมระบบมอนิเตอร์โครงสร้างพื้นฐาน Kubernetes (Cluster, Nodes, Workloads) ครบทั้งมิติ Metrics, Logs และการบริหารพื้นที่จัดเก็บข้อมูล:

1. **OpenObserve Core Platform & Retention Policy:** รวมบทบาท Ingester, Querier และ Compactor ไว้ใน Single Pod บน Helm Chart `openobserve/openobserve-standalone` โดยเก็บไฟล์ Parquet ขึ้น MinIO (Object Storage), บันทึก Metadata บน SQLite Persistent Volume และกำหนดนโยบาย **Data Retention Policy เริ่มต้น 1 วัน (`ZO_DATA_RETENTION_DAYS: 1`)** พร้อมรอบการทำงานของ Compactor ทุก 5 นาที (`ZO_COMPACTOR_INTERVAL: 300s`) เพื่อกวาดล้างข้อมูลหมดอายุ ป้องกัน Disk เต็มใน Lab
2. **Kubernetes Metrics Collection:** ใช้ **kube-prometheus-stack** ในโหมด **Prometheus Agent Mode** เพื่อดึง Metrics จากระดับ Node (`node-exporter`), Pod/Container (`kubelet / cAdvisor`) และสถานะ K8s Objects (`kube-state-metrics`) แล้วส่งตรงเข้า OpenObserve ผ่าน **Prometheus Remote Write** (`/api/default/prometheus/api/v1/write`)
3. **Container Logs Collection:** ใช้ **OpenTelemetry Collector (Contrib)** ในโหมด **DaemonSet** ติดตั้งผ่าน Helm Chart `open-telemetry/opentelemetry-collector` เพื่ออ่าน Container Logs จาก `/var/log/pods/*/*/*.log`, สกัด Kubernetes Metadata (`namespace`, `pod`, `container`, `node`) และส่งเข้า OpenObserve ผ่าน **OTLP HTTP Exporter** (`/api/default`) จัดระเบียบเข้าสู่ Stream `k8s_logs`
4. **Declarative Kubernetes Dashboards & Log Exploration:** จัดเตรียม Dashboard JSON templates สำหรับแสดงผล Cluster Overview, Workload Metrics พร้อมรองรับการค้นหาและวิเคราะห์ Logs ผ่าน OpenObserve UI และ Search API

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

## 2. Tech Stack & Components

| Component | Technology / Detail | Version / Chart | Role |
|---|---|---|---|
| **Core Platform** | OpenObserve Standalone | v1.0.1+ (Chart: `openobserve/openobserve-standalone`) | Ingestion, PromQL Engine, Log Search, Compaction (Retention 1 วัน) & Web UI |
| **Object Storage Backend** | MinIO Subchart (`minio.enabled=true`) | Built-in Helm Subchart | จัดเก็บ Parquet Files (Metrics และ Logs) |
| **Metadata Store** | SQLite on Persistent Disk | `local-path` StorageClass | บันทึก Stream Metadata, Users, Dashboards, Retention Settings |
| **Exposure Service** | Service Type `NodePort` (Port 5080) | Port: 5080, NodePort: 30080 | ทางเข้า Web UI, REST Ingestion Endpoint และ OTLP Endpoint |
| **K8s Metrics Collection** | `kube-prometheus-stack` | Chart: `prometheus-community/kube-prometheus-stack` | รัน Prometheus Agent Mode สแครป Node, Pod, Container Metrics |
| **Node Metrics** | `prometheus-node-exporter` | Subchart ใน `kube-prometheus-stack` | เก็บ Host CPU, Memory, Disk, Network จากทุก Node |
| **Cluster State Metrics** | `kube-state-metrics` | Subchart ใน `kube-prometheus-stack` | เก็บสถานะ Pod Phases, Deployments, Container Restarts |
| **Container Metrics** | `kubelet / cAdvisor` | Built-in Kubelet Scrape Jobs | เก็บ Container CPU, Working Set Memory, Throttling |
| **Container Logs Collection** | `opentelemetry-collector` | Chart: `open-telemetry/opentelemetry-collector` | รัน DaemonSet อ่าน `/var/log/pods`, สกัด K8s Metadata และส่ง OTLP เข้า OpenObserve |
| **Dashboard Management** | OpenObserve Dashboards API / UI | JSON Templates (`dashboards/*.json`) | Visualizations สำหรับ Node, Cluster, Workload ด้วย PromQL |

---

## 3. Configuration & Values Architecture

คอมโพเนนต์ทั้งหมดติดตั้งอยู่ภายใน Namespace เดียวกัน (`openobserve`) เพื่อให้เข้าถึง Service และ Secret ได้โดยตรง

### 3.1 การตั้งค่า OpenObserve Standalone ([`helm/openobserve-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/openobserve-values.yaml))

```yaml
# 1. การกำหนดความจุ Disk สำหรับ SQLite และ WAL
persistence:
  enabled: true
  storageClass: "local-path"
  size: 10Gi
  accessModes:
    - ReadWriteOnce

# 2. ข้อมูลการยืนยันตัวตน (Root User)
auth:
  ZO_ROOT_USER_EMAIL: "root@example.com"
  ZO_ROOT_USER_PASSWORD: "Complexpass#123"

# 3. การคอนฟิกโหมด Standalone, Storage Engine และ Data Retention Policy
config:
  ZO_NODE_ROLE: "all"
  ZO_LOCAL_MODE: "true"
  ZO_LOCAL_MODE_STORAGE: "s3"
  ZO_META_STORE: "sqlite"
  ZO_HTTP_PORT: "5080"
  # กำหนดระยะเวลาเก็บรักษาข้อมูลเริ่มต้น 1 วัน (24 ชั่วโมง) สำหรับทุก Stream
  ZO_DATA_RETENTION_DAYS: "1"
  # กำหนดรอบการทำงานของ Compactor ให้กวาดล้างข้อมูลเก่าทุก 5 นาที (300 วินาที)
  ZO_COMPACTOR_INTERVAL: "300s"

# 4. Service Exposure ผ่าน NodePort
service:
  type: NodePort
  port: 5080
  nodePort: 30080

# 5. เปิดใช้งาน MinIO Subchart เป็น Object Storage
minio:
  enabled: true
  mode: standalone
  replicas: 1
  persistence:
    enabled: true
    storageClass: "local-path"
    size: 20Gi
```

### 3.2 การตั้งค่า kube-prometheus-stack ([`helm/kps-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/kps-values.yaml))

```yaml
# ปิด Grafana และ Alertmanager เพื่อใช้ OpenObserve เป็น Single Pane of Glass
grafana:
  enabled: false

alertmanager:
  enabled: false

# คอนฟิก Prometheus Instance
prometheus:
  prometheusSpec:
    # เปิด Agent Mode เพื่อลดการใช้ Resource ไม่เก็บ TSDB ลง Pod Disk
    agentMode: true

    # ชี้ Prometheus Remote Write เข้า OpenObserve
    remoteWrite:
      - url: "http://openobserve-openobserve-standalone.openobserve.svc.cluster.local:5080/api/default/prometheus/api/v1/write"
        basicAuth:
          username:
            name: openobserve-auth
            key: ZO_ROOT_USER_EMAIL
          password:
            name: openobserve-auth
            key: ZO_ROOT_USER_PASSWORD

    # กำหนด Resource Limits เพื่อความปลอดภัยใน Cluster
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# เปิดใช้งาน Subcharts ที่จำเป็นสำหรับ K8s Metrics
nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
```

### 3.3 การตั้งค่า OpenTelemetry Collector สำหรับ Logs ([`helm/otel-collector-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/otel-collector-values.yaml))

```yaml
# รันในโหมด DaemonSet บนทุก Node
mode: daemonset

# ใช้ Contrib Image เพื่อให้มี filelog receiver และ k8sattributes processor
image:
  repository: otel/opentelemetry-collector-contrib

# คอนฟิก Pipeline สำหรับ Container Logs
config:
  receivers:
    filelog:
      include:
        - /var/log/pods/*/*/*.log
      exclude:
        # ตัด log ของ collector เองเพื่อป้องกัน log loop
        - /var/log/pods/openobserve_openobserve-otel-collector*/*/*.log
      start_at: end
      include_file_path: true
      include_file_name: false
      operators:
        # 1. Parse CRI-O / Containerd log format: "<timestamp> <stream> <tag> <log>"
        - type: regex_parser
          regex: '^(?P<time>[^ ]+) (?P<stream>stdout|stderr) (?P<logtag>[^ ]*) (?P<log>.*)$'
          timestamp:
            parse_from: attributes.time
            layout: '%Y-%m-%dT%H:%M:%S.%L%z'
          severity:
            parse_from: attributes.stream
            mapping:
              error: stderr
              info: stdout
        # 2. Extract Pod/Container info จาก Path: /var/log/pods/<namespace>_<pod>_<uid>/<container>/<run>.log
        - type: regex_parser
          parse_from: attributes["log.file.path"]
          regex: '^/var/log/pods/(?P<k8s_namespace_name>[^_]+)_(?P<k8s_pod_name>[^_]+)_(?P<k8s_pod_uid>[^/]+)/(?P<k8s_container_name>[^/]+)/.*$'

  processors:
    memory_limiter:
      check_interval: 1s
      limit_percentage: 75
      spike_limit_percentage: 20

    k8sattributes:
      auth_type: serviceAccount
      passthrough: false
      extract:
        metadata:
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.namespace.name
          - k8s.node.name
          - k8s.container.name

    resource:
      attributes:
        - action: insert
          key: service.name
          from_attribute: k8s_container_name
        - action: insert
          key: stream_name
          value: k8s_logs

    batch:
      send_batch_size: 1000
      timeout: 5s

  exporters:
    otlphttp/openobserve:
      endpoint: "http://openobserve-openobserve-standalone.openobserve.svc.cluster.local:5080/api/default"
      headers:
        # Basic Auth: root@example.com:Complexpass#123 -> Base64
        Authorization: "Basic cm9vdEBleGFtcGxlLmNvbTpDb21wbGV4cGFzcyMxMjM="
        stream-name: "k8s_logs"
      tls:
        insecure: true

  service:
    pipelines:
      logs:
        receivers: [filelog]
        processors: [memory_limiter, k8sattributes, resource, batch]
        exporters: [otlphttp/openobserve]

# Mount Host Log Directories
extraVolumes:
  - name: varlogpods
    hostPath:
      path: /var/log/pods
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers

extraVolumeMounts:
  - name: varlogpods
    mountPath: /var/log/pods
    readOnly: true
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true

# กำหนด Resources สำหรับ Log Shipper
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 250m
    memory: 256Mi
```

### 3.4 รายการ Dashboard Templates (`dashboards/`) และ PromQL Queries

1. **`k8s-cluster-overview.json` (Cluster & Node Overview):**
   - **Cluster CPU Utilization (%):** `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
   - **Cluster Memory Utilization (%):** `(1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))) * 100`
   - **Node CPU Usage by Node:** `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
   - **Node Memory Usage by Node:** `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`
   - **Node Disk Free Space:** `node_filesystem_avail_bytes{mountpoint="/"}`
   - **Node Network In/Out:** `rate(node_network_receive_bytes_total[5m])`, `rate(node_network_transmit_bytes_total[5m])`

2. **`k8s-workload-metrics.json` (Pods & Workloads Performance):**
   - **Pod Status Breakdown:** `sum by (phase) (kube_pod_status_phase)`
   - **Container CPU Usage by Pod:** `sum by (pod, namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))`
   - **Container Memory Working Set by Pod:** `sum by (pod, namespace) (container_memory_working_set_bytes{container!=""})`
   - **Pod Restart Counts:** `sum by (pod, namespace) (increase(kube_pod_container_status_restarts_total[1h]))`

---

## 4. Commands (คำสั่งในการติดตั้งและจัดการ)

### 4.1 การเพิ่ม Helm Repositories
```bash
helm repo add openobserve https://charts.openobserve.ai
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

### 4.2 การติดตั้ง OpenObserve และ Secret
```bash
# ติดตั้ง OpenObserve Standalone (พร้อม Retention 1 วัน)
helm upgrade --install openobserve openobserve/openobserve-standalone \
  --namespace openobserve \
  --create-namespace \
  -f helm/openobserve-values.yaml

# สร้าง Secret สำหรับ Basic Auth
kubectl create secret generic openobserve-auth \
  --from-literal=ZO_ROOT_USER_EMAIL="root@example.com" \
  --from-literal=ZO_ROOT_USER_PASSWORD="Complexpass#123" \
  -n openobserve --dry-run=client -o yaml | kubectl apply -f -
```

### 4.3 การติดตั้ง kube-prometheus-stack (Metrics)
```bash
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace openobserve \
  -f helm/kps-values.yaml
```

### 4.4 การติดตั้ง OpenTelemetry Collector (Container Logs)
```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace openobserve \
  -f helm/otel-collector-values.yaml
```

### 4.5 การ Provision Dashboards เข้า OpenObserve REST API
```bash
./scripts/import-dashboards.sh
```

### 4.6 การทดสอบและตรวจสอบสถานะทั้งระบบ (Automated End-to-End)
```bash
# รันการทดสอบทั้งหมด (Health, Retention Policy, Metrics Ingestion, Log Ingestion, Dashboards, Resilience)
./scripts/run-all-tests.sh
```

---

## 5. Project Structure

```
openobserve-standalone-k8s-lab/
├── dashboards/
│   ├── k8s-cluster-overview.json   # Template Dashboard Cluster & Node ด้วย PromQL
│   └── k8s-workload-metrics.json   # Template Dashboard Pods & Workloads ด้วย PromQL
├── helm/
│   ├── openobserve-values.yaml     # คอนฟิก OpenObserve Standalone, MinIO และ Retention (1 วัน)
│   ├── kps-values.yaml             # คอนฟิก kube-prometheus-stack (Agent Mode + Remote Write)
│   └── otel-collector-values.yaml  # คอนฟิก OpenTelemetry Collector (DaemonSet + Container Logs)
├── scripts/
│   ├── deploy.sh                   # สคริปต์ติดตั้ง OpenObserve + KPS + OTel Collector + Dashboards
│   ├── cleanup.sh                  # สคริปต์ Uninstall Releases และลบ PVCs/CRDs
│   ├── verify-health.sh            # ตรวจสอบสถานะ Pods, PVCs, Service และ Retention Env
│   ├── test-metrics.sh             # ตรวจสอบ Prometheus Stream Ingestion ผ่าน API
│   ├── test-logs.sh                # ตรวจสอบ Container Log Ingestion ผ่าน Search API
│   ├── test-dashboards.sh          # ตรวจสอบความถูกต้องของ Dashboards ผ่าน API
│   ├── test-resilience.sh          # ทดสอบความคงทนของข้อมูลเมื่อ Restart Pod
│   ├── import-dashboards.sh        # สคริปต์ Auto-provision Dashboards ผ่าน API
│   └── run-all-tests.sh            # รันการทดสอบทุกชุดแบบอัตโนมัติ
├── specs/
│   ├── research.md                 # การศึกษาสถาปัตยกรรม OpenObserve & Prometheus & Logs
│   ├── 0-open-observe-standalone-setup.md # เอกสาร Spec ฉบับนี้
│   └── 1-workshop-setup.md         # Workshop Hands-on Lab Spec
└── README.md                       # คู่มือการใช้งานระบบฉบับสมบูรณ์
```

---

## 6. Testing & Verification Strategy

| ขั้นตอนการตรวจสอบ | คำสั่งและวิธีการทดสอบ | เกณฑ์การผ่าน (Acceptance Criteria) |
|---|---|---|
| **Platform & Collectors Pods** | `./scripts/verify-health.sh` | Pods ทั้งหมดใน `openobserve` (`openobserve`, `minio`, `kps-prometheus`, `node-exporter`, `kube-state-metrics`, `otel-collector`) อยู่ในสถานะ `Running` และ PVCs `Bound` |
| **Retention Policy Verification** | ตรวจสอบผ่าน Pod Environment และ API | OpenObserve Pod มี Environment `ZO_DATA_RETENTION_DAYS=1` และ `ZO_COMPACTOR_INTERVAL=300s` และ Compactor ทำงานต่อเนื่อง |
| **Web UI Access** | ตรวจสอบผ่าน HTTP Port 5080/30080 | หน้า Web UI ตอบกลับ HTTP 200 และล็อกอินด้วย Root User ได้สำเร็จ |
| **Prometheus Ingestion** | `./scripts/test-metrics.sh` | มี Stream `prometheus` ใน OpenObserve และดึงค่า metrics หลัก (`node_cpu_seconds_total`, `node_memory_MemTotal_bytes`, `container_cpu_usage_seconds_total`, `kube_pod_status_phase`) ได้ครบถ้วน |
| **Container Log Ingestion** | `./scripts/test-logs.sh` | มี Stream `k8s_logs` (หรือ OTLP log stream) ใน OpenObserve พร้อมมี Record log จาก pods ใน cluster (`kube-system`, `openobserve`) และมีฟิลด์ metadata (`k8s_namespace_name`, `k8s_pod_name`, `k8s_container_name`) ครบถ้วน |
| **PromQL Dashboards** | `./scripts/test-dashboards.sh` | Dashboards `k8s-cluster-overview` และ `k8s-workload-metrics` ถูก Import เข้า OpenObserve สมบูรณ์ แสดงผลกราฟได้ถูกต้อง |
| **Object Storage Persistence** | ตรวจสอบ MinIO Storage | Parquet Files ของทั้ง metrics และ logs ถูกบันทึกลง MinIO อย่างต่อเนื่อง |
| **Restart Resilience** | `./scripts/test-resilience.sh` | สั่ง Restart OpenObserve Pod แล้วข้อมูล Metrics ย้อนหลัง, Logs และ Dashboards ยังอยู่ครบ 100% |

---

## 7. Boundaries & Operational Guardrails

- **สิ่งที่ต้องทำเสมอ (Always):**
  - กำหนด `ZO_DATA_RETENTION_DAYS: "1"` เพื่อป้องกันพื้นที่ MinIO เต็มใน Lab Cluster
  - ตั้งรอบ `ZO_COMPACTOR_INTERVAL` ให้เหมาะสม (5 นาที / 300 วินาที) เพื่อลบข้อมูลเก่าและ Merge parquet files สม่ำเสมอ
  - รัน Prometheus ใน Agent Mode เพื่อป้องกันปัญหา Resource Exhaustion
  - Exclude log files ของตัว OTel Collector เองใน `filelog` receiver เพื่อป้องกัน Log Loop
  - จัดการ Credentials ผ่าน Kubernetes Secret และใช้อ้างอิงแบบ Declarative ใน Values
  - เก็บ Dashboard Templates เป็น Declarative JSON ใน Version Control
  - ตรวจสอบให้แน่ใจว่าสคริปต์ทั้งหมดรองรับทั้งการติดตั้งใหม่ (Clean Install) และการรันซ้ำ (Idempotent)
- **สิ่งที่ต้องสอบถามก่อน (Ask First):**
  - การปรับเปลี่ยน Data Retention จาก 1 วันไปเป็นค่าอื่นในอนาคต (เช่น 7 วัน หรือ 30 วัน)
  - การเปิดใช้งาน Grafana หรือ Alertmanager เพิ่มเติมใน Stack
- **สิ่งที่ห้ามทำเด็ดขาด (Never):**
  - ห้าม Hardcode Password ในไฟล์ Values หรือ Manifests ที่ Commit เข้า Git
  - ห้ามปิดการทำงานของ Compactor ใน OpenObserve ซึ่งจะส่งผลให้ Retention Policy ไม่ถูกประมวลผล
  - ห้ามเปิด TSDB Storage ขนาดใหญ่บน Prometheus Pod เมื่อยิง Remote Write ไปยัง OpenObserve อยู่แล้ว

---

## 8. Success Criteria

1. มีไฟล์ Values Configuration [`helm/openobserve-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/openobserve-values.yaml) ที่กำหนด Retention Policy ไว้ที่ 1 วัน (`ZO_DATA_RETENTION_DAYS: 1`) ควบคู่กับรอบ Compactor 5 นาที (`ZO_COMPACTOR_INTERVAL: 300s`)
2. มีไฟล์ Values Configuration [`helm/kps-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/kps-values.yaml) สำหรับ Metrics (kube-prometheus-stack) และ [`helm/otel-collector-values.yaml`](file:///home/panupong/github/openobserve-standalone-k8s-lab/helm/otel-collector-values.yaml) สำหรับ Container Logs (OpenTelemetry Collector)
3. OpenObserve สามารถรับและค้นหา Container Logs จากทุกลุ่ม Pods ใน Cluster ผ่าน Stream `k8s_logs` โดยมี K8s Metadata ครบถ้วน
4. Dashboard JSON Templates (`k8s-cluster-overview.json`, `k8s-workload-metrics.json`) ทำงานด้วย PromQL ได้ถูกต้อง
5. ชุดสคริปต์ Automation (`deploy.sh`, `cleanup.sh`, `verify-health.sh`, `test-logs.sh`) รองรับการทดสอบผ่านคำสั่ง `./scripts/run-all-tests.sh` ครบ 100% พร้อมตรวจยืนยัน Retention Policy
