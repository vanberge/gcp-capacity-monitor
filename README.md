# Universal GCP Capacity & Stockout Monitoring (GKE, GCE, Cloud SQL)

A production-ready Google Cloud Operations monitoring package that tracks hardware capacity constraints, resource exhaustions, and stockouts across **Google Kubernetes Engine (GKE)**, **Google Compute Engine (GCE)**, and **Cloud SQL**.

---

## Architecture & Dashboards

This solution provides **four custom Cloud Monitoring dashboards** and **seven log-based metrics** to deliver both cross-service executive visibility and granular service-level troubleshooting:

```
.
├── dashboards/
│   ├── dashboard-overview.json          # Executive Roll-Up (GKE, GCE, Cloud SQL)
│   ├── dashboard-gke.json               # Dedicated GKE Capacity & Node Auto-Provisioning
│   ├── dashboard-gce.json               # Dedicated Compute Engine (VMs & MIGs) Stockouts
│   └── dashboard-cloudsql.json          # Dedicated Cloud SQL Database Stockouts
├── dashboard.json                       # Root dashboard (Executive Overview)
├── metrics/
│   ├── metric-gcp-stockouts.yaml                    # Universal cross-service stockouts
│   ├── metric-gke-stockouts.yaml                    # GKE pod FailedScaleUp & node stockouts
│   ├── metric-gke-provisioning-successes.yaml       # GKE node additions by machine family
│   ├── metric-gce-stockouts.yaml                    # GCE VM creation & start stockouts
│   ├── metric-gce-provisioning-successes.yaml       # GCE VM creations
│   ├── metric-cloudsql-stockouts.yaml               # Cloud SQL creation, resize, & failover stockouts
│   └── metric-cloudsql-provisioning-successes.yaml  # Cloud SQL database creations & resizes
├── deploy.sh                            # Turnkey deployment script
├── terraform/                           # Infrastructure as Code (IaC) module
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── .gitignore
└── README.md
```

---

## 1. Dashboards Overview

### 1. Executive Roll-Up Dashboard (`dashboard-overview.json`)
* **Fleet Stockout Breakdown**: Real-time comparison of stockouts across GKE, GCE, and Cloud SQL.
* **Geographic Distribution**: Stockout trends mapped across zones and regions.
* **Provisioning Velocity**: Fleet-wide successful resource creations across all three engines.
* **Universal Raw Error Stream**: Aggregated activity logs of all capacity failures across the project.

### 2. GKE Dedicated Dashboard (`dashboard-gke.json`)
* **Multi-Cluster Zonal Stockouts**: Tracks Kubernetes autoscaler `FailedScaleUp: GCE out of resources` and GCE `ZONE_RESOURCE_POOL_EXHAUSTED` for node instances.
* **Machine Family Breakdown**: Automatically parses and graphs provisioning successes across machine families (`n4`, `n2`, `c3d`, `t2d`, `e2`, etc.) using regex extraction from Node Auto-Provisioning (NAP) / ComputeClasses.
* **Comparative Trends**: Correlates primary instance type stockouts against secondary fallback pool spin-ups.
* **Autoscaler Log Stream**: Live stream of cluster-autoscaler and instance insertion audit logs.

### 3. Compute Engine Dedicated Dashboard (`dashboard-gce.json`)
* **Scope**: Standalone Compute Engine VMs and Managed Instance Groups (MIGs), cleanly filtering out GKE nodes.
* **Operations Tracked**: Both new instance creation (`compute.instances.insert`) and starting stopped instances (`compute.instances.start`).
* **Zonal Hotspotting**: Identifies specific zones experiencing hardware inventory exhaustion.
* **Raw Compute Audit Stream**: Detailed error payloads with specific machine types and sub-reasons.

### 4. Cloud SQL Dedicated Dashboard (`dashboard-cloudsql.json`)
* **Scope**: Managed PostgreSQL, MySQL, and SQL Server instances.
* **Operations Tracked**: New database provisioning (`create`), machine tier scaling/resizing (`update`), restarts, and High Availability (HA) failovers.
* **Regional Breakdown**: Visualizes regional and zonal capacity stalls when allocating database compute instances.
* **Raw Cloud SQL Activity Stream**: Logs matching `resource.type="cloudsql_database"` with `ZONE_RESOURCE_POOL_EXHAUSTED`, `stockout`, or code `8` (`RESOURCE_EXHAUSTED`).

---

## 2. Metric Specifications

| Metric Name | Type | Log Filter Scope | Extracted Labels |
| :--- | :--- | :--- | :--- |
| `gcp_capacity_stockouts` | Delta INT64 | Cross-service capacity failures across GKE, GCE, and Cloud SQL | `service_name` |
| `gke_node_provisioning_stockouts` | Delta INT64 | `k8s_pod` FailedScaleUp + GCE instance insert errors for GKE | `zone` |
| `gke_node_provisioning_successes` | Delta INT64 | Successful auto-provisioned GKE node inserts | `machine_family` |
| `gce_instance_stockouts` | Delta INT64 | Non-GKE `compute.instances.insert` / `start` errors | `zone`, `method` |
| `gce_instance_provisioning_successes` | Delta INT64 | Successful non-GKE `compute.instances.insert` operations | `zone` |
| `cloudsql_instance_stockouts` | Delta INT64 | Cloud SQL `create`, `update`, `failover`, `restart` errors | `region`, `database_id`, `method` |
| `cloudsql_instance_provisioning_successes` | Delta INT64 | Successful Cloud SQL `create` and `update` operations | `region`, `database_id`, `method` |

---

## 3. Deployment

### Option 1: Turnkey Shell Script

Deploy all metrics and all four dashboards with a single command:

```bash
git clone https://github.com/vanberge/gke-capacity-monitor.git
cd gke-capacity-monitor
./deploy.sh [TARGET_PROJECT_ID]
```

*(If `TARGET_PROJECT_ID` is omitted, the script automatically targets your active `gcloud` config project).*

The script outputs direct Google Cloud Console URLs for each of the four dashboards upon completion.

### Option 2: Terraform (GitOps)

To manage this monitoring suite via Terraform:

```bash
cd terraform
terraform init
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

---

## 4. Prerequisites & Permissions

Ensure your deploying identity possesses:
* `roles/logging.configWriter` (to create and update log-based metrics)
* `roles/monitoring.editor` (to deploy custom Cloud Monitoring dashboards)

> [!NOTE]
> Log-based metrics collect data starting from the moment they are created (they do not retroactively backfill past events into time series). However, the **Details Pane (Logs Panel)** on each dashboard directly queries Cloud Logging and immediately displays historical events.

---

## 5. Stockout Mitigation Playbooks

### When GKE Stockouts Occur:
1. **Leverage GKE ComputeClasses**: Configure multi-family fallback lists (e.g. prioritize `N4`, with automatic fallback to `N2D`, `T2D`, or `C3D`).
2. **Multi-Zone / Regional Clusters**: Spread node pools across multiple availability zones.
3. **Use Node Auto-Provisioning (NAP)**: Allow the cluster autoscaler to evaluate multiple instance types when scaling up.

### When GCE Stockouts Occur:
1. **Regional MIGs with `BALANCED` Distribution**: Configure Managed Instance Groups across multiple zones with flexible instance shapes.
2. **Instance Family Diversification**: Shift temporarily to alternative generations (e.g. from `c2` to `c3` or `n2`).
3. **Compute Engine Reservations**: Reserve critical capacity in specific target zones for predictable workloads.

### When Cloud SQL Stockouts Occur:
1. **High Availability (HA)**: Deploy in HA configuration with a standby replica in a secondary zone to allow failover.
2. **Alternative Machine Shapes**: Adjust instance tiers (e.g., standard custom vCPUs vs high-mem or shared-core tiers) during peak regional demand.
3. **Zonal Placement**: If launching a new replica or standalone database, select an adjacent availability zone in the same region.
